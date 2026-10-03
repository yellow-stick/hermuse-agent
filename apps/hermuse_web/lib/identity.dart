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

enum _Editor { soul, memory }

/// The panel's Identity tab: the agent's name with Edit (the agent editor),
/// then the SOUL card (its persona, `SOUL.md`) and the MEMORY card (what it
/// keeps about the user, `MEMORY.md` + `USER.md`), each opening a
/// full-screen editor.
class HermuseIdentity extends StatefulComponent {
  const HermuseIdentity({
    required this.instanceId,
    required this.profile,
    required this.agentName,
    this.onEditAgent,
    super.key,
  });

  final String instanceId;
  final String profile;
  final String agentName;

  /// Opens the agent editor; null hides Edit (read-only demo).
  final VoidCallback? onEditAgent;

  @override
  State<HermuseIdentity> createState() => _HermuseIdentityState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-identity').styles(
      width: 100.percent,
      margin: .only(top: YsSpace.lg.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-identity-name').styles(
      padding: .symmetric(vertical: YsSpace.md.px, horizontal: YsSpace.lg.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: .all(YsSpace.md.px),
      backgroundColor: .variable('--paper'),
      raw: {'box-shadow': 'var(--raised)'},
    ),
    css('.hermuse-identity-name-text').styles(
      fontSize: YsType.heading.size.px,
      lineHeight: YsType.heading.lineHeight.px,
      fontWeight: .w500,
      color: .variable('--content'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
    ),
    css('.hermuse-identity-cards').styles(
      display: .grid,
      gap: .all(YsSpace.md.px),
      raw: {'grid-template-columns': '1fr 1fr'},
    ),
    css('.hermuse-identity-card').styles(
      height: YsLayout.identityCardHeight.px,
      padding: .all(YsSpace.lg.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      justifyContent: .spaceBetween,
      color: .variable('--identity-content'),
      cursor: .pointer,
      border: .none,
      textAlign: .left,
      raw: {'font-family': 'inherit'},
    ),
    css('.hermuse-identity-soul').styles(
      raw: {
        'background':
            'linear-gradient(160deg, var(--soul-start), var(--soul-end))',
      },
    ),
    css('.hermuse-identity-memory').styles(
      raw: {
        'background':
            'linear-gradient(160deg, var(--memory-start), var(--memory-end))',
      },
    ),
    css(
      '.hermuse-identity-card-head',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.xs.px)),
    css('.hermuse-identity-card-label').styles(
      fontSize: YsType.title.size.px,
      lineHeight: YsType.title.lineHeight.px,
      fontWeight: .w600,
    ),
    css('.hermuse-identity-caption').styles(
      fontSize: YsType.micro.size.px,
      lineHeight: YsType.micro.lineHeight.px,
      raw: {
        'font-family': YsType.monoFamily,
        'letter-spacing': '0.08em',
        'opacity': '0.8',
      },
    ),
    css('.hermuse-identity-card-foot').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      fontSize: YsType.caption.size.px,
      lineHeight: YsType.caption.lineHeight.px,
      raw: {'font-family': YsType.monoFamily},
    ),
    // Full-screen editors (SOUL.md, memory).
    css('.hermuse-identity-editor').styles(
      position: .fixed(top: 0.px, left: 0.px),
      width: 100.vw,
      height: 100.vh,
      display: .flex,
      flexDirection: .column,
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      raw: {'z-index': '50', 'outline': 'none'},
    ),
    css('.hermuse-identity-editor-bar').styles(
      padding: .symmetric(vertical: YsSpace.sm.px, horizontal: YsSpace.lg.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
      border: .only(
        bottom: .solid(color: .variable('--line'), width: ysHairline.px),
      ),
    ),
    css('.hermuse-identity-editor-title').styles(
      margin: .zero,
      flex: .grow(1),
      fontSize: YsType.heading.size.px,
      lineHeight: YsType.heading.lineHeight.px,
      fontWeight: .w500,
    ),
    css('.hermuse-identity-editor-body').styles(
      width: 100.percent,
      maxWidth: YsLayout.threadMaxWidth.px,
      margin: .symmetric(horizontal: .auto),
      padding: .all(YsSpace.xl.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.lg.px),
      overflow: .only(y: .auto),
      flex: .grow(1),
    ),
    css('.hermuse-identity-about').styles(
      margin: .zero,
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.xs.px),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
      fontStyle: .italic,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-identity-about-head')
        .styles(fontWeight: .w600, color: .variable('--content')),
    css('.hermuse-identity-status').styles(
      margin: .zero,
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-identity-error').styles(
      margin: .zero,
      padding: .all(YsSpace.md.px),
      radius: .circular(YsRadius.row.px),
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
      color: .variable('--error'),
      backgroundColor: .variable('--error-wash'),
      raw: {'overflow-wrap': 'anywhere'},
    ),
    css('.hermuse-identity-mono .ys-textbox').styles(
      fontSize: YsType.code.size.px,
      lineHeight: YsType.code.lineHeight.px,
      raw: {'font-family': YsType.monoFamily},
    ),
    css(
      '.hermuse-memory-section',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.sm.px)),
    css('.hermuse-memory-section-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      justifyContent: .spaceBetween,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-memory-section-title').styles(
      margin: .zero,
      fontSize: YsType.heading.size.px,
      lineHeight: YsType.heading.lineHeight.px,
      fontWeight: .w500,
      raw: {'font-family': YsType.monoFamily},
    ),
    css('.hermuse-memory-section-sub').styles(
      margin: .zero,
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-memory-entry').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.xs.px),
    ),
    css('.hermuse-memory-entry > .ys-textbox').styles(flex: .grow(1)),
  ];
}

class _HermuseIdentityState extends State<HermuseIdentity> {
  _Editor? _editor;

  void _close() => setState(() => _editor = null);

  @override
  Component build(BuildContext context) {
    final instanceId = component.instanceId;
    final profile = component.profile;
    return div(classes: 'hermuse-identity', [
      div(classes: 'hermuse-identity-name', [
        span(classes: 'hermuse-identity-name-text', [
          .text(component.agentName),
        ]),
        if (component.onEditAgent case final onEdit?)
          YsButton.pill(
            icon: YsIcon.pencil,
            label: 'Edit',
            small: true,
            onPressed: onEdit,
          ),
      ]),
      div(classes: 'hermuse-identity-cards', [
        _card(
          kind: 'soul',
          label: 'SOUL',
          updatedAt: null,
          onOpen: () => setState(() => _editor = _Editor.soul),
        ),
        HermuseWatch(
          provider: agentMemoryProvider(
            instanceId,
            MemoryTarget.memory,
            profile: profile,
          ),
          builder: (context, memory) => HermuseWatch(
            provider: agentMemoryProvider(
              instanceId,
              MemoryTarget.user,
              profile: profile,
            ),
            builder: (context, user) => _card(
              kind: 'memory',
              label: 'MEMORY',
              updatedAt: _latest(
                memory.value?.updatedAt,
                user.value?.updatedAt,
              ),
              onOpen: () => setState(() => _editor = _Editor.memory),
            ),
          ),
        ),
      ]),
      switch (_editor) {
        _Editor.soul => _SoulEditor(
          instanceId: instanceId,
          profile: profile,
          onClose: _close,
        ),
        _Editor.memory => _MemoryEditor(
          instanceId: instanceId,
          profile: profile,
          onClose: _close,
        ),
        null => .fragment([]),
      },
    ]);
  }

  Component _card({
    required String kind,
    required String label,
    required DateTime? updatedAt,
    required VoidCallback onOpen,
  }) => YsPressable(
    onPressed: onOpen,
    label: 'Open $label',
    classes: 'hermuse-identity-card hermuse-identity-$kind ys-lift ys-press',
    builder: (context, press) => .fragment([
      span(classes: 'hermuse-identity-card-head', [
        span(classes: 'hermuse-identity-card-label', [.text(label)]),
        span(classes: 'hermuse-identity-caption', [.text('ACCESS WITH CARE')]),
      ]),
      span(classes: 'hermuse-identity-card-foot', [
        span([.text(updatedAt == null ? '' : _shortDate(updatedAt))]),
        YsIconView(YsIcon.heart, size: 18),
      ]),
    ]),
  );

  static DateTime? _latest(DateTime? a, DateTime? b) => a == null
      ? b
      : b == null || a.isAfter(b)
      ? a
      : b;

  /// "10.03.26": MM.DD.YY, local.
  static String _shortDate(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.month)}.${two(local.day)}.${two(local.year % 100)}';
  }
}

/// Escape anywhere closes the open full-screen editor only, not the panel
/// under it: the document sees the key before the window's shell handler.
StreamSubscription<web.KeyboardEvent> _escapeCloses(VoidCallback onClose) => web
    .EventStreamProviders
    .keyDownEvent
    .forTarget(web.document)
    .listen((event) {
      if (event.key != 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      onClose();
    });

/// The bar of a full-screen editor: back, title, Save.
Component _editorBar({
  required String title,
  required VoidCallback onClose,
  required VoidCallback? onSave,
  required bool saving,
}) => div(classes: 'hermuse-identity-editor-bar', [
  YsButton.icon(
    icon: YsIcon.arrowLeft,
    label: 'Close $title',
    onPressed: onClose,
  ),
  h2(classes: 'hermuse-identity-editor-title', [.text(title)]),
  YsButton.primary(label: saving ? 'Saving…' : 'Save', onPressed: onSave),
]);

/// Full-screen editor of the agent's `SOUL.md`.
class _SoulEditor extends StatefulComponent {
  const _SoulEditor({
    required this.instanceId,
    required this.profile,
    required this.onClose,
  });

  final String instanceId;
  final String profile;
  final VoidCallback onClose;

  @override
  State<_SoulEditor> createState() => _SoulEditorState();
}

class _SoulEditorState extends State<_SoulEditor> {
  final _root = GlobalNodeKey<web.HTMLElement>();
  StreamSubscription<web.KeyboardEvent>? _escape;

  @override
  void dispose() {
    _escape?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _escape = _escapeCloses(component.onClose);
    // Focus moves into the editor, so Escape closes it right away.
    if (kIsWeb) {
      context.binding.addPostFrameCallback(() {
        if (mounted) _root.currentNode?.focus();
      });
    }
  }

  /// The text being edited; null until the saved SOUL loads.
  String? _draft;
  String? _saved;
  var _saving = false;
  String? _error;
  String? _status;

  Future<void> _save(BuildContext context, String soul) async {
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      await context.container
          .read(agentProfilesProvider(component.instanceId).notifier)
          .saveSoul(component.profile, soul);
      if (mounted) {
        setState(() {
          _saved = soul;
          _status = 'Saved';
        });
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not save SOUL.md: ${hermuseErrorText(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: agentDetailsProvider(component.instanceId, component.profile),
    builder: (context, soul) {
      if (soul.value case final loaded? when _draft == null) {
        _draft = loaded.prompt;
        _saved = loaded.prompt;
      }
      final draft = _draft;
      return div(
        key: _root,
        classes: 'hermuse-identity-editor',
        attributes: {
          'role': 'dialog',
          'aria-label': 'SOUL.md',
          'tabindex': '-1',
        },
        [
          _editorBar(
            title: 'SOUL.md',
            onClose: component.onClose,
            saving: _saving,
            onSave: draft == null || _saving || draft == _saved
                ? null
                : () => unawaited(_save(context, draft)),
          ),
          div(classes: 'hermuse-identity-editor-body', [
            p(classes: 'hermuse-identity-about', [
              span(classes: 'hermuse-identity-about-head', [
                .text('About this file'),
              ]),
              span([
                .text(
                  "This is your agent's persona. It shapes every "
                  'conversation; edit it any time.',
                ),
              ]),
            ]),
            if (draft != null)
              div(classes: 'hermuse-identity-mono', [
                YsTextBox(
                  value: draft,
                  onChanged: (value) => setState(() {
                    _draft = value;
                    _status = null;
                  }),
                  label: 'SOUL.md',
                  name: 'soul-${component.profile}',
                  minHeight: 360,
                  maxHeight: 4000,
                ),
              ])
            else if (soul.hasError)
              p(classes: 'hermuse-identity-error', [
                .text(
                  'Could not load SOUL.md: ${hermuseErrorText(soul.error!)}',
                ),
              ])
            else
              p(
                classes: 'hermuse-identity-status',
                attributes: {'role': 'status'},
                [.text('Loading SOUL.md…')],
              ),
            if (_error case final error?)
              p(
                classes: 'hermuse-identity-error',
                attributes: {'role': 'alert'},
                [.text(error)],
              ),
            if (_status case final status?)
              p(
                classes: 'hermuse-identity-status',
                attributes: {'role': 'status'},
                [.text(status)],
              ),
          ]),
        ],
      );
    },
  );
}

/// One editable entry; [id] keys its text box across additions/removals.
final class _Entry {
  _Entry(this.id, this.text);

  final int id;
  String text;
}

/// Full-screen editor of the agent's long-term memory: `MEMORY.md` (what
/// it remembers about the user's life) and `USER.md` (the user's profile),
/// one block per entry.
class _MemoryEditor extends StatefulComponent {
  const _MemoryEditor({
    required this.instanceId,
    required this.profile,
    required this.onClose,
  });

  final String instanceId;
  final String profile;
  final VoidCallback onClose;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  final _root = GlobalNodeKey<web.HTMLElement>();
  StreamSubscription<web.KeyboardEvent>? _escape;

  @override
  void dispose() {
    _escape?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _escape = _escapeCloses(component.onClose);
    // Focus moves into the editor, so Escape closes it right away.
    if (kIsWeb) {
      context.binding.addPostFrameCallback(() {
        if (mounted) _root.currentNode?.focus();
      });
    }
  }

  final _drafts = <MemoryTarget, List<_Entry>>{};
  final _dirty = <MemoryTarget>{};
  var _nextId = 0;
  var _saving = false;
  String? _error;
  String? _status;

  AgentMemoryStateProvider _provider(MemoryTarget target) =>
      agentMemoryProvider(
        component.instanceId,
        target,
        profile: component.profile,
      );

  void _edit(MemoryTarget target, void Function(List<_Entry> entries) change) =>
      setState(() {
        change(_drafts[target]!);
        _dirty.add(target);
        _status = null;
      });

  Future<void> _save(BuildContext context) async {
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      for (final target in MemoryTarget.values) {
        if (!_dirty.contains(target)) continue;
        await context.container.read(_provider(target).notifier).save([
          for (final e in _drafts[target]!) e.text,
        ]);
        _dirty.remove(target);
      }
      if (mounted) setState(() => _status = 'Saved');
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not save memory: ${hermuseErrorText(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: _provider(MemoryTarget.memory),
    builder: (context, memory) => HermuseWatch(
      provider: _provider(MemoryTarget.user),
      builder: (context, user) {
        for (final (target, value) in [
          (MemoryTarget.memory, memory),
          (MemoryTarget.user, user),
        ]) {
          if (value.value case final loaded?
              when !_drafts.containsKey(target)) {
            _drafts[target] = [
              for (final text in loaded.entries) _Entry(_nextId++, text),
            ];
          }
        }
        return div(
          key: _root,
          classes: 'hermuse-identity-editor',
          attributes: {
            'role': 'dialog',
            'aria-label': 'Memory',
            'tabindex': '-1',
          },
          [
            _editorBar(
              title: 'Memory',
              onClose: component.onClose,
              saving: _saving,
              onSave: _saving || _dirty.isEmpty
                  ? null
                  : () => unawaited(_save(context)),
            ),
            div(classes: 'hermuse-identity-editor-body', [
              p(classes: 'hermuse-identity-about', [
                span(classes: 'hermuse-identity-about-head', [
                  .text('About this file'),
                ]),
                span([
                  .text(
                    "This is your agent's long-term memory: facts and "
                    'preferences worth keeping, gathered from your '
                    'conversations. It can be out of date; edit anything or '
                    'ask your agent to forget something.',
                  ),
                ]),
              ]),
              _section(
                MemoryTarget.memory,
                memory,
                'What your agent remembers about your life',
              ),
              _section(MemoryTarget.user, user, 'Your profile'),
              if (_error case final error?)
                p(
                  classes: 'hermuse-identity-error',
                  attributes: {'role': 'alert'},
                  [.text(error)],
                ),
              if (_status case final status?)
                p(
                  classes: 'hermuse-identity-status',
                  attributes: {'role': 'status'},
                  [.text(status)],
                ),
            ]),
          ],
        );
      },
    ),
  );

  Component _section(
    MemoryTarget target,
    AsyncValue<AgentMemory> value,
    String about,
  ) {
    final entries = _drafts[target];
    return section(classes: 'hermuse-memory-section', [
      div(classes: 'hermuse-memory-section-head', [
        div([
          h3(classes: 'hermuse-memory-section-title', [.text(target.fileName)]),
          p(classes: 'hermuse-memory-section-sub', [.text(about)]),
        ]),
        if (entries != null)
          YsButton.pill(
            icon: YsIcon.plus,
            label: 'Add entry',
            small: true,
            onPressed: () =>
                _edit(target, (list) => list.add(_Entry(_nextId++, ''))),
          ),
      ]),
      if (entries == null)
        p(
          classes: value.hasError
              ? 'hermuse-identity-error'
              : 'hermuse-identity-status',
          attributes: {'role': 'status'},
          [
            .text(
              value.hasError
                  ? 'Could not load ${target.fileName}: ${hermuseErrorText(value.error!)}'
                  : 'Loading ${target.fileName}…',
            ),
          ],
        )
      else if (entries.isEmpty)
        p(classes: 'hermuse-identity-status', [.text('No entries yet.')])
      else
        for (final (index, entry) in entries.indexed)
          div(
            key: ValueKey('${target.name}:${entry.id}'),
            classes: 'hermuse-memory-entry',
            [
              YsTextBox(
                value: entry.text,
                onChanged: (text) => _edit(target, (_) => entry.text = text),
                label: '${target.fileName} entry ${index + 1}',
                name: '${target.name}-${entry.id}',
                minHeight: 64,
                maxHeight: 320,
              ),
              YsButton.icon(
                icon: YsIcon.trash,
                label: 'Delete ${target.fileName} entry ${index + 1}',
                size: 32,
                iconSize: 16,
                onPressed: () => _edit(target, (list) => list.remove(entry)),
              ),
            ],
          ),
    ]);
  }
}
