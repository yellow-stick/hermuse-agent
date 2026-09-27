/// Base of every failure surfaced by `hermuse_host`.
sealed class HostException implements Exception {
  const HostException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A child process failed to spawn, exited unexpectedly, or never became
/// ready. Carries the output tail for the error screen.
final class ProcessFailed extends HostException {
  const ProcessFailed(super.message, {this.exitCode, this.outputTail = ''});
  final int? exitCode;
  final String outputTail;
}

/// The staged installer reported a failing stage.
final class InstallFailed extends HostException {
  const InstallFailed(this.stage, super.message);
  final String stage;
}

/// The installer script could not be obtained (no network, no cache).
final class InstallerUnavailable extends HostException {
  const InstallerUnavailable(super.message);
}

/// A required prerequisite (tool, OS capability) is missing.
final class PrerequisiteMissing extends HostException {
  const PrerequisiteMissing(super.message, {this.fixCommand});
  final String? fixCommand;
}

/// `cliproxy.lock` is missing, unreadable, or a hash does not match.
final class CliproxyVerificationFailed extends HostException {
  const CliproxyVerificationFailed(super.message);
}
