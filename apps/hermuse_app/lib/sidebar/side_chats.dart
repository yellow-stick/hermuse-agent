import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart' show SessionRow;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/screens.dart' show describeError;

/// Name shown for a side chat: its title, or "New side chat" until the agent
/// titles it after the first message.
String sideChatLabel(String title) => title.isEmpty ? 'New side chat' : title;

/// Row titles, search snippets and menu items: 14/20 regular.
const _rowText = YsTextStyle(14, 20);

/// Empty-state titles ("Start a side chat"): 15/20 medium.
const _emptyTitle = YsTextStyle(15, 20, YsWeight.medium);

/// Selected / hovered row: `rgba(255,255,255,.12)` at 50 %, i.e. the line
/// colour at half its alpha.
Color _rowFilm(YsPalette palette) =>
    palette.lineColor.withValues(alpha: palette.lineColor.a / 2);

bool _isDraft(String threadId) => threadId.startsWith('draft-');

/// Chats panel: the instance's "Main chat" and its side
/// chats, full-text search, archived chats and per-row actions (pin, rename,
/// archive, delete).
final class SideChats extends ConsumerStatefulWidget {
  const SideChats({
    required this.controller,
    required this.onPicked,
    this.keepVisible = false,
    this.onKeepVisibleChanged,
    super.key,
  });

  final ChatController controller;

  /// A thread was opened from the panel (row, search result, new side chat):
  /// the shell closes the panel unless it is kept visible.
  final VoidCallback onPicked;

  /// "Keep chat panel visible". Offered only where the panel docks beside
  /// the thread ([onKeepVisibleChanged] set), not in the phone drawer.
  final bool keepVisible;
  final ValueChanged<bool>? onKeepVisibleChanged;

  @override
  ConsumerState<SideChats> createState() => SideChatsState();
}

final class SideChatsState extends ConsumerState<SideChats> {
  static const _searchDelay = Duration(milliseconds: 150);

  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search chats');
  Timer? _searchTimer;
  String _query = '';

  /// Results of the last search that ran; null before the first one.
  List<ChatSearchHit>? _hits;
  String _hitsQuery = '';

  bool _archivedView = false;
  bool _collapsed = false;

  /// Side chat whose row is an inline rename field.
  String? _renaming;

  /// Side chat awaiting the delete confirmation.
  ({String id, String title})? _deleting;
  final _deleteDialog = OverlayPortalController();

  /// Last failed action, shown until dismissed or the next action.
  String? _error;

  ChatController get _chat => widget.controller;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The main chat as stored ('' while it is still a draft).
  ThreadRef get _mainRef {
    final id = _chat.state.mainThread.id;
    return ThreadRef(
      instanceId: _chat.instanceId,
      sessionId: _isDraft(id) ? '' : id,
    );
  }

  // ------------------------------------------------------------------ search

  void _onQuery(String value) {
    _searchTimer?.cancel();
    setState(() {
      _query = value;
      if (value.trim().isEmpty) _hits = null;
    });
    if (value.trim().isEmpty) return;
    _searchTimer = Timer(_searchDelay, () => unawaited(_runSearch(value)));
  }

  Future<void> _runSearch(String query) async {
    try {
      final hits = await chatSearch(
        ref.read(hermuseDatabaseProvider),
        _chat,
        query,
      );
      if (!mounted || query != _query) return;
      setState(() {
        _hits = hits;
        _hitsQuery = query;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: ${describeError(e)}');
    }
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _hits = null;
    });
    _searchFocus.requestFocus();
  }

  // ----------------------------------------------------------------- actions

  void _open(String threadId) {
    _chat.openThread(threadId);
    widget.onPicked();
  }

  void _newSideChat() {
    _chat.newSideChat();
    widget.onPicked();
  }

  /// Runs a server-backed action, showing its failure in the panel.
  Future<void> _run(String failure, Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$failure: ${describeError(e)}');
    }
  }

  void _setPinned(SideChatEntry entry) => unawaited(
    _run(
      entry.pinned
          ? "Couldn't unpin the side chat"
          : "Couldn't pin the side chat",
      () => setSideChatPinned(
        ref.read(hermuseDatabaseProvider),
        ThreadRef(instanceId: _chat.instanceId, sessionId: entry.threadId),
        pinned: !entry.pinned,
      ),
    ),
  );

  void _rename(String threadId, String title) {
    setState(() => _renaming = null);
    unawaited(
      _run(
        "Couldn't rename the side chat",
        () => _chat.renameThread(threadId, title),
      ),
    );
  }

  void _archive(String threadId) => unawaited(
    _run("Couldn't archive the side chat", () => _chat.archiveThread(threadId)),
  );

  void _confirmDelete(SideChatEntry entry) {
    setState(
      () => _deleting = (id: entry.threadId, title: sideChatLabel(entry.title)),
    );
    _deleteDialog.show();
  }

  void _closeDelete() {
    _deleteDialog.hide();
    setState(() => _deleting = null);
  }

  void _delete() {
    final target = _deleting;
    _closeDelete();
    if (target == null) return;
    unawaited(
      _run(
        "Couldn't delete the side chat",
        () => _chat.deleteThread(target.id),
      ),
    );
  }

  void _restore(SessionRow row) => unawaited(
    _run(
      "Couldn't restore the side chat",
      () => _chat.restoreThread(row.sessionId, title: row.title),
    ),
  );

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final main = _mainRef;
    final rows =
        ref.watch(sideChatsProvider(main)).value ?? const <SessionRow>[];
    final archived =
        ref.watch(sideChatsProvider(main, archived: true)).value ??
        const <SessionRow>[];
    final error = _error;
    return OverlayPortal(
      controller: _deleteDialog,
      overlayChildBuilder: _deleteConfirmation,
      child: Column(
        children: [
          Expanded(
            child: _archivedView
                ? _archivedPanel(archived)
                : _chatsPanel(
                    main,
                    sideChatEntries(_chat.state, rows),
                    archived,
                  ),
          ),
          if (error != null)
            _ErrorNotice(
              message: error,
              onDismiss: () => setState(() => _error = null),
            ),
        ],
      ),
    );
  }

  Widget _chatsPanel(
    ThreadRef main,
    List<SideChatEntry> entries,
    List<SessionRow> archived,
  ) {
    final Widget content;
    if (_query.trim().isNotEmpty) {
      content = _results();
    } else if (entries.isEmpty && archived.isEmpty) {
      content = _EmptyBlock(
        icon: YsIcon.sideChat,
        title: 'Start a side chat',
        body:
            'Side chats are an optional way to organize your conversations '
            'by topic.',
        action: YsButton.neutral(
          label: 'New side chat',
          onPressed: _newSideChat,
        ),
      );
    } else {
      content = _list(main, entries);
    }
    return Column(
      children: [
        _topBar(),
        Expanded(child: content),
      ],
    );
  }

  /// Search pill + "Side chat options" menu.
  Widget _topBar() {
    final palette = YsTheme.of(context);
    final onKeepVisibleChanged = widget.onKeepVisibleChanged;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.paperClearColor,
                  borderRadius: BorderRadius.circular(YsRadius.pill),
                  border: Border.all(
                    color: palette.lineColor,
                    width: ysHairline,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 10,
                    right: _query.isEmpty ? 16 : 6,
                  ),
                  child: Row(
                    children: [
                      YsIconWidget(
                        YsIcon.search,
                        size: 18,
                        color: palette.contentMutedColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: YsTextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          placeholder: 'Search',
                          semanticLabel: 'Search chats',
                          textStyle: YsType.label,
                          onChanged: _onQuery,
                        ),
                      ),
                      if (_query.isNotEmpty)
                        YsButton.icon(
                          icon: YsIcon.close,
                          onPressed: _clearSearch,
                          semanticLabel: 'Clear search',
                          tooltip: 'Clear search',
                          size: 24,
                          iconSize: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          YsMenuAnchor(
            semanticLabel: 'Side chat options',
            items: [
              if (onKeepVisibleChanged != null)
                YsMenuItem(
                  label: 'Keep chat panel visible',
                  checked: widget.keepVisible,
                  onSelected: () => onKeepVisibleChanged(!widget.keepVisible),
                ),
              YsMenuItem(
                label: 'Show archived chats',
                icon: YsIcon.archive,
                onSelected: () => setState(() => _archivedView = true),
              ),
            ],
            builder: (context, menu) => YsButton.icon(
              icon: YsIcon.more,
              onPressed: () => menu.open(),
              semanticLabel: 'Side chat options',
              tooltip: 'Side chat options',
              size: 24,
              iconSize: 15,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Main chat row, then the collapsible "Side chats" section.
  Widget _list(ThreadRef main, List<SideChatEntry> entries) {
    final state = _chat.state;
    final mainId = state.mainThread.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      children: [
        _ChatRow(
          title: 'Main chat',
          selected: state.activeThreadId == mainId,
          time: ref.watch(mainChatUpdatedAtProvider(main)).value,
          onPressed: () => _open(mainId),
        ),
        const SizedBox(height: 1),
        _SectionHeader(
          collapsed: _collapsed,
          onToggle: () => setState(() => _collapsed = !_collapsed),
          onNewSideChat: _newSideChat,
        ),
        _Collapsible(
          collapsed: _collapsed,
          child: entries.isEmpty
              // Every side chat is archived.
              ? const _EmptyBlock(
                  title: 'Start a side chat',
                  body:
                      'Side chats are an optional way to organize your '
                      'conversations by topic.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: _entryRow(entry, state.activeThreadId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _entryRow(SideChatEntry entry, String activeThreadId) {
    final id = entry.threadId;
    if (_renaming == id) {
      return _RenameRow(
        key: ValueKey('rename $id'),
        initial: entry.title,
        onCancel: () => setState(() => _renaming = null),
        onSubmit: (title) => _rename(id, title),
      );
    }
    return _ChatRow(
      key: ValueKey(id),
      title: sideChatLabel(entry.title),
      pinned: entry.pinned,
      selected: activeThreadId == id,
      time: entry.updatedAt,
      onPressed: () => _open(id),
      menu: [
        // Pins are stored locally per saved session.
        if (!_isDraft(id))
          YsMenuItem(
            label: entry.pinned ? 'Unpin' : 'Pin',
            icon: YsIcon.pin,
            onSelected: () => _setPinned(entry),
          ),
        YsMenuItem(
          label: 'Rename',
          icon: YsIcon.pencil,
          onSelected: () => setState(() => _renaming = id),
        ),
        YsMenuItem(
          label: 'Archive',
          icon: YsIcon.archive,
          onSelected: () => _archive(id),
        ),
        YsMenuItem(
          label: 'Delete',
          icon: YsIcon.trash,
          destructive: true,
          onSelected: () => _confirmDelete(entry),
        ),
      ],
    );
  }

  /// Search results in place of the list: matching text, thread, time-ago.
  Widget _results() {
    final palette = YsTheme.of(context);
    final hits = _hits;
    // Waiting for the first results of this search.
    if (hits == null) return const SizedBox.shrink();
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            'No results',
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      children: [
        for (final hit in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: _SearchHitRow(
              text: _snippet(hit.text, _hitsQuery),
              thread: hit.isTitle
                  ? 'Side chat'
                  : sideChatLabel(hit.threadTitle),
              time: hit.updatedAt,
              selected: _chat.state.activeThreadId == hit.threadId,
              onPressed: () => _open(hit.threadId),
            ),
          ),
      ],
    );
  }

  /// "Archived chats": back button, heading, archived rows (Restore).
  Widget _archivedPanel(List<SessionRow> rows) {
    final palette = YsTheme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              YsButton.icon(
                icon: YsIcon.chevronLeft,
                onPressed: () => setState(() => _archivedView = false),
                semanticLabel: 'Back to chat list',
                tooltip: 'Back to chat list',
                size: 36,
                iconSize: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Archived chats',
                    style: YsType.label.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const _EmptyBlock(
                  title: 'No archived chats',
                  body: 'Side chats you archive will appear here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: _ChatRow(
                          key: ValueKey(row.sessionId),
                          title: sideChatLabel(row.title),
                          selected: false,
                          time: DateTime.fromMillisecondsSinceEpoch(
                            row.updatedAt,
                          ),
                          alwaysShowTime: true,
                          menu: [
                            YsMenuItem(
                              label: 'Restore from archive',
                              icon: YsIcon.archive,
                              onSelected: () => _restore(row),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _deleteConfirmation(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsDialog(
      title: 'Delete side chat?',
      onClose: _closeDelete,
      actions: [
        YsButton.neutral(label: 'Cancel', onPressed: _closeDelete),
        YsButton.destructive(label: 'Delete', onPressed: _delete),
      ],
      child: Text(
        'Deleting this side chat permanently removes it and cannot be undone.',
        style: YsType.small.flutter.copyWith(color: palette.contentColor),
      ),
    );
  }
}

/// [text] on one line, starting shortly before the first match of [query]
/// so the match shows in a two-line snippet.
String _snippet(String text, String query) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = flat.toLowerCase();
  var at = -1;
  for (final term in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (term.isEmpty) continue;
    final i = lower.indexOf(term);
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 40) return flat;
  var start = at - 24;
  final space = flat.indexOf(' ', start);
  if (space >= 0 && space < at) start = space + 1;
  return '…${flat.substring(start)}';
}

/// One thread row (Main chat, side chat, archived side chat): 36 high, no
/// leading icon (pin icon when pinned), time-ago and "More thread actions"
/// on hover or focus; right-click / long-press opens the same [menu].
final class _ChatRow extends StatefulWidget {
  const _ChatRow({
    required this.title,
    required this.selected,
    this.onPressed,
    this.pinned = false,
    this.time,
    this.alwaysShowTime = false,
    this.menu,
    super.key,
  });

  final String title;
  final bool selected;

  /// Opens the thread; null opens the [menu] (archived rows).
  final VoidCallback? onPressed;
  final bool pinned;

  /// Last activity, shown as time-ago; null when unknown (draft).
  final DateTime? time;
  final bool alwaysShowTime;

  /// "More thread actions"; null for the Main chat row.
  final List<YsMenuItem>? menu;

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

final class _ChatRowState extends State<_ChatRow> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.menu;
    if (items == null) return _row(null);
    return YsMenuAnchor(
      semanticLabel: 'More thread actions',
      items: items,
      onOpenChanged: (open) => setState(() => _menuOpen = open),
      builder: (context, menu) => GestureDetector(
        onSecondaryTapUp: (details) =>
            menu.open(position: details.globalPosition),
        onLongPressStart: (details) =>
            menu.open(position: details.globalPosition),
        child: _row(menu),
      ),
    );
  }

  Widget _row(YsMenuController? menu) {
    final palette = YsTheme.of(context);
    final time = widget.time;
    return Semantics(
      container: true,
      selected: widget.selected,
      child: YsPressable(
        onPressed:
            widget.onPressed ?? (menu == null ? null : () => menu.open()),
        builder: (context, state) {
          final active = state.hovered || state.focused || _menuOpen;
          final film = _rowFilm(palette);
          return AnimatedContainer(
            duration: const Duration(milliseconds: YsMotion.fast),
            height: 36,
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: widget.selected || active
                  ? film
                  : film.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(YsRadius.navRow),
            ),
            child: Row(
              children: [
                if (widget.pinned)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: YsIconWidget(
                      YsIcon.pin,
                      size: 16,
                      color: palette.contentMutedColor,
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      widget.title,
                      style: _rowText.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
                if (time != null && (active || widget.alwaysShowTime))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      formatTimeAgo(time, DateTime.now()),
                      style: YsType.caption.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                    ),
                  ),
                if (menu != null && active)
                  Builder(
                    builder: (button) => YsButton.icon(
                      icon: YsIcon.more,
                      onPressed: () => menu.open(anchor: button),
                      semanticLabel: 'More thread actions',
                      tooltip: 'More thread actions',
                      size: 24,
                      iconSize: 20,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A side chat row turned into a name field: Enter or ✓ saves, Escape or ✕
/// cancels.
final class _RenameRow extends StatefulWidget {
  const _RenameRow({
    required this.initial,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  /// Current title ('' while untitled).
  final String initial;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmit;

  @override
  State<_RenameRow> createState() => _RenameRowState();
}

final class _RenameRowState extends State<_RenameRow> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  late final _focus = FocusNode(
    debugLabel: 'Rename side chat',
    onKeyEvent: _onKey,
  );

  @override
  void initState() {
    super.initState();
    // Opened from a menu, which hands focus back to its trigger: take it
    // once that settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !_text.value.composing.isValid) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    final title = _text.text.trim();
    if (title.isEmpty || title == widget.initial) {
      widget.onCancel();
    } else {
      widget.onSubmit(title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: palette.paperClearColor,
        borderRadius: BorderRadius.circular(YsRadius.navRow),
        border: Border.all(color: palette.primaryInkColor, width: ysHairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: YsTextField(
              controller: _text,
              focusNode: _focus,
              placeholder: sideChatLabel(''),
              semanticLabel: 'Side chat name',
              textStyle: _rowText,
              onSubmitted: (_) => _submit(),
            ),
          ),
          YsButton.icon(
            icon: YsIcon.close,
            onPressed: widget.onCancel,
            semanticLabel: 'Cancel rename',
            tooltip: 'Cancel',
            size: 24,
            iconSize: 16,
          ),
          const SizedBox(width: 2),
          YsButton.icon(
            icon: YsIcon.check,
            onPressed: _submit,
            semanticLabel: 'Save name',
            tooltip: 'Save',
            size: 24,
            iconSize: 16,
          ),
        ],
      ),
    );
  }
}

/// "Side chats": a pill that collapses the section (chevron on hover) and
/// the "New side chat" + button.
final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.collapsed,
    required this.onToggle,
    required this.onNewSideChat,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onNewSideChat;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Semantics(
            container: true,
            expanded: !collapsed,
            child: YsPressable(
              onPressed: onToggle,
              builder: (context, state) {
                final film = _rowFilm(palette);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: YsMotion.fast),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: state.hovered || state.focused
                        ? film
                        : film.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(YsRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Side chats',
                        style: YsType.label.flutter.copyWith(
                          color: palette.contentMutedColor,
                        ),
                      ),
                      if (state.hovered || state.focused) ...[
                        const SizedBox(width: 2),
                        AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: const Duration(milliseconds: YsMotion.base),
                          child: YsIconWidget(
                            YsIcon.chevronDown,
                            size: 20,
                            color: palette.contentSubtleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: YsButton.icon(
              icon: YsIcon.plus,
              onPressed: onNewSideChat,
              semanticLabel: 'New side chat',
              tooltip: 'New side chat',
              size: 24,
              iconSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapses to zero height over 200 ms (grid-rows animation);
/// hidden rows leave the focus order and the semantics tree.
final class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedAlign(
      alignment: Alignment.topCenter,
      heightFactor: collapsed ? 0 : 1,
      duration: const Duration(milliseconds: YsMotion.base),
      curve: Curves.easeInOut,
      child: ExcludeFocus(
        excluding: collapsed,
        child: ExcludeSemantics(
          excluding: collapsed,
          child: IgnorePointer(ignoring: collapsed, child: child),
        ),
      ),
    ),
  );
}

/// A search result: the matching text, then the thread and its time-ago.
final class _SearchHitRow extends StatelessWidget {
  const _SearchHitRow({
    required this.text,
    required this.thread,
    required this.time,
    required this.selected,
    required this.onPressed,
  });

  final String text;
  final String thread;
  final DateTime? time;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final time = this.time;
    final caption = YsType.caption.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    return Semantics(
      container: true,
      selected: selected,
      child: YsPressable(
        onPressed: onPressed,
        builder: (context, state) => _hit(palette, state, caption, time),
      ),
    );
  }

  Widget _hit(
    YsPalette palette,
    YsPressableState state,
    TextStyle caption,
    DateTime? time,
  ) {
    final film = _rowFilm(palette);
    return AnimatedContainer(
      duration: const Duration(milliseconds: YsMotion.fast),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: selected || state.hovered || state.focused
            ? film
            : film.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(YsRadius.navRow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            style: _rowText.flutter.copyWith(color: palette.contentColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  thread,
                  style: caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              if (time != null) ...[
                const SizedBox(width: 8),
                Text(formatTimeAgo(time, DateTime.now()), style: caption),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Centered empty state: optional icon (28 muted), 15/20 title, 13/18 body
/// and an optional action 12 px below.
final class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.title,
    required this.body,
    this.icon,
    this.action,
  });

  final YsIcon? icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final icon = this.icon;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              YsHover(
                builder: (context, hovered) => YsArtView(
                  YsArt.chats,
                  size: YsLayout.artCompact,
                  active: hovered,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              style: _emptyTitle.flutter.copyWith(color: palette.contentColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: YsType.small.flutter.copyWith(color: palette.contentColor),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              IntrinsicWidth(child: action),
            ],
          ],
        ),
      ),
    );
  }
}

/// A failed action (server refused, not connected), until dismissed.
final class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperColor,
            borderRadius: BorderRadius.circular(YsRadius.row),
            boxShadow: palette.raisedShadows,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: YsType.small.flutter.copyWith(
                      color: palette.errorColor,
                    ),
                  ),
                ),
                YsButton.icon(
                  icon: YsIcon.close,
                  onPressed: onDismiss,
                  semanticLabel: 'Dismiss',
                  tooltip: 'Dismiss',
                  size: 24,
                  iconSize: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The docked chats panel of the desktop shells: [ChatPanelPrefs.width]
/// wide with a hairline right edge that drags to resize it.
final class DockedChatPanel extends ConsumerWidget {
  const DockedChatPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final width =
        ref.watch(chatPanelProvider).value?.width ??
        ChatPanelPrefs.defaultWidth;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: palette.lineColor, width: ysHairline),
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            const Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 8,
              child: _ResizeHandle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Resize panel": drag (or arrow keys) to change the panel width, saved
/// when the drag ends.
final class _ResizeHandle extends ConsumerStatefulWidget {
  const _ResizeHandle();

  @override
  ConsumerState<_ResizeHandle> createState() => _ResizeHandleState();
}

final class _ResizeHandleState extends ConsumerState<_ResizeHandle> {
  static const _step = 16.0;

  bool _hovered = false;
  bool _focused = false;
  bool _dragging = false;
  double _dragFrom = 0;
  double _widthFrom = 0;

  ChatPanel get _panel => ref.read(chatPanelProvider.notifier);

  double get _width =>
      ref.read(chatPanelProvider).value?.width ?? ChatPanelPrefs.defaultWidth;

  static String _px(double width) =>
      '${width.clamp(ChatPanelPrefs.minWidth, ChatPanelPrefs.maxWidth).round()} px';

  void _nudge(double delta) {
    _panel.setWidth(_width + delta);
    unawaited(_panel.saveWidth());
  }

  void _endDrag() {
    setState(() => _dragging = false);
    unawaited(_panel.saveWidth());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _nudge(-_step);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nudge(_step);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final width =
        ref.watch(chatPanelProvider).value?.width ??
        ChatPanelPrefs.defaultWidth;
    final active = _hovered || _focused || _dragging;
    return Semantics(
      container: true,
      label: 'Resize panel',
      value: _px(width),
      increasedValue: _px(width + _step),
      decreasedValue: _px(width - _step),
      slider: true,
      onIncrease: () => _nudge(_step),
      onDecrease: () => _nudge(-_step),
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The edge follows the pointer from where it was pressed.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (details) => setState(() {
              _dragging = true;
              _dragFrom = details.globalPosition.dx;
              _widthFrom = width;
            }),
            onHorizontalDragUpdate: (details) => _panel.setWidth(
              _widthFrom + details.globalPosition.dx - _dragFrom,
            ),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: YsMotion.fast),
                width: 2,
                color: active
                    ? palette.contentSubtleColor
                    : palette.contentSubtleColor.withValues(alpha: 0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
