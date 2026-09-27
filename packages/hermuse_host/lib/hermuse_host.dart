/// Desktop-only host services: Hermes detection, staged install, process
/// supervision, and the CLIProxyAPI sidecar. `dart:io` only.
library;

export 'src/bridge_host.dart';
export 'src/cliproxy_binary.dart';
export 'src/cliproxy_supervisor.dart';
export 'src/detector.dart';
export 'src/errors.dart';
export 'src/hermes_supervisor.dart';
export 'src/installer.dart';
export 'src/plugin_installer.dart';
export 'src/supervisor.dart';
