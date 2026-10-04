import 'dart:async';

import 'package:hermes_client/hermes_client.dart' show HermesException;
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
          if (component.instanceId case final instanceId?)
            HermuseImageGenerationSection(
              key: ValueKey('media:$instanceId'),
              instanceId: instanceId,
            )
          else
            section(classes: 'hermuse-settings-section', [
              h2([.text('Image generation')]),
              p([
                .text(
                  'Open a chat with an agent to set up image generation on '
                  'its server.',
                ),
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

/// Settings → Image generation: the ContentFlow service the open chat's
/// server draws agent portraits, their animations and Feed illustrations
/// with ([mediaConfigProvider], tested with [mediaStatusProvider]).
class HermuseImageGenerationSection extends StatefulComponent {
  const HermuseImageGenerationSection({required this.instanceId, super.key});

  final String instanceId;

  @override
  State<HermuseImageGenerationSection> createState() =>
      _HermuseImageGenerationSectionState();

  @css
  static List<StyleRule> get styles => [
    css('.hermuse-media-form').styles(
      margin: .only(top: YsSpace.lg.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.md.px),
    ),
    css(
      '.hermuse-media-advanced',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.md.px)),
    css('.hermuse-media-disclosure').styles(
      display: .inlineFlex,
      alignSelf: .start,
      alignItems: .center,
      gap: .all(YsSpace.xxs.px),
      color: .variable('--content-muted'),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
    ),
    css('.hermuse-media-disclosure:hover')
        .styles(color: .variable('--content')),
    css('.hermuse-media-disclosure:focus-visible').styles(
      raw: {
        'outline': '2px solid var(--primary)',
        'outline-offset': '${YsSpace.xxs}px',
      },
    ),
    css(
      '.hermuse-media-advanced-fields',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.md.px)),
    css('.hermuse-media-value').styles(
      margin: .zero,
      color: .variable('--content'),
      raw: {'overflow-wrap': 'anywhere'},
    ),
  ];
}

class _HermuseImageGenerationSectionState
    extends State<HermuseImageGenerationSection> {
  /// The config the fields were filled from (once, then they are the
  /// user's).
  MediaConfig? _seeded;
  String _endpoint = '';
  String _token = '';
  String _imageModel = '';
  String _videoModel = '';
  bool _feedFallback = false;
  bool _saving = false;
  bool _saved = false;
  bool _tested = false;

  /// The model fields are shown (collapsed by default).
  bool _advanced = false;
  String? _error;

  void _seed(MediaConfig config) {
    if (_seeded != null) return;
    _seeded = config;
    _endpoint = config.endpoint;
    _imageModel = config.imageModel;
    _videoModel = config.videoModel;
    _feedFallback = config.feedFallback;
  }

  void _edited(void Function() change) => setState(() {
    change();
    _saved = false;
  });

  Future<void> _save({String? token}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      final config = await context
          .readProvider(mediaConfigProvider(component.instanceId).notifier)
          .save(
            endpoint: _seeded?.fromEnv ?? false ? _seeded!.endpoint : _endpoint,
            token: token ?? (_token.isEmpty ? null : _token),
            imageModel: _imageModel.trim(),
            videoModel: _videoModel.trim(),
            feedFallback: _feedFallback,
          );
      if (mounted) {
        setState(() {
          _seeded = config;
          _endpoint = config.endpoint;
          _token = '';
          _saved = true;
          _tested = false;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not save: ${_reason(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _tested = true;
      _saved = false;
      _error = null;
    });
    try {
      await context
          .readProvider(mediaStatusProvider(component.instanceId).notifier)
          .refresh();
    } on Object catch (_) {
      // Shown from the provider's error below.
    }
  }

  static String _reason(Object e) =>
      e is HermesException ? hermesReason(e) : hermuseErrorText(e);

  Component _status(AsyncValue<MediaStatus> status) {
    if (status.isLoading) {
      return p(attributes: {'role': 'status'}, [.text('Testing…')]);
    }
    if (status.hasError) {
      return div(
        classes: 'hermuse-settings-error',
        attributes: {'role': 'alert'},
        [.text('Not reachable: ${_reason(status.error!)}')],
      );
    }
    final value = status.value;
    if (value == null) return .fragment(const []);
    if (!value.configured) {
      return p(
        attributes: {'role': 'status'},
        [
          .text(
            'Not set up: nothing is generated until you enter an endpoint.',
          ),
        ],
      );
    }
    if (!value.reachable) {
      return div(
        classes: 'hermuse-settings-error',
        attributes: {'role': 'alert'},
        [
          .text(
            'Not reachable: ${value.error ?? 'the service did not answer'}',
          ),
        ],
      );
    }
    return p(
      attributes: {'role': 'status'},
      [
        .text(
          value.credits == null
              ? 'Reachable'
              : 'Reachable · ${value.credits} credits',
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: mediaConfigProvider(component.instanceId),
    builder: (context, config) => HermuseWatch(
      provider: mediaStatusProvider(component.instanceId),
      builder: (context, status) {
        final value = config.value;
        if (value != null) _seed(value);
        final fromEnv = _seeded?.fromEnv ?? false;
        final hasToken = _seeded?.hasToken ?? false;
        final busy = _saving || value == null;
        return section(classes: 'hermuse-settings-section', [
          h2([.text('Image generation')]),
          p([
            .text(
              'Generates agent portraits, their animations and Feed '
              'illustrations with a ContentFlow service you run.',
            ),
          ]),
          if (value == null)
            config.hasError
                ? div(
                    classes: 'hermuse-settings-error',
                    attributes: {'role': 'alert'},
                    [
                      .text(
                        'Could not load image generation: '
                        '${_reason(config.error!)}',
                      ),
                    ],
                  )
                : p(attributes: {'role': 'status'}, [.text('Loading…')])
          else ...[
            if (!value.configured && !_tested)
              p([
                .text(
                  'Not set up: nothing is generated until you enter an '
                  'endpoint.',
                ),
              ]),
            div(classes: 'hermuse-media-form', [
              if (fromEnv) ...[
                p([
                  .text(
                    "Set by the server's environment "
                    '(HERMUSE_MEDIA_ENDPOINT); change it there.',
                  ),
                ]),
                YsField(
                  label: 'Endpoint',
                  child: p(classes: 'hermuse-media-value', [
                    .text(value.endpoint),
                  ]),
                ),
              ] else ...[
                YsField(
                  label: 'Endpoint',
                  child: YsInputBox(
                    value: _endpoint,
                    label: 'Endpoint',
                    url: true,
                    placeholder: 'https://contentflow.example.com',
                    onChanged: (text) => _edited(() => _endpoint = text),
                    onSubmitted: () => unawaited(_save()),
                  ),
                ),
                YsField(
                  label: 'Token',
                  child: YsInputBox(
                    value: _token,
                    label: 'Token',
                    obscure: true,
                    autocomplete: 'off',
                    placeholder: hasToken
                        ? 'Saved — leave empty to keep'
                        : 'Leave empty if the service has none',
                    onChanged: (text) => _edited(() => _token = text),
                    onSubmitted: () => unawaited(_save()),
                  ),
                ),
              ],
              div(classes: 'hermuse-media-advanced', [
                YsPressable(
                  classes: 'hermuse-media-disclosure',
                  attributes: {'aria-expanded': '$_advanced'},
                  onPressed: () => setState(() => _advanced = !_advanced),
                  builder: (context, state) => .fragment([
                    YsIconView(
                      _advanced ? YsIcon.chevronDown : YsIcon.chevronRight,
                      size: YsLayout.inlineIcon,
                    ),
                    .text(_advanced ? 'Hide advanced' : 'Advanced'),
                  ]),
                ),
                if (_advanced)
                  div(classes: 'hermuse-media-advanced-fields', [
                    YsField(
                      label: 'Image model',
                      child: YsInputBox(
                        value: _imageModel,
                        label: 'Image model',
                        placeholder: 'Service default',
                        onChanged: (text) => _edited(() => _imageModel = text),
                      ),
                    ),
                    YsField(
                      label: 'Video model',
                      child: YsInputBox(
                        value: _videoModel,
                        label: 'Video model',
                        placeholder: 'Service default',
                        onChanged: (text) => _edited(() => _videoModel = text),
                      ),
                    ),
                  ]),
              ]),
              YsPressable(
                label: 'Illustrate Feed posts that have no image',
                classes: 'hermuse-settings-radio',
                attributes: {
                  'role': 'switch',
                  'aria-checked': '$_feedFallback',
                },
                onPressed: busy
                    ? null
                    : () => _edited(() => _feedFallback = !_feedFallback),
                builder: (context, state) => .fragment([
                  span(classes: 'hermuse-settings-radio-dot', []),
                  span(classes: 'hermuse-settings-radio-text', [
                    span(classes: 'hermuse-settings-radio-label', [
                      .text('Illustrate Feed posts that have no image'),
                    ]),
                  ]),
                ]),
              ),
            ]),
            div(classes: 'hermuse-settings-account-actions', [
              YsButton.primary(
                label: _saving ? 'Saving…' : 'Save',
                onPressed: busy ? null : () => unawaited(_save()),
              ),
              YsButton.neutral(
                label: 'Test',
                onPressed: busy || status.isLoading
                    ? null
                    : () => unawaited(_test()),
              ),
              if (hasToken && !fromEnv)
                YsButton.neutral(
                  label: 'Remove token',
                  onPressed: busy ? null : () => unawaited(_save(token: '')),
                ),
            ]),
            if (hasToken && !fromEnv) p([.text('Token saved')]),
            if (_saved) p(attributes: {'role': 'status'}, [.text('Saved.')]),
            if (_tested) _status(status),
            if (_error case final error?)
              div(
                classes: 'hermuse-settings-error',
                attributes: {'role': 'alert'},
                [.text(error)],
              ),
          ],
        ]);
      },
    ),
  );
}
