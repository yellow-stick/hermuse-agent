import 'dart:async';

import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';

/// The active profile's portrait, with a static reduced-motion fallback.
class HermuseAgentAvatar extends StatelessComponent {
  const HermuseAgentAvatar({
    required this.profile,
    required this.avatarId,
    this.chat,
    this.size = 36,
    this.alt = '',
    this.onEdit,
    super.key,
  });

  final String profile;
  final String avatarId;
  final ChatState? chat;
  final double size;
  final String alt;
  final VoidCallback? onEdit;

  @override
  Component build(BuildContext context) => div(
    classes: 'ys-avatar',
    styles: Styles(width: size.px, height: size.px),
    [
      .element(
        tag: 'picture',
        children: [
          if (profile == 'default' && avatarId == 'hermuse' && chat != null)
            source(
              attributes: {
                'media': '(prefers-reduced-motion: no-preference)',
                'srcset':
                    '/images/${agentAvatarAsset(avatarId, chat: chat, animate: true)}',
              },
            ),
          img(
            classes: 'ys-avatar-img',
            src: '/images/${agentAvatarAsset(avatarId)}',
            alt: alt,
            width: size.round(),
            height: size.round(),
            attributes: {'decoding': 'async'},
          ),
        ],
      ),
      if (onEdit != null)
        YsPressable(
          onPressed: onEdit,
          label: 'Edit agent',
          classes: 'ys-avatar-badge',
          builder: (context, state) => YsIconView(YsIcon.pencil, size: 14),
        ),
    ],
  );
}

/// A real profile switcher independent of the server instance controls.
class HermuseAgentPicker extends StatefulComponent {
  const HermuseAgentPicker({
    required this.instanceId,
    required this.profile,
    required this.chat,
    required this.onCreate,
    required this.onEdit,
    this.subtitle,
    this.readOnly = false,
    this.disabled = false,
    super.key,
  });

  final String instanceId;
  final String profile;
  final ChatState chat;
  final VoidCallback onCreate;
  final ValueChanged<AgentProfile> onEdit;
  final bool readOnly;

  /// Set in the phone top bar: the trigger renders as a centered two-line
  /// title (agent name over [subtitle], the chat on screen) instead of the
  /// avatar pill of the floating header.
  final String? subtitle;
  final bool disabled;

  @override
  State<HermuseAgentPicker> createState() => _HermuseAgentPickerState();

  @css
  static List<StyleRule> get styles => [
    css('.hermuse-agent-picker').styles(minWidth: 0.px, maxWidth: 240.px),
    css('.hermuse-agent-trigger').styles(
      display: .flex,
      minWidth: 0.px,
      maxWidth: 100.percent,
      height: YsLayout.pillHeight.px,
      padding: .only(left: YsSpace.xs.px, right: YsSpace.md.px),
      border: .none,
      radius: .circular(YsRadius.pill.px),
      cursor: .pointer,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
      color: .variable('--content'),
    ),
    ...ysGlassRules('.hermuse-agent-trigger:not(.hermuse-agent-title)'),
    css('.hermuse-agent-trigger:focus-visible').styles(
      raw: {
        'outline': '2px solid var(--primary)',
        'outline-offset': '${YsSpace.xxs}px',
      },
    ),
    css('.hermuse-agent-label').styles(
      minWidth: 0.px,
      overflow: .hidden,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
    ),
    css('.hermuse-agent-caption')
        .styles(color: .variable('--content-muted'), fontSize: 10.px),
    css('.hermuse-agent-error').styles(color: .variable('--error')),
    css('.hermuse-agent-trigger.hermuse-agent-title').styles(
      height: .auto,
      padding: .symmetric(horizontal: YsSpace.sm.px, vertical: YsSpace.xxs.px),
      flexDirection: .column,
      gap: .all(0.px),
      radius: .circular(YsRadius.navRow.px),
      backgroundColor: Colors.transparent,
      raw: {'transition': 'background-color ${YsMotion.fast}ms'},
    ),
    css('.hermuse-agent-title:hover, .hermuse-agent-title:active')
        .styles(backgroundColor: .variable('--neutral-wash')),
    css('.hermuse-agent-title-row').styles(
      display: .flex,
      maxWidth: 100.percent,
      alignItems: .center,
      gap: .all(YsSpace.xxs.px),
      fontSize: YsType.heading.size.px,
      lineHeight: YsType.heading.lineHeight.px,
      fontWeight: .w500,
    ),
    css('.hermuse-agent-title-row svg')
        .styles(color: .variable('--content-muted'), raw: {'flex-shrink': '0'}),
    css('.hermuse-agent-subtitle').styles(
      maxWidth: 100.percent,
      overflow: .hidden,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
      color: .variable('--content-muted'),
      fontSize: YsType.caption.size.px,
      lineHeight: YsType.caption.lineHeight.px,
      fontWeight: .w400,
    ),
  ];
}

class _HermuseAgentPickerState extends State<HermuseAgentPicker> {
  final _trigger = GlobalNodeKey<web.HTMLElement>();
  YsMenuAnchor? _menu;
  String? _error;
  bool _switching = false;

  Future<void> _switch(AgentProfile agent) async {
    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      await context
          .readProvider(activeThreadProvider.notifier)
          .openAgent(component.instanceId, agent.profile);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not open agent: $error');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final roster = context.watch(agentProfilesProvider(component.instanceId));
    final agents = roster.value ?? const <AgentProfile>[];
    final current = agents
        .where((agent) => agent.profile == component.profile)
        .firstOrNull;
    final name =
        current?.displayName ??
        (roster.isLoading ? 'Loading agents…' : component.chat.agentName);
    final subtitle = component.subtitle;
    return div(classes: 'hermuse-agent-picker', [
      span(key: _trigger, [
        YsPressable(
          onPressed: component.disabled || _switching
              ? null
              : () {
                  final node = _trigger.currentNode;
                  if (node != null) {
                    setState(() => _menu = YsMenuAnchor.of(node));
                  }
                },
          label: 'Agent: $name',
          classes: subtitle == null
              ? 'hermuse-agent-trigger'
              : 'hermuse-agent-trigger hermuse-agent-title',
          attributes: {
            'aria-haspopup': 'menu',
            'aria-expanded': '${_menu != null}',
          },
          builder: (context, press) => subtitle == null
              ? .fragment([
                  HermuseAgentAvatar(
                    profile: component.profile,
                    avatarId: current?.avatarId ?? 'hermuse',
                    chat: component.chat,
                    size: 28,
                  ),
                  span(classes: 'hermuse-agent-caption', [.text('AGENT')]),
                  span(classes: 'hermuse-agent-label', [.text(name)]),
                  YsIconView(YsIcon.chevronDown, size: YsLayout.inlineIcon),
                ])
              : .fragment([
                  span(classes: 'hermuse-agent-title-row', [
                    span(classes: 'hermuse-agent-label', [.text(name)]),
                    YsIconView(YsIcon.chevronDown, size: YsLayout.inlineIcon),
                  ]),
                  span(classes: 'hermuse-agent-subtitle', [.text(subtitle)]),
                ]),
        ),
      ]),
      if (_error case final error?)
        p(
          classes: 'hermuse-agent-error',
          attributes: {'role': 'alert'},
          [.text(error)],
        ),
      if (_menu case final anchor?)
        YsMenu(
          label: 'Agents',
          anchor: anchor,
          onClose: () => setState(() => _menu = null),
          items: [
            for (final agent in agents)
              YsMenuItem(
                label: agent.displayName,
                checked: agent.profile == component.profile,
                onSelected: () => unawaited(_switch(agent)),
              ),
            if (roster.hasError || agents.isEmpty)
              YsMenuItem(
                label: roster.hasError
                    ? 'Could not load agents — retry'
                    : 'Reload agents',
                onSelected: () => context.container.invalidate(
                  agentProfilesProvider(component.instanceId),
                ),
              ),
            if (!component.readOnly) ...[
              if (current != null)
                YsMenuItem(
                  label: 'Edit agent',
                  icon: YsIcon.pencil,
                  onSelected: () => component.onEdit(current),
                ),
              YsMenuItem(
                label: 'Add agent',
                icon: YsIcon.plus,
                onSelected: component.onCreate,
              ),
            ],
          ],
        ),
    ]);
  }
}

/// Creates a Hermes profile or edits just the selected profile's SOUL.
class HermuseAgentEditor extends StatefulComponent {
  const HermuseAgentEditor({
    required this.instanceId,
    required this.onClose,
    this.agent,
    super.key,
  });

  final String instanceId;
  final AgentProfile? agent;
  final VoidCallback onClose;

  @override
  State<HermuseAgentEditor> createState() => _HermuseAgentEditorState();

  @css
  static List<StyleRule> get styles => [
    css(
      '.hermuse-agent-form',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.md.px)),
    css('.hermuse-agent-avatars')
        .styles(display: .flex, flexWrap: .wrap, gap: .all(YsSpace.sm.px)),
    css('.hermuse-agent-choice').styles(
      display: .flex,
      padding: .all(YsSpace.sm.px),
      border: .all(color: .variable('--line'), width: ysHairline.px),
      radius: .circular(YsRadius.option.px),
      cursor: .pointer,
      flexDirection: .column,
      alignItems: .center,
      gap: .all(YsSpace.xs.px),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
    ),
    css(
      '.hermuse-agent-choice[aria-pressed="true"], .hermuse-agent-choice:focus-visible',
    ).styles(
      raw: {
        'outline': '2px solid var(--primary)',
        'outline-offset': '${YsSpace.xxs}px',
      },
    ),
    css('.hermuse-agent-note').styles(
      margin: .zero,
      color: .variable('--content-muted'),
      fontSize: 13.px,
    ),
  ];
}

class _HermuseAgentEditorState extends State<HermuseAgentEditor> {
  late String _avatarId;
  late String _name;
  late String _prompt;
  bool _promptEdited = false;
  bool _nameEdited = false;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  AgentProfile? _savedAgent;

  @override
  void initState() {
    super.initState();
    final agent = component.agent;
    _savedAgent = agent;
    final template = agent?.avatar ?? AgentAvatar.byId('noah');
    _avatarId = template.id;
    _name = agent?.displayName ?? template.name;
    _prompt = agent == null ? template.defaultPrompt : '';
    if (agent != null) unawaited(_loadPrompt());
  }

  Future<void> _loadPrompt() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await context.readProvider(
        agentDetailsProvider(
          component.instanceId,
          component.agent!.profile,
        ).future,
      );
      if (mounted) {
        setState(() {
          _prompt = details.prompt;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load agent prompt: $error';
        });
      }
    }
  }

  void _selectAvatar(AgentAvatar avatar) => setState(() {
    _avatarId = avatar.id;
    // Editing artwork must never silently replace an existing SOUL.
    if (_savedAgent == null) {
      if (!_nameEdited) _name = avatar.name;
      if (!_promptEdited) _prompt = avatar.defaultPrompt;
    }
  });

  Future<void> _save() async {
    if (_busy || _loading || _name.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = context.readProvider(
        agentProfilesProvider(component.instanceId).notifier,
      );
      final agent = _savedAgent;
      if (agent == null) {
        final created = await notifier.create(
          name: _name.trim(),
          avatarId: _avatarId,
          prompt: _prompt,
        );
        _savedAgent = created;
        await context
            .readProvider(activeThreadProvider.notifier)
            .openAgent(component.instanceId, created.profile);
      } else {
        await notifier.saveAgent(
          agent: agent,
          name: _name.trim(),
          avatarId: _avatarId,
          prompt: _prompt,
        );
        if (component.agent == null) {
          await context
              .readProvider(activeThreadProvider.notifier)
              .openAgent(component.instanceId, agent.profile);
        }
      }
      if (mounted) component.onClose();
    } on AgentWriteException catch (error) {
      if (mounted) {
        setState(() {
          _savedAgent = error.createdAgent ?? _savedAgent;
          _busy = false;
          _error = error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save agent: $error';
        });
      }
    }
  }

  @override
  Component build(BuildContext context) => YsDialog(
    title: _savedAgent == null ? 'Add agent' : 'Edit agent',
    wide: true,
    onClose: () {
      if (!_busy) component.onClose();
    },
    actions: [
      YsButton.neutral(
        label: 'Cancel',
        onPressed: _busy ? null : component.onClose,
      ),
      YsButton.primary(
        label: _busy
            ? 'Saving…'
            : _savedAgent == null
            ? 'Create agent'
            : 'Save',
        onPressed: _busy || _loading || _name.trim().isEmpty
            ? null
            : () => unawaited(_save()),
      ),
    ],
    child: div(classes: 'hermuse-agent-form', [
      if (_error case final error?)
        p(
          classes: 'hermuse-agent-error',
          attributes: {'role': 'alert'},
          [.text(error)],
        ),
      if (_loading) ...[
        p(
          attributes: {'role': 'status'},
          [
            .text(
              _error == null
                  ? 'Loading agent prompt…'
                  : 'The prompt must load before this agent can be saved.',
            ),
          ],
        ),
        if (_error != null)
          YsButton.neutral(
            label: 'Retry',
            onPressed: () {
              context.container.invalidate(
                agentDetailsProvider(
                  component.instanceId,
                  component.agent!.profile,
                ),
              );
              unawaited(_loadPrompt());
            },
          ),
      ] else ...[
        YsField(
          label: 'Avatar',
          child: div(classes: 'hermuse-agent-avatars', [
            for (final avatar in AgentAvatar.available)
              YsPressable(
                onPressed: _busy ? null : () => _selectAvatar(avatar),
                label: '${avatar.name} avatar',
                classes: 'hermuse-agent-choice',
                attributes: {'aria-pressed': '${_avatarId == avatar.id}'},
                builder: (context, state) => .fragment([
                  YsAvatar(src: '/images/${avatar.assetPath}', size: 48),
                  span([.text(avatar.name)]),
                ]),
              ),
          ]),
        ),
        YsField(
          label: 'Name',
          child: YsInputBox(
            value: _name,
            label: 'Agent name',
            onChanged: (value) {
              if (!_busy) {
                setState(() {
                  _name = value;
                  _nameEdited = true;
                });
              }
            },
            onSubmitted: () => unawaited(_save()),
          ),
        ),
        YsField(
          label: 'SOUL prompt',
          child: YsTextBox(
            value: _prompt,
            label: 'Agent SOUL prompt',
            minHeight: 160,
            onChanged: (value) {
              if (!_busy) {
                setState(() {
                  _prompt = value;
                  _promptEdited = true;
                });
              }
            },
          ),
        ),
        p(classes: 'hermuse-agent-note', [
          .text(
            'This agent has its own prompt and conversations on the same Hermes instance. Prompt changes apply to new conversations.',
          ),
        ]),
      ],
    ]),
  );
}
