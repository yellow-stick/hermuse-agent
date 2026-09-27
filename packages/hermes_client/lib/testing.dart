/// Test doubles. Never import from production code.
library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes_contract/hermes_contract.dart';

import 'src/errors.dart';
import 'src/json_rpc.dart';
import 'src/transport.dart';

/// Scripted server answer: returns the JSON `result`, or throws
/// [FakeRpcError] to answer with a JSON-RPC error.
typedef FakeResponder = Object? Function(Map<String, Object?> params);

final class FakeRpcError implements Exception {
  const FakeRpcError(this.code, this.message);
  final int code;
  final String message;
}

/// A [HermesTransport] running the real JSON-RPC framing against scripted
/// server frames, so tests exercise the same decode paths as production.
final class FakeHermesTransport implements HermesTransport {
  FakeHermesTransport() {
    _peer.sink = _onClientFrame;
  }

  final JsonRpcPeer _peer = JsonRpcPeer();
  final Map<String, FakeResponder> _responders = {};
  final _states = StreamController<ConnectionState>.broadcast(sync: true);
  ConnectionState _state = ConnectionState.ready;
  Object? _lastError;

  /// Every frame the client sent, decoded.
  final List<Map<String, Object?>> sent = [];

  /// Client calls (method + params) in order.
  Iterable<({String method, Map<String, Object?> params})> get calls => sent
      .where((f) => f['method'] is String && f['id'] is int)
      .map(
        (f) => (
          method: f['method'] as String,
          params: f['params'] as Map<String, Object?>,
        ),
      );

  /// Replies sent to server requests, keyed by request id.
  Map<Object?, Map<String, Object?>> get replies => {
    for (final f in sent)
      if (f['method'] == null) f['id']: f,
  };

  /// Scripts the answer of [method].
  void on(String method, FakeResponder responder) {
    _responders[method] = responder;
  }

  /// Delivers a raw server frame.
  void emitFrame(Map<String, Object?> frame) =>
      _peer.receive(jsonEncode(frame));

  /// Delivers an `event` notification.
  void emitEvent(
    String type, {
    String? sessionId,
    int? seq,
    Map<String, Object?>? payload,
  }) => emitFrame({
    'jsonrpc': '2.0',
    'method': 'event',
    'params': {
      'type': type,
      'session_id': ?sessionId,
      'seq': ?seq,
      'payload': ?payload,
    },
  });

  /// Delivers a server → client request.
  void emitRequest(String id, String method, Map<String, Object?> params) =>
      emitFrame({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });

  /// Simulates a connection transition; leaving `ready` fails in-flight calls
  /// like a dropped socket.
  void setState(ConnectionState next, [Object? error]) {
    _lastError = error ?? _lastError;
    _state = next;
    if (next != ConnectionState.ready) {
      _peer.failAll(HermesConnectionLost('fake: $next'));
    }
    _states.add(next);
  }

  void _onClientFrame(String text) {
    final frame = jsonDecode(text) as Map<String, Object?>;
    sent.add(frame);
    final id = frame['id'];
    final method = frame['method'];
    if (id is! int || method is! String) return;
    scheduleMicrotask(() {
      final responder = _responders[method];
      try {
        if (responder == null) throw FakeRpcError(-32601, 'unscripted $method');
        final result = responder(
          frame['params'] as Map<String, Object?>? ?? const {},
        );
        emitFrame({'jsonrpc': '2.0', 'id': id, 'result': result});
      } on FakeRpcError catch (e) {
        emitFrame({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': e.code, 'message': e.message},
        });
      }
    });
  }

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
  ) => _peer.call(method, params);

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

  bool closed = false;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _peer.close();
    await _states.close();
  }
}
