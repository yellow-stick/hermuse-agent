import 'dart:async';
import 'dart:convert';

import 'package:hermes_contract/hermes_contract.dart';

import 'errors.dart';
import 'transport.dart';

/// JSON-RPC 2.0 framing of the Hermes gateway, independent of the socket:
/// client calls with integer ids, `event` notifications, and server requests
/// with string ids (`srq-…`) answered on the same id.
final class JsonRpcPeer {
  JsonRpcPeer([this.sink]);

  /// Current socket writer; null while disconnected (calls then fail fast).
  void Function(String frame)? sink;
  final Map<int, _Pending> _pending = {};
  final _events = StreamController<HermesEvent>.broadcast(sync: true);
  ServerRequestHandler? handler;
  int _nextId = 1;

  /// Server request ids currently awaiting the handler (dedupes redelivery).
  final Set<String> _serving = {};

  Stream<HermesEvent> get events => _events.stream;

  /// Sends a request and resolves with the raw `result`.
  Future<Object?> request(String method, Object? params) {
    final sink = this.sink;
    if (sink == null) {
      return Future.error(HermesConnectionLost('$method: not connected'));
    }
    final id = _nextId++;
    final pending = _Pending(method);
    _pending[id] = pending;
    sink(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params ?? const <String, Object?>{},
      }),
    );
    return pending.completer.future;
  }

  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  ) async => method.decodeResult(await request(method.name, params.toJson()));

  /// Handles one inbound text frame.
  void receive(String text) {
    final Object? frame;
    try {
      frame = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (frame is! Map<String, Object?>) return;
    final method = frame['method'];
    final id = frame['id'];
    if (method == 'event') {
      final params = frame['params'];
      if (params is Map<String, Object?>) _events.add(_decodeEvent(params));
    } else if (method is String && id != null) {
      _serve(id, method, frame['params']);
    } else if (id is int) {
      final pending = _pending.remove(id);
      if (pending == null) return;
      final error = frame['error'];
      if (error is Map<String, Object?>) {
        pending.completer.completeError(
          HermesRpcError(
            pending.method,
            (error['code'] as num?)?.toInt() ?? -32603,
            error['message'] as String? ?? 'error',
            data: error['data'],
          ),
        );
      } else {
        pending.completer.complete(frame['result']);
      }
    }
  }

  HermesEvent _decodeEvent(Map<String, Object?> params) {
    try {
      return HermesEvent.fromParams(params);
    } on Object catch (e) {
      // A payload this client cannot decode must not kill the stream.
      return UnknownHermesEvent(
        type: '${params['type']}',
        sessionId: params['session_id'] as String?,
        seq: (params['seq'] as num?)?.toInt(),
        payload: {'decode_error': '$e', 'payload': params['payload']},
      );
    }
  }

  /// Handles a server request delivered out of band (`open_requests` of
  /// `session.resume` after a reconnect) exactly like a live frame.
  void redeliver(String id, String method, Map<String, Object?> params) =>
      _serve(id, method, params);

  Future<void> _serve(Object id, String method, Object? rawParams) async {
    if (!_serving.add('$id')) return;
    try {
      await _handle(id, method, rawParams);
    } finally {
      _serving.remove('$id');
    }
  }

  Future<void> _handle(Object id, String method, Object? rawParams) async {
    final params = rawParams is Map<String, Object?>
        ? rawParams
        : const <String, Object?>{};
    final HermesServerRequest<JsonObject>? request;
    try {
      request = HermesServerRequest.fromFrame('$id', method, params);
    } on Object catch (e) {
      _reply(id, error: {'code': -32602, 'message': 'invalid params: $e'});
      return;
    }
    final handler = this.handler;
    if (request == null || handler == null) {
      _reply(id, error: {'code': -32601, 'message': 'unsupported: $method'});
      return;
    }
    try {
      final result = await handler(request);
      _reply(id, result: result.toJson());
    } on Object catch (e) {
      _reply(id, error: {'code': -32000, 'message': '$e'});
    }
  }

  void _reply(Object id, {Object? result, Map<String, Object?>? error}) {
    // A reply for a dropped socket is lost; the server re-sends open
    // requests to the reconnected client (`open_requests`).
    sink?.call(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        if (error != null) 'error': error else 'result': result,
      }),
    );
  }

  /// Fails every in-flight call (socket dropped or closed).
  void failAll(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final p in pending) {
      p.completer.completeError(error);
    }
  }

  Future<void> close() async {
    failAll(const HermesConnectionLost('transport closed'));
    await _events.close();
  }
}

final class _Pending {
  _Pending(this.method);
  final String method;
  final completer = Completer<Object?>();
}
