import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/agents.dart';
import '../shell/screens.dart' show YsDialogError;
import '../thread/markdown_view.dart';
import 'panel_parts.dart';

/// The Identity tab: the agent's name with Edit (the agent editor), then
/// its SOUL and MEMORY cards, each opening a full-screen editor.
final class IdentityTab extends ConsumerStatefulWidget {
  const IdentityTab({
    required this.instanceId,
    required this.profile,
    required this.agentName,
    super.key,
  });

  final String instanceId;
  final String profile;
  final String agentName;

  @override
  ConsumerState<IdentityTab> createState() => _IdentityTabState();
}

enum _Editor { soul, memory }

final class _IdentityTabState extends ConsumerState<IdentityTab> {
  final _portal = OverlayPortalController();
  _Editor _editor = _Editor.soul;

  void _open(_Editor editor) {
    setState(() => _editor = editor);
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final memory = ref
        .watch(
          agentMemoryProvider(
            widget.instanceId,
            MemoryTarget.memory,
            profile: widget.profile,
          ),
        )
        .value;
    final user = ref
        .watch(
          agentMemoryProvider(
            widget.instanceId,
            MemoryTarget.user,
            profile: widget.profile,
          ),
        )
        .value;
    final memoryUpdated = [
      ?memory?.updatedAt,
      ?user?.updatedAt,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => switch (_editor) {
        _Editor.soul => SoulEditor(
          instanceId: widget.instanceId,
          profile: widget.profile,
          onClose: _portal.hide,
        ),
        _Editor.memory => MemoryEditor(
          instanceId: widget.instanceId,
          profile: widget.profile,
          onClose: _portal.hide,
        ),
      },
      child: ListView(
        padding: const EdgeInsets.only(top: YsSpace.sm),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperColor,
              borderRadius: BorderRadius.circular(YsRadius.bubble),
              boxShadow: palette.raisedShadows,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                YsSpace.lg,
                YsSpace.md,
                YsSpace.md,
                YsSpace.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name',
                          style: YsType.caption.flutter.copyWith(
                            color: palette.contentMutedColor,
                          ),
                        ),
                        Text(
                          widget.agentName,
                          style: YsType.heading.flutter.copyWith(
                            color: palette.contentColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AgentEditorAnchor(
                    instanceId: widget.instanceId,
                    profile: widget.profile,
                    builder: (context, edit) => YsButton.neutral(
                      label: 'Edit',
                      icon: YsIcon.pencil,
                      semanticLabel: 'Edit ${widget.agentName}',
                      onPressed: edit,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: YsSpace.md),
          Row(
            children: [
              Expanded(
                child: _IdentityCard(
                  label: 'SOUL',
                  start: palette.soulStartColor,
                  end: palette.soulEndColor,
                  semanticLabel: 'Open SOUL.md',
                  onPressed: () => _open(_Editor.soul),
                ),
              ),
              const SizedBox(width: YsSpace.md),
              Expanded(
                child: _IdentityCard(
                  label: 'MEMORY',
                  start: palette.memoryStartColor,
                  end: palette.memoryEndColor,
                  updatedAt: memoryUpdated,
                  semanticLabel: 'Open memory',
                  onPressed: () => _open(_Editor.memory),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A gradient card of the Identity tab: file label, "ACCESS WITH CARE",
/// last update and a heart.
final class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.label,
    required this.start,
    required this.end,
    required this.semanticLabel,
    required this.onPressed,
    this.updatedAt,
  });

  final String label;
  final Color start;
  final Color end;
  final String semanticLabel;
  final VoidCallback onPressed;

  /// Last write of the file(s); null when unknown.
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final ink = palette.identityContentColor;
    final updatedAt = this.updatedAt;
    final mono = YsType.micro.flutter.copyWith(
      fontFamily: YsType.monoFamily,
      color: ink,
    );
    return YsPressable(
      onPressed: onPressed,
      // The card's caption and stamp are decoration: the label says it all.
      semanticLabel: updatedAt == null
          ? semanticLabel
          : '$semanticLabel, updated ${formatDotDate(updatedAt)}',
      builder: (context, state) => YsFocusRing(
        visible: state.focused,
        radius: YsRadius.bubble,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: YsMotion.fast),
          height: YsLayout.identityCardHeight,
          padding: const EdgeInsets.all(YsSpace.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [start, end],
            ),
            borderRadius: BorderRadius.circular(YsRadius.bubble),
            boxShadow: state.hovered ? palette.raisedShadows : const [],
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: YsType.heading.flutter.copyWith(color: ink)),
                const SizedBox(height: YsSpace.xxs),
                Text('ACCESS WITH CARE', style: mono),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        updatedAt == null ? '' : formatDotDate(updatedAt),
                        style: mono,
                      ),
                    ),
                    YsIconWidget(
                      YsIcon.heart,
                      size: YsLayout.inlineIcon,
                      color: ink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen page over the app: a bar with close, [title] and Save, then
/// [body] in a centred reading column.
final class _EditorPage extends StatelessWidget {
  const _EditorPage({
    required this.title,
    required this.onClose,
    required this.onSave,
    required this.saving,
    required this.body,
    this.error,
    this.trailing = const [],
  });

  final String title;
  final VoidCallback onClose;

  /// Null while there is nothing to save yet (loading).
  final VoidCallback? onSave;
  final bool saving;
  final String? error;
  final List<Widget> trailing;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final error = this.error;
    return BlockSemantics(
      child: FocusScope(
        autofocus: true,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
          child: ColoredBox(
            color: palette.canvasColor,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(YsSpace.lg),
                    child: Row(
                      children: [
                        YsButton.icon(
                          icon: YsIcon.close,
                          onPressed: saving ? null : onClose,
                          semanticLabel: 'Close $title',
                          tooltip: 'Close',
                          size: 36,
                        ),
                        const SizedBox(width: YsSpace.sm),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: YsType.title.flutter.copyWith(
                                color: palette.contentColor,
                              ),
                            ),
                          ),
                        ),
                        ...trailing,
                        const SizedBox(width: YsSpace.sm),
                        YsButton.primary(
                          label: saving ? 'Saving…' : 'Save',
                          onPressed: saving ? null : onSave,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        YsSpace.lg,
                        0,
                        YsSpace.lg,
                        YsSpace.xxl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: YsLayout.threadMaxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null) ...[
                                YsDialogError(error),
                                const SizedBox(height: YsSpace.md),
                              ],
                              ...body,
                            ],
                          ),
                        ),
                      ),
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

/// Italic "About this file" note heading an editor.
final class _AboutNote extends StatelessWidget {
  const _AboutNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final style = YsType.small.flutter.copyWith(
      color: palette.contentMutedColor,
      fontStyle: FontStyle.italic,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.lg),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About this file',
              style: style.copyWith(color: palette.contentColor),
            ),
            const SizedBox(height: YsSpace.xxs),
            Text(text, style: style),
          ],
        ),
      ),
    );
  }
}

/// Bordered multi-line box: Enter adds a line.
final class _EditBox extends StatelessWidget {
  const _EditBox({
    required this.controller,
    required this.semanticLabel,
    this.minLines = 1,
    this.placeholder = '',
    this.focusNode,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final int minLines;
  final String placeholder;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(YsSpace.md),
        child: YsTextArea(
          controller: controller,
          focusNode: focusNode,
          semanticLabel: semanticLabel,
          placeholder: placeholder,
          minLines: minLines,
          maxLines: null,
          enterSubmits: false,
          textInputAction: TextInputAction.newline,
          textStyle: YsType.input,
        ),
      ),
    );
  }
}

String _saveError(Object error) => switch (error) {
  ArgumentError(:final message) => '$message',
  _ => '$error',
};

/// SOUL.md, the agent's persona, as editable Markdown with a preview.
final class SoulEditor extends ConsumerStatefulWidget {
  const SoulEditor({
    required this.instanceId,
    required this.profile,
    required this.onClose,
    super.key,
  });

  final String instanceId;
  final String profile;
  final VoidCallback onClose;

  @override
  ConsumerState<SoulEditor> createState() => _SoulEditorState();
}

final class _SoulEditorState extends ConsumerState<SoulEditor> {
  final _text = TextEditingController();
  bool _loaded = false;
  bool _preview = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final details = await ref.read(
        agentDetailsProvider(widget.instanceId, widget.profile).future,
      );
      if (!mounted) return;
      _text.text = details.prompt;
      setState(() => _loaded = true);
    } catch (error) {
      if (mounted) setState(() => _error = "Couldn't load SOUL.md: $error");
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(agentProfilesProvider(widget.instanceId).notifier)
          .saveSoul(widget.profile, _text.text);
      if (mounted) widget.onClose();
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EditorPage(
    title: 'SOUL.md',
    onClose: widget.onClose,
    onSave: _loaded ? () => unawaited(_save()) : null,
    saving: _saving,
    error: _error,
    trailing: [
      if (_loaded)
        YsButton.neutral(
          label: _preview ? 'Edit' : 'Preview',
          onPressed: () => setState(() => _preview = !_preview),
        ),
    ],
    body: [
      const _AboutNote(
        "This is your agent's persona. It shapes every conversation; edit it "
        'any time.',
      ),
      if (!_loaded && _error == null)
        const Center(child: YsSpinner())
      else if (!_loaded)
        Align(
          alignment: Alignment.centerLeft,
          child: YsButton.neutral(
            label: 'Retry',
            onPressed: () => unawaited(_load()),
          ),
        )
      else if (_preview)
        MarkdownView(_text.text)
      else
        _EditBox(controller: _text, semanticLabel: 'SOUL.md', minLines: 16),
    ],
  );
}

/// What the memory editor's sections say about their file.
String _sectionHelp(MemoryTarget target) => switch (target) {
  MemoryTarget.memory => 'What your agent remembers about your life',
  MemoryTarget.user => 'Your profile',
};

/// The agent's long-term memory: MEMORY.md and USER.md, one editable block
/// per entry.
final class MemoryEditor extends ConsumerStatefulWidget {
  const MemoryEditor({
    required this.instanceId,
    required this.profile,
    required this.onClose,
    super.key,
  });

  final String instanceId;
  final String profile;
  final VoidCallback onClose;

  @override
  ConsumerState<MemoryEditor> createState() => _MemoryEditorState();
}

final class _MemoryEditorState extends ConsumerState<MemoryEditor> {
  /// Entries being edited, per file; null until loaded.
  Map<MemoryTarget, List<TextEditingController>>? _entries;

  /// Entries as loaded, per file: only changed files are written.
  final _loaded = <MemoryTarget, List<String>>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  AgentMemoryStateProvider _provider(MemoryTarget target) =>
      agentMemoryProvider(widget.instanceId, target, profile: widget.profile);

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final files = await Future.wait([
        for (final target in MemoryTarget.values)
          ref.read(_provider(target).future),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = {
          for (final file in files)
            file.target: [
              for (final entry in file.entries)
                TextEditingController(text: entry),
            ],
        };
        for (final file in files) {
          _loaded[file.target] = file.entries;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = "Couldn't load the memory: $error");
    }
  }

  Future<void> _save() async {
    final entries = _entries;
    if (entries == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final target in MemoryTarget.values) {
        final texts = [for (final c in entries[target]!) c.text];
        if (_same(texts, _loaded[target] ?? const [])) continue;
        await ref.read(_provider(target).notifier).save(texts);
      }
      if (mounted) widget.onClose();
    } catch (error) {
      if (mounted) setState(() => _error = "Couldn't save: $error");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The entry "Add entry" created last and its box's focus: the caret
  /// moves there once the box is built.
  TextEditingController? _added;
  final _addedFocus = FocusNode(debugLabel: 'Added memory entry');

  void _add(MemoryTarget target) {
    setState(() => _entries![target]!.add(_added = TextEditingController()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addedFocus.requestFocus();
    });
  }

  void _remove(MemoryTarget target, int index) =>
      setState(() => _entries![target]!.removeAt(index).dispose());

  @override
  void dispose() {
    for (final list
        in _entries?.values ?? const <List<TextEditingController>>[]) {
      for (final c in list) {
        c.dispose();
      }
    }
    _addedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return _EditorPage(
      title: 'Memory',
      onClose: widget.onClose,
      onSave: entries == null ? null : () => unawaited(_save()),
      saving: _saving,
      error: _error,
      body: [
        const _AboutNote(
          "This is your agent's long-term memory: facts and preferences "
          'worth keeping, gathered from your conversations. It can be out of '
          'date; edit anything or ask your agent to forget something.',
        ),
        if (entries == null && _error == null)
          const Center(child: YsSpinner())
        else if (entries == null)
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.neutral(
              label: 'Retry',
              onPressed: () => unawaited(_load()),
            ),
          )
        else
          for (final target in MemoryTarget.values)
            _section(target, entries[target]!),
      ],
    );
  }

  Widget _section(MemoryTarget target, List<TextEditingController> entries) {
    final palette = YsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeading(target.fileName),
          Text(
            _sectionHelp(target),
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
          const SizedBox(height: YsSpace.sm),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: YsSpace.sm),
              child: Text(
                'No entries yet.',
                style: YsType.small.flutter.copyWith(
                  color: palette.contentSubtleColor,
                ),
              ),
            ),
          for (final (index, controller) in entries.indexed)
            Padding(
              key: ObjectKey(controller),
              padding: const EdgeInsets.only(bottom: YsSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _EditBox(
                      controller: controller,
                      semanticLabel: '${target.fileName} entry ${index + 1}',
                      placeholder: 'Something worth remembering',
                      focusNode: identical(controller, _added)
                          ? _addedFocus
                          : null,
                    ),
                  ),
                  const SizedBox(width: YsSpace.xs),
                  YsButton.icon(
                    icon: YsIcon.trash,
                    onPressed: () => _remove(target, index),
                    semanticLabel:
                        'Delete ${target.fileName} entry ${index + 1}',
                    tooltip: 'Delete entry',
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: YsButton.neutral(
              label: 'Add entry',
              icon: YsIcon.plus,
              semanticLabel: 'Add ${target.fileName} entry',
              onPressed: () => _add(target),
            ),
          ),
        ],
      ),
    );
  }
}
