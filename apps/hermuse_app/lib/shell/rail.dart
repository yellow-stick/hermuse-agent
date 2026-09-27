import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../product/destination.dart';

/// Left navigation rail: destinations, instance switcher, settings.
final class HermuseRail extends ConsumerWidget {
  const HermuseRail({
    required this.destination,
    required this.onDestination,
    required this.onSettings,
    super.key,
  });

  final HermuseDestination destination;
  final ValueChanged<HermuseDestination> onDestination;

  /// Opens instance management (connections, setup, sign-in).
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final instances = ref.watch(instancesProvider).value ?? const [];
    final active = ref.watch(activeThreadProvider).value;
    return SizedBox(
      width: YsLayout.railWidth,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in HermuseDestination.values)
                      _RailItem(
                        icon: item.icon,
                        label: item.label,
                        active: item == destination,
                        onPressed: () => onDestination(item),
                      ),
                    if (instances.length > 1) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          width: 24,
                          child: ColoredBox(
                            color: palette.lineColor,
                            child: const SizedBox(height: 1),
                          ),
                        ),
                      ),
                      for (final instance in instances)
                        _InstanceItem(
                          instance: instance,
                          selected: instance.id == active?.instanceId,
                          onPressed: () => _selectInstance(ref, instance.id),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailItem(
                icon: YsIcon.menu,
                label: 'Settings',
                onPressed: onSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the instance's main chat.
  Future<void> _selectInstance(WidgetRef ref, String instanceId) async {
    final active = ref.read(activeThreadProvider).value;
    if (active?.instanceId == instanceId) return;
    await ref.read(activeThreadProvider.notifier).openInstance(instanceId);
  }
}

final class _InstanceItem extends StatelessWidget {
  const _InstanceItem({
    required this.instance,
    required this.selected,
    required this.onPressed,
  });

  final HermesInstance instance;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final initial = instance.label.trim().isEmpty
        ? '?'
        : instance.label.trim().characters.first.toUpperCase();
    return YsTooltip(
      message: instance.label,
      child: YsPressable(
        onPressed: onPressed,
        semanticLabel: 'Open ${instance.label}',
        builder: (context, state) => SizedBox(
          height: YsLayout.railItemHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: YsMotion.fast),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? palette.paperClearColor
                    : state.hovered
                    ? palette.paperClearColor.withValues(alpha: 0.5)
                    : const Color(0x00000000),
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: palette.primaryColor, width: ysHairline)
                    : null,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: YsType.monogram.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final YsIcon icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  /// Rail: the whole row is the hit target; one solid disc marks
  /// hover and the current destination, and hovering plays the icon motion.
  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsTooltip(
      message: label,
      child: YsPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => SizedBox(
          width: YsLayout.railWidth,
          height: YsLayout.railItemHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: YsMotion.base),
              curve: const Cubic(0.4, 0, 0.2, 1),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active || state.hovered || state.focused
                    ? palette.neutralAmbientColor
                    : palette.neutralAmbientColor.withValues(alpha: 0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: YsMotionIcon(
                  icon,
                  size: YsLayout.railIconSize,
                  strokeWidth: YsLayout.railIconStroke,
                  color: palette.contentColor,
                  hovered: state.hovered,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
