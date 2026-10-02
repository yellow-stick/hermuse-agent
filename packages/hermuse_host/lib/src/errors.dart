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

/// The SSH host key was not explicitly accepted.
final class RemoteHostKeyRejected extends HostException {
  const RemoteHostKeyRejected()
    : super('The SSH host key was not accepted. Nothing was installed.');
}

/// An SSH reconnect presented a different key from the accepted server.
final class RemoteHostKeyChanged extends HostException {
  const RemoteHostKeyChanged(super.message);
}

/// The SSH server refused the supplied login.
final class RemoteAuthFailed extends HostException {
  const RemoteAuthFailed()
    : super('SSH authentication failed. Check the user name and password.');

  const RemoteAuthFailed.key()
    : super(
        'SSH key authentication failed. Check the user name and that this '
        'machine’s key is authorized for that account. Unlock the key in your '
        'SSH agent, or enter an SSH password.',
      );
}

/// No existing SSH key could be used for a password-free login.
final class RemoteSshKeyUnavailable extends HostException {
  const RemoteSshKeyUnavailable()
    : super(
        'No usable SSH key was found on this machine. Load your key into the '
        'SSH agent (unlock encrypted keys first), or enter an SSH password. '
        'Hermuse also checks unencrypted id_ed25519, id_ecdsa and id_rsa files '
        'in your home .ssh directory.',
      );
}

/// The SSH server could not be reached or its handshake failed.
final class RemoteUnreachable extends HostException {
  const RemoteUnreachable(super.message);
}

/// A remote provisioning stage failed; later stages were not attempted.
final class RemoteInstallFailed extends HostException {
  const RemoteInstallFailed(this.step, super.message);
  final String step;
}

/// The user cancelled an in-memory remote installation attempt.
final class RemoteInstallCancelled extends HostException {
  const RemoteInstallCancelled() : super('Remote installation cancelled.');
}
