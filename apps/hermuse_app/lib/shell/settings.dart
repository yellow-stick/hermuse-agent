import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// The same preferences menu on the rail and compact navigation.
final class SettingsMenu extends StatelessWidget {
  const SettingsMenu({
    required this.onSettings,
    required this.builder,
    this.onInstances,
    super.key,
  });

  final VoidCallback onSettings;
  final VoidCallback? onInstances;
  final Widget Function(BuildContext, YsMenuController) builder;

  @override
  Widget build(BuildContext context) => YsMenuAnchor(
    semanticLabel: 'Settings menu',
    items: [
      YsMenuItem(label: 'Settings', icon: YsIcon.menu, onSelected: onSettings),
      if (onInstances case final open?)
        YsMenuItem(label: 'Instances', icon: YsIcon.monitor, onSelected: open),
    ],
    builder: builder,
  );
}

/// Device appearance, the open agent's permissions, connectors and the
/// upcoming Yellow Stick account.
final class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    required this.onClose,
    this.instanceId = '',
    this.profile = 'default',
    this.agentName = '',
    super.key,
  });

  final VoidCallback onClose;

  /// Hermes instance and profile of the open chat: its permissions show
  /// ('' when no agent is open).
  final String instanceId;
  final String profile;
  final String agentName;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _saving = false;
  String? _saveError;

  Future<void> _select(YsThemeMode mode) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(appThemeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Appearance could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final preference = ref.watch(appThemeProvider);
    final mode = preference.value ?? YsThemeMode.dark;
    final busy = _saving || preference.isLoading;
    return ColoredBox(
      color: palette.canvasColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(YsSpace.md),
              child: Align(
                alignment: Alignment.centerRight,
                child: YsButton.icon(
                  icon: YsIcon.close,
                  onPressed: widget.onClose,
                  semanticLabel: 'Close settings',
                  tooltip: 'Close settings',
                  autofocus: true,
                  size: 44,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  YsSpace.xl,
                  YsSpace.sm,
                  YsSpace.xl,
                  YsSpace.xxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: YsLayout.listWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Settings', style: YsType.display.flutter),
                        const SizedBox(height: YsSpace.sm),
                        Text(
                          'Make Hermuse feel like home.',
                          style: YsType.body.flutter.copyWith(
                            color: palette.contentMutedColor,
                          ),
                        ),
                        const SizedBox(height: YsSpace.xxl),
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Appearance', style: YsType.title.flutter),
                              const SizedBox(height: YsSpace.sm),
                              Text(
                                'Choose how Hermuse looks on this device.',
                                style: YsType.body.flutter.copyWith(
                                  color: palette.contentMutedColor,
                                ),
                              ),
                              const SizedBox(height: YsSpace.lg),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cards = [
                                    for (final choice in YsThemeMode.values)
                                      _AppearanceChoice(
                                        mode: choice,
                                        selected: mode == choice,
                                        onPressed: busy || preference.hasError
                                            ? null
                                            : () => _select(choice),
                                      ),
                                  ];
                                  if (constraints.maxWidth <
                                      YsLayout.dialogNarrow) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (
                                          var i = 0;
                                          i < cards.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const SizedBox(height: YsSpace.sm),
                                          cards[i],
                                        ],
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < cards.length;
                                        i++
                                      ) ...[
                                        if (i > 0)
                                          const SizedBox(width: YsSpace.sm),
                                        Expanded(child: cards[i]),
                                      ],
                                    ],
                                  );
                                },
                              ),
                              if (busy) ...[
                                const SizedBox(height: YsSpace.md),
                                Text(
                                  _saving
                                      ? 'Saving appearance…'
                                      : 'Loading appearance…',
                                  style: YsType.caption.flutter,
                                ),
                              ],
                              if (_saveError != null ||
                                  preference.hasError) ...[
                                const SizedBox(height: YsSpace.md),
                                Text(
                                  _saveError ??
                                      'Appearance could not be loaded.',
                                  style: YsType.body.flutter.copyWith(
                                    color: palette.errorColor,
                                  ),
                                ),
                                if (preference.hasError) ...[
                                  const SizedBox(height: YsSpace.sm),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: YsButton.neutral(
                                      label: 'Try again',
                                      onPressed: () =>
                                          ref.invalidate(appThemeProvider),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        if (widget.instanceId.isNotEmpty) ...[
                          const SizedBox(height: YsSpace.lg),
                          _PermissionsSection(
                            instanceId: widget.instanceId,
                            profile: widget.profile,
                            agentName: widget.agentName,
                          ),
                        ],
                        const SizedBox(height: YsSpace.lg),
                        const _ConnectorsSection(),
                        const SizedBox(height: YsSpace.lg),
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: YsSpace.md,
                                runSpacing: YsSpace.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Yellow Stick account',
                                    style: YsType.title.flutter,
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: palette.primaryMutedColor,
                                      borderRadius: BorderRadius.circular(
                                        YsRadius.pill,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: YsSpace.md,
                                        vertical: YsSpace.sm,
                                      ),
                                      child: Text(
                                        'Work in progress',
                                        style: YsType.caption.flutter.copyWith(
                                          color: palette.contentColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: YsSpace.lg),
                              YsIconWidget(
                                YsIcon.user,
                                size: 32,
                                color: palette.contentMutedColor,
                              ),
                              const SizedBox(height: YsSpace.md),
                              Text(
                                'A place for your account.',
                                style: YsType.heading.flutter,
                              ),
                              const SizedBox(height: YsSpace.sm),
                              Text(
                                'Yellow Stick sign-in is not available yet. You can keep using Hermuse and manage your instances without an account.',
                                style: YsType.body.flutter.copyWith(
                                  color: palette.contentMutedColor,
                                ),
                              ),
                              const SizedBox(height: YsSpace.lg),
                              const YsButton.primary(
                                label: 'Sign in with Yellow Stick',
                                icon: YsIcon.user,
                                onPressed: null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.bubble),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(padding: const EdgeInsets.all(YsSpace.lg), child: child),
    );
  }
}

/// What each approvals mode means, in one line.
String approvalsModeHelp(ApprovalsMode mode) => switch (mode) {
  ApprovalsMode.smart =>
    'Your agent judges which commands are risky and asks you only for those.',
  ApprovalsMode.manual =>
    'Your agent asks before every command that could change or delete '
        'something.',
  ApprovalsMode.off =>
    'Your agent runs every command without asking. Use only on a server you '
        'can rebuild.',
};

/// Settings → Permissions: when the open agent asks before risky commands.
final class _PermissionsSection extends ConsumerStatefulWidget {
  const _PermissionsSection({
    required this.instanceId,
    required this.profile,
    required this.agentName,
  });

  final String instanceId;
  final String profile;
  final String agentName;

  @override
  ConsumerState<_PermissionsSection> createState() =>
      _PermissionsSectionState();
}

final class _PermissionsSectionState
    extends ConsumerState<_PermissionsSection> {
  ApprovalsMode? _saving;
  String? _error;

  Future<void> _select(ApprovalsMode mode) async {
    setState(() {
      _saving = mode;
      _error = null;
    });
    try {
      await ref
          .read(
            approvalsModeProvider(
              widget.instanceId,
              profile: widget.profile,
            ).notifier,
          )
          .set(mode);
    } catch (error) {
      if (mounted) setState(() => _error = 'Not saved: $error');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final provider = approvalsModeProvider(
      widget.instanceId,
      profile: widget.profile,
    );
    final setting = ref.watch(provider);
    final current = setting.value;
    final muted = YsType.body.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    final who = widget.agentName.isEmpty ? 'your agent' : widget.agentName;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Permissions', style: YsType.title.flutter),
          const SizedBox(height: YsSpace.sm),
          Text('When $who asks before running risky commands.', style: muted),
          const SizedBox(height: YsSpace.lg),
          if (current == null && setting.hasError) ...[
            Text(
              'Permissions could not be loaded: ${setting.error}',
              style: YsType.body.flutter.copyWith(color: palette.errorColor),
            ),
            const SizedBox(height: YsSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: YsButton.neutral(
                label: 'Try again',
                onPressed: () => ref.invalidate(provider),
              ),
            ),
          ] else if (current == null)
            Text('Loading permissions…', style: YsType.caption.flutter)
          else
            Semantics(
              label: 'Approvals',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final mode in ApprovalsMode.values)
                    _RadioRow(
                      label: mode.label,
                      help: approvalsModeHelp(mode),
                      selected: (_saving ?? current) == mode,
                      onPressed: _saving == null && mode != current
                          ? () => _select(mode)
                          : null,
                    ),
                ],
              ),
            ),
          if (_saving != null) ...[
            const SizedBox(height: YsSpace.sm),
            Text('Saving…', style: YsType.caption.flutter),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: YsSpace.sm),
            Text(
              error,
              style: YsType.body.flutter.copyWith(color: palette.errorColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// One choice of a radio group: ring, label and a line of help.
final class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.help,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String help;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      // Inside the pressable: the radio state joins the button's own node.
      builder: (context, state) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: YsFocusRing(
          visible: state.focused,
          radius: YsRadius.row,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: state.hovered && !selected
                  ? palette.neutralWashColor
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(YsRadius.row),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YsSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: YsSpace.xxs),
                    child: Container(
                      width: YsLayout.inlineIcon,
                      height: YsLayout.inlineIcon,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? palette.primaryInkColor
                              : palette.contentSubtleColor,
                          width: ysHairline,
                        ),
                      ),
                      child: selected
                          ? Container(
                              width: YsLayout.statusDot,
                              height: YsLayout.statusDot,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.primaryInkColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: YsSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: YsType.heading.flutter),
                        const SizedBox(height: YsSpace.xxs),
                        Text(
                          help,
                          style: YsType.small.flutter.copyWith(
                            color: palette.contentMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings → Connectors: none exist yet, and it says so.
final class _ConnectorsSection extends StatelessWidget {
  const _ConnectorsSection();

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connectors', style: YsType.title.flutter),
          const SizedBox(height: YsSpace.lg),
          YsIconWidget(YsIcon.link, size: 32, color: palette.contentMutedColor),
          const SizedBox(height: YsSpace.md),
          Text('No connectors yet', style: YsType.heading.flutter),
          const SizedBox(height: YsSpace.sm),
          Text(
            'Connectors will let your agent reach your other accounts, such as '
            'mail or calendars. None are available yet.',
            style: YsType.body.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

final class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({
    required this.mode,
    required this.selected,
    required this.onPressed,
  });

  final YsThemeMode mode;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final label = switch (mode) {
      YsThemeMode.system => 'System',
      YsThemeMode.light => 'Light',
      YsThemeMode.dark => 'Dark',
    };
    final description = mode == YsThemeMode.system
        ? 'Follow your device'
        : mode == YsThemeMode.light
        ? 'A brighter canvas'
        : 'A softer glow';
    return Semantics(
      selected: selected,
      child: YsPressable(
        onPressed: onPressed,
        semanticLabel: '$label appearance',
        builder: (context, state) => YsFocusRing(
          visible: state.focused,
          radius: YsRadius.row,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected || state.hovered
                  ? palette.neutralAmbientColor
                  : palette.canvasColor,
              borderRadius: BorderRadius.circular(YsRadius.row),
              border: Border.all(
                color: selected ? palette.primaryColor : palette.lineColor,
                width: ysHairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YsSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(YsRadius.option),
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            if (mode != YsThemeMode.dark)
                              const Expanded(
                                child: _ThemePreview(mode: YsThemeMode.light),
                              ),
                            if (mode != YsThemeMode.light)
                              const Expanded(
                                child: _ThemePreview(mode: YsThemeMode.dark),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: YsSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(label, style: YsType.heading.flutter),
                      ),
                      if (selected)
                        YsIconWidget(
                          YsIcon.check,
                          size: 18,
                          color: palette.contentColor,
                        ),
                    ],
                  ),
                  const SizedBox(height: YsSpace.sm),
                  Text(
                    description,
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A miniature shell uses the real palettes, including both for System.
final class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final YsThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final palette = resolveTheme(mode, platformDark: false);
    return ColoredBox(
      color: palette.canvasColor,
      child: Row(
        children: [
          ColoredBox(
            color: palette.paperColor,
            child: SizedBox(
              width: 18,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 6),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(YsSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.neutralAmbientColor,
                        borderRadius: BorderRadius.circular(YsRadius.option),
                      ),
                      child: const SizedBox(width: 32, height: 12),
                    ),
                  ),
                  const SizedBox(height: YsSpace.sm),
                  ColoredBox(
                    color: palette.contentMutedColor,
                    child: const SizedBox(height: 3),
                  ),
                  const SizedBox(height: YsSpace.xs),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.7,
                    child: ColoredBox(
                      color: palette.contentMutedColor,
                      child: const SizedBox(height: 3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
