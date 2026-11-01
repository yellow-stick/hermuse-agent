import 'dart:async';
import 'dart:math' as math;

import 'package:hermes_contract/hermes_contract.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket/web_socket.dart';

import 'errors.dart';
import 'instance.dart';
import 'json_rpc.dart';
import 'rest.dart';
import 'secrets.dart';
import 'transport.dart';

/// Opens a WebSocket; injectable for tests.
typedef WebSocketConnector = Future<WebSocket> Function(Uri uri);

/// Transport over the dashboard gateway `/api/ws` (same protocol as Hermes
/// Desktop): status probe → auth → WS upgrade → `gateway.ready` →
/// `client.capabilities`, with exponential-backoff reconnection.
final class DashboardTransport implements HermesTransport {
  DashboardTransport._(
    this.instance,
    this.rest,
    this._secrets,
    this._connector,
    this._pingInterval,
    this._readyTimeout,
  );

  /// Connects to [instance]; throws [HermesException] when the first
  /// connection fails (unreachable, credentials, unsupported version).
  static Future<DashboardTransport> connect({
    required HermesInstance instance,
    required SecretStore secrets,
    required http.Client httpClient,
    WebSocketConnector connector = WebSocket.connect,
    Duration pingInterval = const Duration(seconds: 25),
    Duration readyTimeout = const Duration(seconds: 20),
  }) async {
    final token = instance.auth == AuthMethod.loopbackToken
        ? await secrets.read(instance.id, SecretKeys.sessionToken)
        : null;
    final rest = HermesRestClient(
      httpClient,
      baseUrl: instance.baseUrl,
      sessionToken: token,
      profile: instance.profile ?? 'default',
    );
    final transport = DashboardTransport._(
      instance,
      rest,
      secrets,
      connector,
      pingInterval,
      readyTimeout,
    );
    try {
      await transport._open();
    } on Object {
      await transport.close();
      rethrow;
    }
    return transport;
  }

  static const _maxBackoff = Duration(seconds: 30);

  final HermesInstance instance;

  /// Authenticated REST client of the same instance.
  final HermesRestClient rest;
  final SecretStore _secrets;
  final WebSocketConnector _connector;
  final Duration _pingInterval;
  final Duration _readyTimeout;

  final _peer = JsonRpcPeer();
  final _states = StreamController<ConnectionState>.broadcast(sync: true);
  ConnectionState _state = ConnectionState.connecting;
  Object? _lastError;
  WebSocket? _socket;
  StreamSubscription<WebSocketEvent>? _socketSub;
  Timer? _pingTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _closed = false;

  /// Completed with an error when the socket drops while [_open] runs.
  Completer<Never>? _opening;

  /// Status of the last successful probe.
  HermesStatus? status;

  /// Payload of the last `gateway.ready`.
  GatewayReadyPayload? ready;

  @override
  ConnectionState get currentState => _state;

  @override
  Stream<ConnectionState> get state => _states.stream;

  @override
  Object? get lastError => _lastError;

  @override
  Stream<HermesEvent> get events => _peer.events;

  @override
  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  ) async {
    final json = params.toJson();
    json.putIfAbsent('profile', () => instance.profile ?? 'default');
    return method.decodeResult(await _peer.request(method.name, json));
  }

  @override
  void onServerRequest(ServerRequestHandler handler) {
    _peer.handler = handler;
  }

  @override
  void redeliverServerRequest(
    String id,
    String method,
    Map<String, Object?> params,
  ) => _peer.redeliver(id, method, params);

  void _setState(ConnectionState next, [Object? error]) {
    if (error != null) _lastError = error;
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> _open() async {
    final opening = _opening = Completer<Never>();
    opening.future.ignore(); // Only observed while the handshake awaits it.
    try {
      await _handshake(opening.future);
    } finally {
      _opening = null;
    }
  }

  Future<void> _handshake(Future<Never> dropped) async {
    final status = await rest.getStatus();
    checkSupportedVersion(status.version);
    this.status = status;
    final query = await _wsCredential(status);
    final base = instance.baseUrl;
    final wsUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/api/ws',
      queryParameters: query,
    );
    final WebSocket socket;
    try {
      socket = await _connector(wsUri);
    } on WebSocketException catch (e) {
      throw HermesUnreachable('${base.origin}: ${e.message}');
    }
    _socket = socket;
    final readyEvent = _peer.events
        .where((e) => e is GatewayReadyEvent)
        .cast<GatewayReadyEvent>()
        .first;
    _socketSub = socket.events.listen(
      (event) => switch (event) {
        TextDataReceived(:final text) => _peer.receive(text),
        BinaryDataReceived() => null,
        CloseReceived(:final code, :final reason) => _onDropped(
          socket,
          HermesConnectionLost('socket closed ($code $reason)'),
        ),
      },
      onError: (Object e) => _onDropped(socket, HermesConnectionLost('$e')),
      onDone: () => _onDropped(socket, const HermesConnectionLost('closed')),
    );
    _peer.sink = socket.sendText;
    try {
      ready = (await Future.any([readyEvent, dropped]).timeout(_readyTimeout))
          .payload;
    } on TimeoutException {
      throw const HermesUnreachable('no gateway.ready from /api/ws');
    }
    // Without this every server → client request (approval, clarify…) is refused.
    await Future.any([
      _peer.call(
        HermesMethods.clientCapabilities,
        const ClientCapabilitiesParams(serverRequests: true),
      ),
      dropped,
    ]);
    _attempt = 0;
    _startPing(socket);
    _setState(ConnectionState.ready);
  }

  Future<Map<String, String>> _wsCredential(HermesStatus status) async {
    switch (instance.auth) {
      case AuthMethod.loopbackToken:
        final token = rest.sessionToken;
        if (token == null) {
          throw const HermesAuthFailed('missing loopback session token');
        }
        if (status.authRequired) {
          throw const HermesAuthFailed(
            'instance requires a login; loopback token refused',
          );
        }
        return {'token': token};
      case AuthMethod.password:
        if (!status.authRequired) {
          throw const HermesAuthFailed(
            'instance has no login gate; only loopback clients are accepted',
          );
        }
        try {
          return {'ticket': await rest.mintWsTicket()};
        } on HermesAuthFailed {
          await _passwordLogin(status);
          return {'ticket': await rest.mintWsTicket()};
        }
      case AuthMethod.nativeOAuth:
        throw UnimplementedError('native PKCE sign-in');
    }
  }

  Future<void> _passwordLogin(HermesStatus status) async {
    final username = await _secrets.read(instance.id, SecretKeys.username);
    final password = await _secrets.read(instance.id, SecretKeys.password);
    if (username == null || password == null) {
      throw const HermesAuthFailed('no stored credentials');
    }
    final provider = status.authProviders.contains('basic')
        ? 'basic'
        : status.authProviders.firstOrNull ?? 'basic';
    await rest.passwordLogin(
      username: username,
      password: password,
      provider: provider,
    );
  }

  void _startPing(WebSocket socket) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) async {
      try {
        await _peer.request('gateway.ping', null).timeout(_pingInterval);
      } on Object catch (e) {
        _onDropped(socket, HermesConnectionLost('heartbeat: $e'));
      }
    });
  }

  void _onDropped(WebSocket socket, HermesConnectionLost error) {
    if (!identical(socket, _socket)) return;
    _teardownSocket(error);
    if (_closed) return;
    if (_opening case final opening? when !opening.isCompleted) {
      opening.completeError(error); // _open reports it.
      return;
    }
    _scheduleReconnect(error);
  }

  void _teardownSocket(Object error) {
    _pingTimer?.cancel();
    _pingTimer = null;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    _peer.sink = null;
    _peer.failAll(error);
    if (socket != null) unawaited(socket.close().catchError((_) {}));
  }

  void _scheduleReconnect(Object error) {
    _setState(ConnectionState.reconnecting, error);
    final seconds = math.min(1 << _attempt, _maxBackoff.inSeconds);
    _attempt = math.min(_attempt + 1, 5);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () async {
      if (_closed) return;
      try {
        await _open();
      } on HermesAuthFailed catch (e) {
        _teardownSocket(e);
        _setState(ConnectionState.error, e);
      } on UnsupportedServerVersion catch (e) {
        _teardownSocket(e);
        _setState(ConnectionState.error, e);
      } on UnimplementedError catch (e) {
        _teardownSocket(e);
        _setState(ConnectionState.error, e);
      } on Object catch (e) {
        _teardownSocket(e);
        if (!_closed) _scheduleReconnect(e);
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _teardownSocket(const HermesConnectionLost('transport closed'));
    _setState(ConnectionState.disconnected);
    await _peer.close();
    await _states.close();
  }
}
