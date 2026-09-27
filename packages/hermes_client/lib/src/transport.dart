import 'package:hermes_contract/hermes_contract.dart';

/// Lifecycle of a transport as shown to the user.
enum ConnectionState {
  disconnected,
  connecting,
  ready,

  /// The socket dropped; the transport is retrying with backoff.
  reconnecting,

  /// Terminal failure (credentials rejected, unsupported version); see
  /// [HermesTransport.lastError]. No automatic retry.
  error,
}

/// Answers a server → client request. The returned object is sent as the
/// JSON-RPC `result`; a thrown error becomes a JSON-RPC error.
typedef ServerRequestHandler = Future<JsonObject> Function(
  HermesServerRequest<JsonObject> request,
);

/// A JSON-RPC session with one Hermes instance.
abstract interface class HermesTransport {
  ConnectionState get currentState;

  /// Emits every [ConnectionState] transition.
  Stream<ConnectionState> get state;

  /// Cause of the last `reconnecting`/`error` transition.
  Object? get lastError;

  /// Gateway notifications of every session on this connection.
  Stream<HermesEvent> get events;

  /// Sends [method] and decodes its result; throws `HermesRpcError` on a
  /// JSON-RPC error and `HermesConnectionLost` when the socket drops first.
  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  );

  /// Installs the single handler for server → client requests.
  void onServerRequest(ServerRequestHandler handler);

  /// Re-delivers an unanswered request listed in `open_requests` (returned by
  /// `session.resume` after a reconnect) to the handler; the answer goes out
  /// on the current socket. Requests already being handled are ignored.
  void redeliverServerRequest(
    String id,
    String method,
    Map<String, Object?> params,
  );

  /// Closes the socket for good. Idempotent.
  Future<void> close();
}
