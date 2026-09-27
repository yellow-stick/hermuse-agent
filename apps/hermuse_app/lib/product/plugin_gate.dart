import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/local_host.dart';
import 'route.dart';

/// Gates [child] on the Hermuse plugin backend of [instance].
///
/// Missing plugin: the local (Hermuse-supervised) instance offers a one-tap
/// install; any other instance shows the commands to run on its host.
final class PluginGate extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pluginStatusProvider(instance.id));
    return switch (status) {
      AsyncData(value: PluginPresence.installed) => child,
      AsyncData(value: PluginPresence.missing) => _PluginMissing(
        instance: instance,
        title: title,
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

final class _PluginMissing extends ConsumerStatefulWidget {
  const _PluginMissing({required this.instance, required this.title});

  final HermesInstance instance;
  final String title;

  @override
  ConsumerState<_PluginMissing> createState() => _PluginMissingState();
}

final class _PluginMissingState extends ConsumerState<_PluginMissing> {
  var _busy = false;
  String? _error;

  Future<void> _install(LocalHermesHost host) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await host.installPlugin(await ref.read(registryProvider.future));
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
          '${local ? 'Hermuse can install the plugin on this computer.' : 'Run these commands where ${widget.instance.label} runs, then restart its gateway:'}',
        ),
        if (local)
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.primary(
              label: _busy ? 'Installing…' : 'Install the plugin',
              onPressed: _busy ? null : () => unawaited(_install(host)),
            ),
          )
        else
          const HermuseCodeBlock(
            'cp -r hermes-plugin/hermuse ~/.hermes/plugins/hermuse\n'
            'hermes plugins enable hermuse\n'
            'hermes hermuse enable\n'
            'hermes hermuse doctor',
          ),
        if (_error case final error?) HermuseRouteError(error),
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
