/// Base of every failure surfaced by `hermes_client`.
sealed class HermesException implements Exception {
  const HermesException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The host could not be reached (DNS, TCP, TLS, timeout).
final class HermesUnreachable extends HermesException {
  const HermesUnreachable(super.message);
}

/// Credentials missing, rejected (401) or rate limited (429).
final class HermesAuthFailed extends HermesException {
  const HermesAuthFailed(super.message, {this.statusCode});
  final int? statusCode;
}

/// The instance runs a Hermes version this client was not generated for.
final class UnsupportedServerVersion extends HermesException {
  const UnsupportedServerVersion(this.version, this.supported)
    : super('Hermes $version is not supported (expected $supported.x)');
  final String version;
  final String supported;
}

/// A non-success HTTP status from the dashboard REST API.
final class HermesHttpError extends HermesException {
  const HermesHttpError(this.statusCode, super.message);
  final int statusCode;
}

/// A JSON-RPC error response.
final class HermesRpcError extends HermesException {
  const HermesRpcError(this.method, this.code, super.message, {this.data});
  final String method;
  final int code;
  final Object? data;

  @override
  String toString() => 'HermesRpcError($method, $code): $message';
}

/// The WebSocket dropped while a call was in flight, or the transport closed.
final class HermesConnectionLost extends HermesException {
  const HermesConnectionLost(super.message);
}

/// The request's UI detached without answering; no reply is sent to Hermes.
///
/// A later session resume can deliver the still-open request to a new handler.
final class HermesRequestDetached extends HermesException {
  const HermesRequestDetached() : super('request handler detached');
}
