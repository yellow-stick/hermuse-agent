import 'package:hermes_contract/hermes_contract.dart';

import 'transport.dart';

/// One instance's transport shared by every chat on it: server requests are
/// routed to the handler registered for their live session id.
final class HermesConnection {
  HermesConnection(this.instanceId, this.transport) {
    transport.onServerRequest(_route);
  }

  final String instanceId;
  final HermesTransport transport;
  final Map<String, ServerRequestHandler> _handlers = {};

  /// Routes requests of [liveSessionId] to [handler] until [unregister].
  void register(String liveSessionId, ServerRequestHandler handler) {
    _handlers[liveSessionId] = handler;
  }

  void unregister(String liveSessionId, ServerRequestHandler handler) {
    if (identical(_handlers[liveSessionId], handler)) {
      _handlers.remove(liveSessionId);
    }
  }

  Future<JsonObject> _route(HermesServerRequest<JsonObject> request) {
    final handler = _handlers[request.sessionId];
    if (handler == null) {
      throw UnsupportedError('no chat open for session ${request.sessionId}');
    }
    return handler(request);
  }
}

/// Resolves the shared connection of an instance, connecting lazily.
abstract interface class HermesConnections {
  Future<HermesConnection> connectionFor(String instanceId);
}
