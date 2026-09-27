import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/local_host.dart';
import 'route.dart';

/// Gates [child] on the Hermuse plugin backend of [instance].
///
/// Missing plugin: the local (Hermuse-supervised) instance offers a one-tap
/// install of the bundled plugin; any other instance installs it through its
/// dashboard, with the commands to run on its host as a fallback. When
/// the local install could not set up the agent's computer for lack of
/// Docker, a notice stays under [child] while the route is open.
final class PluginGate extends ConsumerStatefulWidget {
  const PluginGate({
    required this.instance,
    required this.title,
    required this.child,
    super.key,
  });

  final HermesInstance instance;

  /// Route title while loading / when missing.
  final String title;
  final Widget child;

  @override
  ConsumerState<PluginGate> createState() => _PluginGateState();
}

final class _PluginGateState extends ConsumerState<PluginGate> {
  /// Computer step of the install run from this gate.
  ComputerSetup? _computer;

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;
    final title = widget.title;
    final status = ref.watch(pluginStatusProvider(instance.id));
    return switch (status) {
      AsyncData(value: PluginPresence.installed) => switch (_computer) {
        ComputerSetup.dockerMissing || ComputerSetup.dockerNotRunning => Column(
          children: [
            Expanded(child: widget.child),
            _DockerNotice(
              dockerMissing: _computer == ComputerSetup.dockerMissing,
            ),
          ],
        ),
        _ => widget.child,
      },
      AsyncData(value: PluginPresence.missing) => _PluginMissing(
        instance: instance,
        title: title,
        onInstalled: (setup) => setState(() => _computer = setup),
      ),
      AsyncError(:final error) => HermuseRoute(
        title: title,
        children: [
          HermuseRouteError('Could not reach the Hermuse plugin: $error'),
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.neutral(
              label: 'Check again',
              onPressed: () =>
                  ref.invalidate(pluginStatusProvider(instance.id)),
            ),
          ),
        ],
      ),
      _ => HermuseRoute(
        title: title,
        children: const [HermuseRouteSub('Loading…')],
      ),
    };
  }
}

/// Non-blocking notice after an install whose computer step needs Docker:
/// the plugin works, the agent's browser stays hidden until Docker runs.
final class _DockerNotice extends StatelessWidget {
  const _DockerNotice({required this.dockerMissing});

  /// Docker is not installed (else installed but not running).
  final bool dockerMissing;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ColoredBox(
      color: palette.canvasColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: YsLayout.threadMaxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: YsLayout.threadGutter,
              vertical: 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: HermuseRouteSub(
                    dockerMissing
                        ? "Install Docker to let Hermuse show the agent's browser."
                        : "Start Docker to let Hermuse show the agent's browser.",
                  ),
                ),
                if (dockerMissing) ...[
                  const SizedBox(width: 12),
                  YsButton.neutral(
                    label: 'Get Docker',
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse(
                          'https://docs.docker.com/get-started/get-docker/',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _PluginMissing extends ConsumerStatefulWidget {
  const _PluginMissing({
    required this.instance,
    required this.title,
    required this.onInstalled,
  });

  final HermesInstance instance;
  final String title;

  /// The install succeeded; its computer step may need Docker.
  final ValueChanged<ComputerSetup> onInstalled;

  @override
  ConsumerState<_PluginMissing> createState() => _PluginMissingState();
}

final class _PluginMissingState extends ConsumerState<_PluginMissing> {
  var _busy = false;
  String? _error;
  List<PluginScanFinding> _findings = const [];

  /// The dashboard installed the plugin but must restart to serve it.
  var _needsRestart = false;

  /// Hermes' scan report while the install waits for the user's consent.
  String? _consent;

  Future<void> _install(LocalHermesHost host) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final install = await host.installPlugin(
        await ref.read(registryProvider.future),
      );
      if (mounted) widget.onInstalled(install.computerSetup);
      // The backend restarted on a new port: reopen the connection and the
      // chats that held the old one.
      ref.invalidate(connectionProvider(widget.instance.id));
      ref.invalidate(chatSessionProvider);
      ref.invalidate(pluginStatusProvider(widget.instance.id));
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Installs through the remote dashboard (see [installHermusePlugin]);
  /// [force] once the user allowed a "caution" scan verdict.
  Future<void> _installRemote({bool force = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _findings = const [];
      _needsRestart = false;
    });
    try {
      final rest = await ref.read(
        restClientProvider(widget.instance.id).future,
      );
      final result = await installHermusePlugin(rest, force: force);
      if (!mounted) return;
      setState(() => _consent = null);
      switch (result) {
        case PluginInstalled():
          ref.invalidate(pluginStatusProvider(widget.instance.id));
        case PluginNeedsConsent(:final detail):
          setState(() => _consent = detail);
        case PluginNeedsDashboardRestart():
          setState(() => _needsRestart = true);
        case PluginInstallFailed(:final message, :final findings):
          setState(() {
            _error = message;
            _findings = findings;
          });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final host = ref.watch(localHostProvider);
    final local =
        host != null &&
        widget.instance.kind == InstanceKind.local &&
        host.supervisor != null;
    return HermuseRoute(
      title: widget.title,
      children: [
        Text(
          'Enable the Hermuse plugin',
          style: YsType.heading.flutter.copyWith(color: palette.contentColor),
        ),
        HermuseRouteSub(
          'Feed, Ideas, Goals and Library live on your Hermes instance. '
          '${local ? 'Hermuse can install the plugin on this computer.' : 'Hermuse can install the plugin on ${widget.instance.label}.'}',
        ),
        if (_consent case final consent?) ...[
          const HermuseRouteSub(
            'Hermuse needs permission to install Docker with sudo on this '
            'server (Hermes flags this for review).',
          ),
          Text(
            consent,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.primary(
              label: _busy ? 'Installing…' : 'Allow and install',
              onPressed: _busy
                  ? null
                  : () => unawaited(_installRemote(force: true)),
            ),
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.primary(
              label: _busy
                  ? 'Installing…'
                  : local
                  ? 'Install the plugin'
                  : 'Install Hermuse on this Hermes',
              onPressed: _busy
                  ? null
                  : () => unawaited(local ? _install(host) : _installRemote()),
            ),
          ),
        if (_needsRestart) ...[
          const HermuseRouteSub(
            'Restart the Hermes dashboard to finish installing Hermuse. '
            'Under systemd run the command below; otherwise stop '
            '`hermes dashboard` and start it again. Then check again.',
          ),
          const HermuseCodeBlock('systemctl --user restart hermes-dashboard'),
        ],
        if (_error case final error?) HermuseRouteError(error),
        if (_findings.isNotEmpty)
          HermuseCodeBlock([for (final f in _findings) '$f'].join('\n')),
        if (!local) ...[
          HermuseRouteSub(
            'Or run these commands where ${widget.instance.label} runs, '
            'then restart its gateway:',
          ),
          const HermuseCodeBlock(
            'cp -r hermes-plugin/hermuse ~/.hermes/plugins/hermuse\n'
            'hermes plugins enable hermuse\n'
            'hermes hermuse enable\n'
            'hermes hermuse doctor',
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: YsButton.neutral(
            label: 'Check again',
            onPressed: () =>
                ref.invalidate(pluginStatusProvider(widget.instance.id)),
          ),
        ),
      ],
    );
  }
}
