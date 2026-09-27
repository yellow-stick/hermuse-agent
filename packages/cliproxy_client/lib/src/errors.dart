/// Base of every failure surfaced by `cliproxy_client`.
sealed class CliproxyException implements Exception {
  const CliproxyException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The sidecar could not be reached (TCP refused, timeout).
final class CliproxyUnreachable extends CliproxyException {
  const CliproxyUnreachable(super.message);
}

/// The management key was missing or rejected (401), or the caller is banned
/// after too many failures (403).
final class CliproxyAuthFailed extends CliproxyException {
  const CliproxyAuthFailed(super.message, {this.statusCode});
  final int? statusCode;
}

/// A non-success HTTP status from the management API.
final class CliproxyHttpError extends CliproxyException {
  const CliproxyHttpError(this.statusCode, super.message);
  final int statusCode;
}

/// A success-HTTP response without the expected shape.
final class CliproxyProtocolError extends CliproxyException {
  const CliproxyProtocolError(super.message);
}
