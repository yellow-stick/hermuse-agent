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

/// The install cannot start or resume on its own, and nothing was modified:
/// the target directory holds a checkout Hermuse did not install, or the
/// install journal cannot be read. The user resolves it (the message says
/// how); retrying a stage does not.
final class InstallBlocked extends HostException {
  const InstallBlocked(super.message);
}

/// A required prerequisite (tool, OS capability) is missing.
final class PrerequisiteMissing extends HostException {
  const PrerequisiteMissing(super.message, {this.fixCommand});
  final String? fixCommand;
}

/// The CLIProxyAPI binary cannot be trusted: incomplete bundle metadata,
/// wrong platform, missing binary or `cliproxy.lock`, or a hash mismatch.
final class CliproxyVerificationFailed extends HostException {
  const CliproxyVerificationFailed(super.message);
}

/// The Linux setup helper cannot be used: this build carries no helper
/// digest (`HERMUSE_LINUX_HELPER_SHA256`), or the development helper was
/// asked for outside a development build.
final class LinuxSetupUnavailable extends HostException {
  const LinuxSetupUnavailable(super.message);
}
