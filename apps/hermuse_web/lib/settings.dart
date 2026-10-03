import 'dart:async';

import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';
import 'screens.dart';

/// The same app menu in the desktop rail and compact navigation.
class HermuseSettingsMenu extends StatefulComponent {
  const HermuseSettingsMenu({
    required this.onSettings,
    this.onInstances,
    this.compact = false,
    super.key,
  });

  final VoidCallback onSettings;
  final VoidCallback? onInstances;
  final bool compact;

  @override
  State<HermuseSettingsMenu> createState() => _HermuseSettingsMenuState();
  @css
  static List<StyleRule> get styles => [
    css('.hermuse-settings-menu')
        .styles(display: .flex, justifyContent: .center, alignItems: .center),
    css('.hermuse-settings-menu-compact').styles(flex: .grow(1)),
    css('.hermuse-computer-settings-menu').styles(display: .none),
    css.media(MediaQuery.screen(maxWidth: 767.px), [
      css('.hermuse-computer-settings-menu').styles(
        position: .fixed(left: YsSpace.lg.px, bottom: YsSpace.lg.px),
        zIndex: const ZIndex(20),
        radius: .circular(YsRadius.pill.px),
        display: .block,
        backgroundColor: .variable('--paper'),
      ),
    ]),
  ];
}

class _HermuseSettingsMenuState extends State<HermuseSettingsMenu> {
  final _trigger = GlobalNodeKey<web.HTMLElement>();
  YsMenuAnchor? _anchor;

  void _open() {
    if (!kIsWeb) return;
    final trigger = _trigger.currentNode;
    if (trigger != null) {
      setState(() => _anchor = YsMenuAnchor.of(trigger));
    }
  }

  @override
  Component build(BuildContext context) => div(
    key: _trigger,
    classes: component.compact
        ? 'hermuse-settings-menu hermuse-settings-menu-compact'
        : 'hermuse-settings-menu',
    [
      YsButton.icon(
        icon: YsIcon.menu,
        label: 'Settings and app menu',
        size: 44,
        iconSize: YsLayout.railIconSize,
        attributes: {
          'aria-haspopup': 'menu',
          'aria-expanded': '${_anchor != null}',
        },
        onPressed: _open,
      ),
      if (_anchor case final anchor?)
        YsMenu(
          label: 'App menu',
          anchor: anchor,
          onClose: () => setState(() => _anchor = null),
          items: [
            YsMenuItem(
              label: 'Settings',
              icon: YsIcon.menu,
              onSelected: component.onSettings,
            ),
            if (component.onInstances case final onInstances?)
              YsMenuItem(
                label: 'Instances',
                icon: YsIcon.monitor,
                onSelected: onInstances,
              ),
          ],
        ),
    ],
  );
}

/// Local preferences, the open agent's permissions and connectors; account
/// sign-in remains explicitly unavailable.
class HermuseSettings extends StatefulComponent {
  const HermuseSettings({
    required this.onBack,
    this.instanceId,
    this.profile = 'default',
    super.key,
  });

  final VoidCallback onBack;

  /// Instance and profile of the open chat (Permissions); null before any
  /// chat is open.
  final String? instanceId;
  final String profile;

  @override
  State<HermuseSettings> createState() => _HermuseSettingsState();

  @css
  static List<StyleRule> get styles => [
    css('.hermuse-settings').styles(
      width: 100.percent,
      height: 100.percent,
      padding: .all(YsSpace.xl.px),
      boxSizing: .borderBox,
      overflow: .only(y: .auto),
      color: .variable('--content'),
    ),
    css('.hermuse-settings-inner').styles(
      maxWidth: YsLayout.listWidth.px,
      margin: .symmetric(horizontal: .auto),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.xxl.px),
    ),
    css('.hermuse-settings-heading, .hermuse-settings-section-head').styles(
      display: .flex,
      flexWrap: .wrap,
      justifyContent: .spaceBetween,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-settings h1').styles(
      margin: .zero,
      fontSize: YsType.title.size.px,
      fontWeight: .w500,
      lineHeight: YsType.title.lineHeight.px,
    ),
    css('.hermuse-settings h2').styles(
      margin: .zero,
      fontSize: YsType.heading.size.px,
      fontWeight: .w500,
    ),
    css('.hermuse-settings p').styles(
      margin: .only(top: YsSpace.sm.px),
      color: .variable('--content-muted'),
      fontSize: YsType.body.size.px,
      lineHeight: YsType.body.lineHeight.px,
    ),
    css('.hermuse-settings-section').styles(
      padding: .all(YsSpace.lg.px),
      radius: .circular(YsRadius.bubble.px),
      backgroundColor: .variable('--paper'),
    ),
    css('.hermuse-theme-choices').styles(
      margin: .only(top: YsSpace.xl.px),
      display: .flex,
      flexWrap: .wrap,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-theme-choice').styles(
      minWidth: 130.px,
      padding: .all(YsSpace.md.px),
      border: .all(color: .variable('--line'), width: 1.px),
      radius: .circular(YsRadius.navRow.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.md.px),
      flex: .grow(1),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
    ),
    css('.hermuse-theme-choice[aria-pressed="true"]').styles(
      border: .all(color: .variable('--primary'), width: 1.px),
      backgroundColor: .variable('--primary-wash'),
    ),
    css('.hermuse-theme-label').styles(
      display: .flex,
      justifyContent: .spaceBetween,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-theme-preview').styles(
      width: 100.percent,
      height: 72.px,
      padding: .all(YsSpace.md.px),
      boxSizing: .borderBox,
      border: .all(color: .variable('--line'), width: 1.px),
      radius: .circular(YsRadius.option.px),
      display: .flex,
      flexDirection: .column,
      justifyContent: .center,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-theme-preview-light')
        .styles(backgroundColor: Color(YsPalette.light.canvas.css)),
    css('.hermuse-theme-preview-dark')
        .styles(backgroundColor: Color(YsPalette.dark.canvas.css)),
    css('.hermuse-theme-preview-system').styles(
      raw: {
        'background':
            'linear-gradient(110deg, ${YsPalette.light.canvas.css} 50%, ${YsPalette.dark.canvas.css} 50%)',
      },
    ),
    css('.hermuse-theme-preview-line').styles(
      width: 70.percent,
      height: 8.px,
      radius: .circular(YsRadius.pill.px),
      backgroundColor: Color(YsPalette.light.contentSubtle.css),
    ),
    css('.hermuse-theme-preview-line:last-child').styles(
      width: 45.percent,
      alignSelf: .end,
      backgroundColor: .variable('--primary'),
    ),
    css('.hermuse-settings-badge').styles(
      padding: .symmetric(horizontal: YsSpace.md.px, vertical: YsSpace.sm.px),
      radius: .circular(YsRadius.pill.px),
      color: .variable('--content'),
      backgroundColor: .variable('--primary-wash'),
      fontSize: YsType.small.size.px,
    ),
    css('.hermuse-settings-account-actions').styles(
      margin: .only(top: YsSpace.xl.px),
      display: .flex,
      flexWrap: .wrap,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-settings-error').styles(
      padding: .all(YsSpace.md.px),
      radius: .circular(YsRadius.row.px),
      color: .variable('--error'),
      backgroundColor: .variable('--error-wash'),
    ),
    css('.hermuse-settings-radios').styles(
      margin: .only(top: YsSpace.lg.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-settings-radio').styles(
      width: 100.percent,
      padding: .all(YsSpace.md.px),
      border: .all(color: .variable('--line'), width: 1.px),
      radius: .circular(YsRadius.navRow.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.md.px),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      textAlign: .left,
      cursor: .pointer,
    ),
    css('.hermuse-settings-radio[aria-checked="true"]').styles(
      border: .all(color: .variable('--primary'), width: 1.px),
      backgroundColor: .variable('--primary-wash'),
    ),
    css('.hermuse-settings-radio-dot').styles(
      width: 18.px,
      height: 18.px,
      margin: .only(top: 1.px),
      radius: .circular(YsRadius.pill.px),
      border: .all(color: .variable('--content-subtle'), width: 1.5.px),
      raw: {'flex-shrink': '0'},
    ),
    css(
      '.hermuse-settings-radio[aria-checked="true"] .hermuse-settings-radio-dot',
    ).styles(
      border: .all(color: .variable('--primary'), width: 5.px),
    ),
    css('.hermuse-settings-radio-text')
        .styles(display: .flex, flexDirection: .column, gap: .all(2.px)),
    css('.hermuse-settings-radio-label').styles(
      fontSize: YsType.body.size.px,
      lineHeight: YsType.body.lineHeight.px,
      fontWeight: .w500,
    ),
    css('.hermuse-settings-radio-help').styles(
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-settings-empty').styles(
      margin: .only(top: YsSpace.lg.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
      color: .variable('--content-muted'),
    ),
    css('.hermuse-settings-empty-title').styles(
      fontSize: YsType.body.size.px,
      fontWeight: .w500,
      color: .variable('--content'),
    ),
    css('.hermuse-settings .hermuse-settings-empty p').styles(margin: .zero),
    css.media(MediaQuery.screen(maxWidth: 480.px), [
      css('.hermuse-settings, .hermuse-settings-section')
          .styles(padding: .all(YsSpace.lg.px)),
      css('.hermuse-theme-choice').styles(minWidth: 100.percent),
    ]),
  ];
}

class _HermuseSettingsState extends State<HermuseSettings> {
  final _heading = GlobalNodeKey<web.HTMLElement>();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      context.binding.addPostFrameCallback(() {
        if (mounted) _heading.currentNode?.focus();
      });
    }
  }

  Future<void> _setMode(BuildContext context, YsThemeMode mode) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await context.readProvider(appThemeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _saveError = 'Could not save your appearance. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: appThemeProvider,
    builder: (context, theme) {
      final selected = theme.value ?? YsThemeMode.dark;
      final busy = _saving || theme.isLoading;
      return div(classes: 'hermuse-settings', [
        div(classes: 'hermuse-settings-inner', [
          div(classes: 'hermuse-settings-heading', [
            div([
              h1(
                key: _heading,
                attributes: {'tabindex': '-1'},
                [.text('Settings')],
              ),
              p([.text('Make Hermuse feel like home.')]),
            ]),
            YsButton.icon(
              icon: YsIcon.close,
              label: 'Back to chat',
              size: 44,
              onPressed: component.onBack,
            ),
          ]),
          section(classes: 'hermuse-settings-section', [
            h2([.text('Appearance')]),
            p([.text('Choose how Hermuse looks on this device.')]),
            div(
              classes: 'hermuse-theme-choices',
              attributes: {
                'role': 'group',
                'aria-label': 'Appearance',
                'aria-busy': '$busy',
              },
              [
                for (final (mode, label) in const [
                  (YsThemeMode.system, 'System'),
                  (YsThemeMode.light, 'Light'),
                  (YsThemeMode.dark, 'Dark'),
                ])
                  YsPressable(
                    label: label,
                    classes: 'hermuse-theme-choice',
                    attributes: {'aria-pressed': '${mode == selected}'},
                    onPressed: busy
                        ? null
                        : () => unawaited(_setMode(context, mode)),
                    builder: (context, state) => .fragment([
                      span(
                        classes:
                            'hermuse-theme-preview hermuse-theme-preview-${mode.name}',
                        attributes: {'aria-hidden': 'true'},
                        [
                          span(classes: 'hermuse-theme-preview-line', []),
                          span(classes: 'hermuse-theme-preview-line', []),
                        ],
                      ),
                      span(classes: 'hermuse-theme-label', [
                        .text(label),
                        if (mode == selected)
                          const YsIconView(YsIcon.checkCircle, size: 18),
                      ]),
                    ]),
                  ),
              ],
            ),
            p(
              attributes: {'role': 'status'},
              [
                .text(
                  theme.isLoading
                      ? 'Loading appearance…'
                      : _saving
                      ? 'Saving appearance…'
                      : 'System follows your device’s appearance.',
                ),
              ],
            ),
            if (_saveError != null || theme.hasError)
              div(
                classes: 'hermuse-settings-error',
                attributes: {'role': 'alert'},
                [
                  .text(
                    _saveError ?? 'Could not load your appearance. Choose a theme to try saving it again.',
                  ),
                ],
              ),
          ]),
          if (component.instanceId case final instanceId?)
            _PermissionsSection(
              key: ValueKey('$instanceId:${component.profile}'),
              instanceId: instanceId,
              profile: component.profile,
            )
          else
            section(classes: 'hermuse-settings-section', [
              h2([.text('Permissions')]),
              p([
                .text('Open a chat with an agent to choose its permissions.'),
              ]),
            ]),
          section(classes: 'hermuse-settings-section', [
            h2([.text('Connectors')]),
            p([.text('Apps and accounts your agent can use on your behalf.')]),
            div(classes: 'hermuse-settings-empty', [
              YsIconView(YsIcon.link, size: 20),
              div([
                p(classes: 'hermuse-settings-empty-title', [
                  .text('No connectors yet'),
                ]),
                p([
                  .text(
                    'Connectors will let your agent reach your other '
                    'accounts, such as mail or calendars. None are '
                    'available yet.',
                  ),
                ]),
              ]),
            ]),
          ]),
          section(classes: 'hermuse-settings-section', [
            div(classes: 'hermuse-settings-section-head', [
              h2([.text('Yellow Stick account')]),
              span(classes: 'hermuse-settings-badge', [
                .text('Work in progress'),
              ]),
            ]),
            p([
              .text('A place for your Yellow Stick account, when it’s ready.'),
            ]),
            p([
              .text(
                'Sign-in is not available yet. You can keep using Hermuse and change your preferences without an account.',
              ),
            ]),
            div(classes: 'hermuse-settings-account-actions', [
              YsButton.primary(label: 'Sign in with Yellow Stick'),
              span([.text('Not available yet')]),
            ]),
          ]),
        ]),
      ]);
    },
  );
}

/// Settings → Permissions: when the open agent asks before running a
/// command ([approvalsModeProvider]).
class _PermissionsSection extends StatefulComponent {
  const _PermissionsSection({
    required this.instanceId,
    required this.profile,
    super.key,
  });

  final String instanceId;
  final String profile;

  @override
  State<_PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<_PermissionsSection> {
  ApprovalsMode? _saving;
  String? _error;

  static String _help(ApprovalsMode mode) => switch (mode) {
    ApprovalsMode.smart =>
      'Your agent judges which commands are risky and asks you only for '
          'those.',
    ApprovalsMode.manual =>
      'Your agent asks before every command that could change or delete '
          'something.',
    ApprovalsMode.off =>
      'Your agent runs every command without asking. Use only on a server '
          'you can rebuild.',
  };

  Future<void> _set(BuildContext context, ApprovalsMode mode) async {
    setState(() {
      _saving = mode;
      _error = null;
    });
    try {
      await context
          .readProvider(
            approvalsModeProvider(
              component.instanceId,
              profile: component.profile,
            ).notifier,
          )
          .set(mode);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not save: ${hermuseErrorText(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: approvalsModeProvider(
      component.instanceId,
      profile: component.profile,
    ),
    builder: (context, mode) {
      final selected = _saving ?? mode.value;
      final busy = _saving != null || mode.value == null;
      return section(classes: 'hermuse-settings-section', [
        h2([.text('Permissions')]),
        p([.text('When your agent asks before running a command.')]),
        div(
          classes: 'hermuse-settings-radios',
          attributes: {
            'role': 'radiogroup',
            'aria-label': 'Approvals',
            'aria-busy': '$busy',
          },
          [
            for (final option in ApprovalsMode.values)
              YsPressable(
                label: option.label,
                classes: 'hermuse-settings-radio',
                attributes: {
                  'role': 'radio',
                  'aria-checked': '${option == selected}',
                },
                onPressed: busy || option == selected
                    ? null
                    : () => unawaited(_set(context, option)),
                builder: (context, state) => .fragment([
                  span(classes: 'hermuse-settings-radio-dot', []),
                  span(classes: 'hermuse-settings-radio-text', [
                    span(classes: 'hermuse-settings-radio-label', [
                      .text(option.label),
                    ]),
                    span(classes: 'hermuse-settings-radio-help', [
                      .text(_help(option)),
                    ]),
                  ]),
                ]),
              ),
          ],
        ),
        if (mode.value == null && mode.hasError)
          div(
            classes: 'hermuse-settings-error',
            attributes: {'role': 'alert'},
            [
              .text(
                'Could not load permissions: ${hermuseErrorText(mode.error!)}',
              ),
            ],
          ),
        if (_error case final error?)
          div(
            classes: 'hermuse-settings-error',
            attributes: {'role': 'alert'},
            [.text(error)],
          ),
      ]);
    },
  );
}
