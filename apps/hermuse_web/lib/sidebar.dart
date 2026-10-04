import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';
import 'screens.dart';
import 'thread.dart';

/// "Keep chat panel visible" alone, so a width drag rebuilds the panel and
/// not the whole shell.
final chatPanelPinnedProvider = Provider<bool>(
  (ref) => ref.watch(chatPanelProvider).value?.pinned ?? false,
);

/// The chats panel (side chats) of the open main chat: "Main chat"
/// and its side chats (pin, rename, archive, delete), the archive,
/// full-text search and the options menu.
///
/// Its width follows [chatPanelProvider] and is dragged on its right edge.
class HermuseSidebar extends StatefulComponent {
  const HermuseSidebar({
    required this.controller,
    this.readOnly = false,
    required this.onOpenThread,
    required this.onNewSideChat,
    required this.onSetPinned,
    super.key,
  });

  final ChatController controller;

  /// Read-only chats (the demo): no new side chat, rename, archive, delete
  /// or restore; pins and panel options stay (they are local).
  final bool readOnly;

  /// Opens a thread of [controller]; the shell then closes the panel unless
  /// it is kept visible.
  final ValueChanged<String> onOpenThread;
  final VoidCallback onNewSideChat;

  /// Turns "Keep chat panel visible" on or off.
  final ValueChanged<bool> onSetPinned;

  @override
  State<HermuseSidebar> createState() => _HermuseSidebarState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-sidebar', [
      css('&').styles(
        height: 100.percent,
        display: .flex,
        flexDirection: .column,
        padding: .all(12.px),
        position: .relative(),
        backgroundColor: .variable('--canvas'),
        border: .only(
          right: .solid(color: .variable('--line'), width: 1.2.px),
        ),
        raw: {
          'flex-shrink': '0',
          'width':
              'var(--hermuse-chats-width, ${ChatPanelPrefs.defaultWidth}px)',
        },
      ),
      css('.hermuse-sidebar-top').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        margin: .only(bottom: 8.px),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-sidebar-search').styles(
        height: 36.px,
        padding: .only(left: 10.px, right: 16.px),
        radius: .circular(YsRadius.pill.px),
        flex: .grow(1),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(6.px),
        color: .variable('--content-muted'),
        backgroundColor: .variable('--paper-clear'),
        border: .all(color: .variable('--line'), width: ysHairline.px),
        raw: {'min-width': '0'},
      ),
      css('.hermuse-sidebar-search:has(.ys-btn-icon)')
          .styles(padding: .only(right: 6.px)),
      css('.hermuse-sidebar-search .ys-textfield').styles(
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        raw: {'min-width': '0'},
      ),
      css('.hermuse-sidebar-options').styles(
        display: .inlineFlex,
        margin: .only(right: 4.px),
      ),
      // Empty states ("Start a side chat", "No archived chats").
      css('.hermuse-sidebar-empty').styles(
        flex: .grow(1),
        display: .flex,
        flexDirection: .column,
        justifyContent: .center,
        alignItems: .center,
        gap: .all(4.px),
        padding: .symmetric(horizontal: 24.px),
        color: .variable('--content-muted'),
        textAlign: .center,
      ),
      css('.hermuse-sidebar-empty-text').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        gap: .all(2.px),
        color: .variable('--content'),
      ),
      css('.hermuse-sidebar-empty-title').styles(
        margin: .zero,
        fontSize: 15.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-sidebar-empty-body')
          .styles(margin: .zero, fontSize: 13.px, lineHeight: 18.px),
      css('.hermuse-sidebar-empty-action').styles(margin: .only(top: 12.px)),
      // 12 px under the illustration, with the column's 4 px gap.
      css('.hermuse-sidebar-empty-art').styles(
        display: .inlineFlex,
        margin: .only(bottom: (YsSpace.md - YsSpace.xs).px),
      ),
      css('.hermuse-sidebar-section-empty').styles(
        padding: .symmetric(vertical: 12.px, horizontal: 12.px),
        textAlign: .center,
      ),
      css('.hermuse-sidebar-list').styles(
        flex: .grow(1),
        display: .flex,
        flexDirection: .column,
        gap: .all(1.px),
        overflow: .only(y: .auto, x: .hidden),
        raw: {'min-height': '0'},
      ),
      // Rows (Main chat, side chats, archived chats).
      css('.hermuse-sidebar-row').styles(
        height: 36.px,
        padding: .only(right: 4.px),
        radius: .circular(YsRadius.navRow.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        color: .variable('--content'),
        raw: {'flex-shrink': '0'},
      ),
      css(
        // `&` on every part: jaspr only prefixes the first one otherwise.
        '& .hermuse-sidebar-row:hover, & .hermuse-sidebar-row-selected, '
        '& .hermuse-sidebar-row-active',
      ).styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-sidebar-row-main').styles(
        height: 100.percent,
        padding: .only(left: 8.px),
        radius: .circular(YsRadius.navRow.px),
        flex: .grow(1),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        color: .inherit,
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        textAlign: .left,
        raw: {'min-width': '0', 'outline': 'none'},
      ),
      css(
        '& .hermuse-sidebar-row-main:focus-visible, '
        '& .hermuse-sidebar-result:focus-visible',
      ).styles(raw: {'box-shadow': 'inset 0 0 0 2px var(--primary-ink)'}),
      css('.hermuse-sidebar-row-pin').styles(
        display: .inlineFlex,
        color: .variable('--content-muted'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-sidebar-row-title').styles(
        padding: .symmetric(horizontal: 4.px),
        flex: .grow(1),
        overflow: .hidden,
        textOverflow: .ellipsis,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w400,
        raw: {'white-space': 'nowrap', 'min-width': '0'},
      ),
      css('.hermuse-sidebar-row-time').styles(
        display: .none,
        padding: .symmetric(horizontal: 4.px),
        color: .variable('--content-muted'),
        fontSize: 12.px,
        lineHeight: 16.px,
        raw: {'flex-shrink': '0', 'white-space': 'nowrap'},
      ),
      // "…" stays focusable while hidden (zero width, not display:none) so
      // focus can return to it after its menu or dialog closes.
      css('.hermuse-sidebar-row-more').styles(
        width: 0.px,
        display: .inlineFlex,
        overflow: .hidden,
        raw: {'flex-shrink': '0'},
      ),
      css(
        '& .hermuse-sidebar-row:hover .hermuse-sidebar-row-time, '
        '& .hermuse-sidebar-row:focus-within .hermuse-sidebar-row-time, '
        '& .hermuse-sidebar-row-active .hermuse-sidebar-row-time, '
        '& .hermuse-sidebar-row-archived .hermuse-sidebar-row-time',
      ).styles(display: .block),
      css(
        '& .hermuse-sidebar-row:hover .hermuse-sidebar-row-more, '
        '& .hermuse-sidebar-row:focus-within .hermuse-sidebar-row-more, '
        '& .hermuse-sidebar-row-active .hermuse-sidebar-row-more, '
        '& .hermuse-sidebar-row-archived .hermuse-sidebar-row-more',
      ).styles(width: 24.px, overflow: .visible),
      // Inline rename: the row turns into a field with × and ✓.
      css('.hermuse-sidebar-row-rename').styles(
        padding: .only(left: 8.px, right: 4.px),
        gap: .all(2.px),
        backgroundColor: .variable('--neutral-film'),
        raw: {'box-shadow': 'inset 0 0 0 ${ysHairline}px var(--line)'},
      ),
      css('.hermuse-sidebar-rename-field').styles(
        padding: .symmetric(horizontal: 4.px),
        flex: .grow(1),
        display: .flex,
        raw: {'min-width': '0'},
      ),
      css('.hermuse-sidebar-rename-field .ys-textfield')
          .styles(fontSize: 14.px, lineHeight: 20.px, raw: {'min-width': '0'}),
      // "Side chats" section: collapsible (grid rows) with a "+".
      css('.hermuse-sidebar-section').styles(
        padding: .only(right: 4.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        justifyContent: .spaceBetween,
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-sidebar-section-toggle').styles(
        height: 36.px,
        padding: .symmetric(horizontal: 10.px),
        radius: .circular(YsRadius.pill.px),
        display: .inlineFlex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(2.px),
        color: .variable('--content-muted'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-sidebar-section-toggle:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-sidebar-section-toggle:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.hermuse-sidebar-section-chevron').styles(
        display: .inlineFlex,
        color: .variable('--content-subtle'),
        opacity: 0,
        raw: {'transition': 'opacity ${YsMotion.fast}ms ease'},
      ),
      css(
        '& .hermuse-sidebar-section-toggle:hover .hermuse-sidebar-section-chevron, '
        '& .hermuse-sidebar-section-toggle:focus-visible .hermuse-sidebar-section-chevron',
      ).styles(opacity: 1),
      css('.hermuse-sidebar-section-body').styles(
        display: .grid,
        raw: {
          'flex-shrink': '0',
          'grid-template-rows': '1fr',
          'transition':
              'grid-template-rows ${YsMotion.base}ms ${YsEase.standard.css}',
        },
      ),
      css('.hermuse-sidebar-section-collapsed')
          .styles(raw: {'grid-template-rows': '0fr'}),
      css('.hermuse-sidebar-section-rows').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(1.px),
        overflow: .hidden,
        raw: {'min-height': '0'},
      ),
      // Archived view.
      css('.hermuse-sidebar-archive-head').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        margin: .only(bottom: 8.px),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-sidebar-back').styles(display: .inlineFlex),
      css('.hermuse-sidebar-back .ys-btn-icon').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--paper-clear'),
        raw: {'box-shadow': 'var(--raised)'},
      ),
      css('.hermuse-sidebar-back .ys-btn-icon:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-sidebar-archive-title').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      // Search results.
      css('.hermuse-sidebar-result').styles(
        width: 100.percent,
        padding: .symmetric(vertical: 8.px, horizontal: 8.px),
        radius: .circular(YsRadius.navRow.px),
        display: .flex,
        flexDirection: .column,
        alignItems: .start,
        gap: .all(2.px),
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        textAlign: .left,
        raw: {'flex-shrink': '0', 'outline': 'none'},
      ),
      css('.hermuse-sidebar-result:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-sidebar-result-text').styles(
        width: 100.percent,
        overflow: .hidden,
        fontSize: 14.px,
        lineHeight: 20.px,
        raw: {
          'display': '-webkit-box',
          '-webkit-line-clamp': '2',
          '-webkit-box-orient': 'vertical',
          'overflow-wrap': 'anywhere',
        },
      ),
      css('.hermuse-sidebar-result-meta').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .row,
        gap: .all(6.px),
        color: .variable('--content-muted'),
        fontSize: 12.px,
        lineHeight: 16.px,
      ),
      css('.hermuse-sidebar-result-thread').styles(
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap', 'min-width': '0'},
      ),
      css('.hermuse-sidebar-result-time').styles(raw: {'flex-shrink': '0'}),
      css('.hermuse-sidebar-noresults').styles(
        margin: .zero,
        padding: .only(top: 24.px),
        textAlign: .center,
        color: .variable('--content-muted'),
        fontSize: 13.px,
        lineHeight: 18.px,
      ),
      // Failed action notice.
      css('.hermuse-sidebar-notice').styles(
        margin: .only(top: 8.px),
        padding: .only(left: 12.px, right: 6.px, top: 6.px, bottom: 6.px),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        color: .variable('--content'),
        backgroundColor: .variable('--paper-clear'),
        fontSize: 13.px,
        lineHeight: 18.px,
        raw: {'flex-shrink': '0', 'box-shadow': 'var(--raised)'},
      ),
      css('.hermuse-sidebar-notice-text')
          .styles(flex: .grow(1), raw: {'overflow-wrap': 'anywhere'}),
      // Resize handle straddling the right border.
      css('.hermuse-sidebar-resize').styles(
        position: .absolute(top: 0.px, bottom: 0.px, right: (-4).px),
        width: 8.px,
        raw: {
          'cursor': 'col-resize',
          'touch-action': 'none',
          'z-index': '5',
          'outline': 'none',
        },
      ),
      css('.hermuse-sidebar-resize::after').styles(
        position: .absolute(top: 0.px, bottom: 0.px, left: 3.px),
        width: 2.px,
        backgroundColor: Colors.transparent,
        raw: {
          'content': '""',
          'transition': 'background-color ${YsMotion.fast}ms ease',
        },
      ),
      css(
        '& .hermuse-sidebar-resize:hover::after, '
        '& .hermuse-sidebar-resize-active::after',
      ).styles(backgroundColor: .variable('--line')),
      css('.hermuse-sidebar-resize:focus-visible::after')
          .styles(backgroundColor: .variable('--primary')),
      // The delete confirmation covers the viewport, not only the panel.
      css('.ys-dialog-root').styles(
        position: .fixed(top: 0.px, left: 0.px),
      ),
      css('.hermuse-sidebar-dialog-body').styles(
        margin: .zero,
        fontSize: 15.px,
        lineHeight: 22.px,
        color: .variable('--content-muted'),
      ),
    ]),
    // The compact drawer has a fixed width.
    css.media(MediaQuery.screen(maxWidth: 767.px), [
      css('.hermuse-sidebar .hermuse-sidebar-resize').styles(display: .none),
    ]),
  ];
}

/// A menu open in the panel: "Side chat options", or a row's actions.
final class _OpenMenu {
  const _OpenMenu(this.anchor, {this.threadId, this.archived = false});

  final YsMenuAnchor anchor;

  /// Row whose actions show; null for "Side chat options".
  final String? threadId;
  final bool archived;
}

class _HermuseSidebarState extends State<HermuseSidebar> {
  static const _searchDelay = Duration(milliseconds: 150);
  static const _resizeStep = 16.0;
  static const _optionsKey = 'options';
  static const _sectionId = 'hermuse-side-chat-rows';

  var _archiveOpen = false;
  var _collapsed = false;
  var _query = '';
  Timer? _searchTimer;
  var _searchSeq = 0;
  List<ChatSearchHit>? _hits;
  _OpenMenu? _menu;
  String? _renamingId;
  var _renameDraft = '';
  String? _deletingId;
  String? _error;
  double? _dragStartX;
  var _dragStartWidth = ChatPanelPrefs.defaultWidth;
  Timer? _clock;

  /// Rows (`side:<id>`, `archived:<id>`) and the options button, to anchor
  /// menus and return focus.
  final _anchors = <String, GlobalNodeKey<web.HTMLElement>>{};
  final _searchBox = GlobalNodeKey<web.HTMLElement>();
  final _renameBox = GlobalNodeKey<web.HTMLElement>();
  final _backButton = GlobalNodeKey<web.HTMLElement>();

  ChatController get _chat => component.controller;

  ChatPanel get _panel =>
      HermuseScope.container.read(chatPanelProvider.notifier);

  double get _width =>
      HermuseScope.container.read(chatPanelProvider).value?.width ??
      ChatPanelPrefs.defaultWidth;

  GlobalNodeKey<web.HTMLElement> _anchor(String key) =>
      _anchors.putIfAbsent(key, GlobalNodeKey<web.HTMLElement>.new);

  /// The main chat as the side chat index knows it ('' until it exists).
  ThreadRef get _main {
    final id = _chat.state.mainThread.id;
    return ThreadRef(
      instanceId: _chat.instanceId,
      profile: _chat.profile,
      sessionId: id.startsWith('draft-') ? '' : id,
    );
  }

  @override
  void initState() {
    super.initState();
    // Keeps the time-ago captions current.
    if (kIsWeb) {
      _clock = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final main = _main;
    return HermuseWatch(
      provider: chatPanelProvider,
      builder: (context, panel) => HermuseWatch(
        provider: sideChatsProvider(main),
        builder: (context, rows) => HermuseWatch(
          provider: sideChatsProvider(main, archived: true),
          builder: (context, archived) => HermuseWatch(
            provider: mainChatUpdatedAtProvider(main),
            builder: (context, mainUpdated) => _body(
              panel.value ?? const ChatPanelPrefs(),
              rows.value,
              archived.value,
              mainUpdated.value,
            ),
          ),
        ),
      ),
    );
  }

  Component _body(
    ChatPanelPrefs prefs,
    List<SessionRow>? rows,
    List<SessionRow>? archived,
    DateTime? mainUpdated,
  ) {
    final now = DateTime.now();
    final entries = rows == null ? null : sideChatEntries(_chat.state, rows);
    return nav(
      classes: 'hermuse-sidebar',
      styles: Styles(raw: {'--hermuse-chats-width': '${prefs.width}px'}),
      attributes: {'aria-label': 'Side chats'},
      [
        if (_archiveOpen)
          ..._archive(archived, now)
        else ...[
          _top(),
          _content(entries, archived, mainUpdated, now),
        ],
        if (_error case final error?) _notice(error),
        _resizeHandle(prefs.width),
        if (_menu case final menu?)
          _menuOf(menu, prefs, entries ?? const [], archived ?? const []),
        if (_deletingId case final id?) _confirmDelete(id),
      ],
    );
  }

  Component _content(
    List<SideChatEntry>? entries,
    List<SessionRow>? archived,
    DateTime? mainUpdated,
    DateTime now,
  ) {
    if (_query.trim().isNotEmpty) return _results(now);
    // Nothing until both lists are read: no empty state flash.
    if (entries == null || archived == null) {
      return div(classes: 'hermuse-sidebar-list', []);
    }
    if (entries.isEmpty && archived.isEmpty) return _start();
    return _list(entries, mainUpdated, now);
  }

  // ------------------------------------------------------------------ top bar

  Component _top() {
    final optionsOpen = _menu != null && _menu!.threadId == null;
    return div(classes: 'hermuse-sidebar-top', [
      div(
        key: _searchBox,
        classes: 'hermuse-sidebar-search',
        attributes: {'role': 'search'},
        [
          YsIconView(YsIcon.search, size: 18),
          YsTextField(
            value: _query,
            onChanged: _onQuery,
            onEscape: _query.isEmpty ? null : _clearSearch,
            placeholder: 'Search',
            name: 'search',
          ),
          if (_query.isNotEmpty)
            YsButton.icon(
              icon: YsIcon.close,
              label: 'Clear search',
              onPressed: _clearSearch,
              size: 24,
              iconSize: 16,
            ),
        ],
      ),
      span(key: _anchor(_optionsKey), classes: 'hermuse-sidebar-options', [
        YsButton.icon(
          icon: YsIcon.more,
          label: 'Side chat options',
          onPressed: () => _openMenu(null),
          size: 24,
          iconSize: 15,
          attributes: {
            'aria-haspopup': 'menu',
            'aria-expanded': '$optionsOpen',
          },
        ),
      ]),
    ]);
  }

  void _onQuery(String value) {
    _searchTimer?.cancel();
    final empty = value.trim().isEmpty;
    if (empty) _searchSeq++;
    setState(() {
      _query = value;
      if (empty) _hits = null;
    });
    if (!empty) {
      _searchTimer = Timer(_searchDelay, () => unawaited(_search(value)));
    }
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    try {
      final hits = await chatSearch(
        HermuseScope.container.read(hermuseDatabaseProvider),
        _chat,
        query,
      );
      if (mounted && seq == _searchSeq) setState(() => _hits = hits);
    } on Object catch (e) {
      if (mounted && seq == _searchSeq) {
        setState(() {
          _hits = const [];
          _error = 'Search failed: ${_describe(e)}';
        });
      }
    }
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchSeq++;
    setState(() {
      _query = '';
      _hits = null;
    });
    _focusIn(_searchBox, 'input');
  }

  // -------------------------------------------------------------------- lists

  Component _start() => div(classes: 'hermuse-sidebar-empty', [
    YsHover(
      builder: (context, hovered) => span(
        classes: 'hermuse-sidebar-empty-art',
        [YsArtView(YsArt.chats, size: YsLayout.artCompact, active: hovered)],
      ),
    ),
    div(classes: 'hermuse-sidebar-empty-text', [
      h3(classes: 'hermuse-sidebar-empty-title', [.text('Start a side chat')]),
      p(classes: 'hermuse-sidebar-empty-body', [.text(_startBody)]),
      if (!component.readOnly)
        div(classes: 'hermuse-sidebar-empty-action', [
          YsButton.neutral(
            label: 'New side chat',
            onPressed: component.onNewSideChat,
          ),
        ]),
    ]),
  ]);

  static const _startBody =
      'Side chats are an optional way to organize your conversations by topic.';

  Component _list(
    List<SideChatEntry> entries,
    DateTime? mainUpdated,
    DateTime now,
  ) {
    final state = _chat.state;
    final mainId = state.mainThread.id;
    final mainSelected = state.activeThreadId == mainId;
    return div(classes: 'hermuse-sidebar-list', [
      div(
        key: const ValueKey('main-chat'),
        classes: mainSelected
            ? 'hermuse-sidebar-row hermuse-sidebar-row-selected'
            : 'hermuse-sidebar-row',
        [
          YsPressable(
            onPressed: () => component.onOpenThread(mainId),
            classes: 'hermuse-sidebar-row-main',
            attributes: {if (mainSelected) 'aria-current': 'true'},
            builder: (context, press) => .fragment([
              span(classes: 'hermuse-sidebar-row-title', [.text('Main chat')]),
              if (mainUpdated != null)
                span(classes: 'hermuse-sidebar-row-time', [
                  .text(formatTimeAgo(mainUpdated, now)),
                ]),
            ]),
          ),
        ],
      ),
      div(classes: 'hermuse-sidebar-section', [
        YsPressable(
          onPressed: () => setState(() => _collapsed = !_collapsed),
          classes: 'hermuse-sidebar-section-toggle',
          attributes: {
            'aria-expanded': '${!_collapsed}',
            'aria-controls': _sectionId,
          },
          builder: (context, press) => .fragment([
            span([.text('Side chats')]),
            span(classes: 'hermuse-sidebar-section-chevron', [
              YsIconView(
                _collapsed ? YsIcon.chevronRight : YsIcon.chevronDown,
                size: 20,
              ),
            ]),
          ]),
        ),
        if (!component.readOnly)
          YsButton.icon(
            icon: YsIcon.plus,
            label: 'New side chat',
            onPressed: component.onNewSideChat,
            size: 24,
            iconSize: 20,
          ),
      ]),
      div(
        id: _sectionId,
        classes: _collapsed
            ? 'hermuse-sidebar-section-body hermuse-sidebar-section-collapsed'
            : 'hermuse-sidebar-section-body',
        [
          div(
            classes: 'hermuse-sidebar-section-rows',
            // Collapsed rows leave the tab order and accessibility tree.
            attributes: {if (_collapsed) 'inert': ''},
            [
              if (entries.isEmpty)
                div(
                  classes: 'hermuse-sidebar-section-empty hermuse-sidebar-empty-text',
                  [
                    p(classes: 'hermuse-sidebar-empty-title', [
                      .text('Start a side chat'),
                    ]),
                    p(classes: 'hermuse-sidebar-empty-body', [
                      .text(_startBody),
                    ]),
                  ],
                )
              else
                for (final entry in entries)
                  entry.threadId == _renamingId
                      ? _renameRow(entry)
                      : _sideRow(entry, now),
            ],
          ),
        ],
      ),
    ]);
  }

  Component _sideRow(SideChatEntry entry, DateTime now) {
    final id = entry.threadId;
    final menu = _menu;
    final menuOpen = menu != null && menu.threadId == id && !menu.archived;
    final selected = _chat.state.activeThreadId == id;
    final updated = entry.updatedAt;
    return div(
      key: _anchor('side:$id'),
      classes: [
        'hermuse-sidebar-row',
        if (selected) 'hermuse-sidebar-row-selected',
        if (menuOpen || _deletingId == id) 'hermuse-sidebar-row-active',
      ].join(' '),
      events: {'contextmenu': (event) => _contextMenu(event, id)},
      [
        YsPressable(
          onPressed: () => component.onOpenThread(id),
          classes: 'hermuse-sidebar-row-main',
          attributes: {if (selected) 'aria-current': 'true'},
          builder: (context, press) => .fragment([
            if (entry.pinned)
              span(classes: 'hermuse-sidebar-row-pin', [
                YsIconView(YsIcon.pin, size: 16),
              ]),
            span(classes: 'hermuse-sidebar-row-title', [
              .text(sideChatTitle(entry.title)),
            ]),
            if (updated != null)
              span(classes: 'hermuse-sidebar-row-time', [
                .text(formatTimeAgo(updated, now)),
              ]),
          ]),
        ),
        span(classes: 'hermuse-sidebar-row-more', [
          YsButton.icon(
            icon: YsIcon.more,
            label: 'More thread actions',
            onPressed: () => _openMenu(id),
            size: 24,
            iconSize: 20,
            attributes: {'aria-haspopup': 'menu', 'aria-expanded': '$menuOpen'},
          ),
        ]),
      ],
    );
  }

  Component _renameRow(SideChatEntry entry) => div(
    key: _anchor('side:${entry.threadId}'),
    classes: 'hermuse-sidebar-row hermuse-sidebar-row-rename',
    [
      span(key: _renameBox, classes: 'hermuse-sidebar-rename-field', [
        YsTextField(
          value: _renameDraft,
          onChanged: (v) => setState(() => _renameDraft = v),
          onSubmitted: () => _confirmRename(entry),
          onEscape: () => _endRename(entry.threadId),
          label: 'Side chat name',
          name: 'rename',
        ),
      ]),
      YsButton.icon(
        icon: YsIcon.close,
        label: 'Cancel rename',
        onPressed: () => _endRename(entry.threadId),
        size: 24,
        iconSize: 16,
      ),
      YsButton.icon(
        icon: YsIcon.check,
        label: 'Save name',
        onPressed: () => _confirmRename(entry),
        size: 24,
        iconSize: 16,
      ),
    ],
  );

  // ------------------------------------------------------------------ archive

  List<Component> _archive(List<SessionRow>? rows, DateTime now) => [
    div(classes: 'hermuse-sidebar-archive-head', [
      span(key: _backButton, classes: 'hermuse-sidebar-back', [
        YsButton.icon(
          icon: YsIcon.chevronLeft,
          label: 'Back to chat list',
          onPressed: _closeArchive,
        ),
      ]),
      h2(classes: 'hermuse-sidebar-archive-title', [.text('Archived chats')]),
    ]),
    if (rows == null)
      div(classes: 'hermuse-sidebar-list', [])
    else if (rows.isEmpty)
      div(classes: 'hermuse-sidebar-empty', [
        div(classes: 'hermuse-sidebar-empty-text', [
          p(classes: 'hermuse-sidebar-empty-title', [
            .text('No archived chats'),
          ]),
          p(classes: 'hermuse-sidebar-empty-body', [
            .text('Side chats you archive will appear here.'),
          ]),
        ]),
      ])
    else
      div(classes: 'hermuse-sidebar-list', [
        for (final row in rows) _archivedRow(row, now),
      ]),
  ];

  /// An archived side chat: not open-able until restored, so the row itself
  /// opens its menu ("Restore from archive").
  Component _archivedRow(SessionRow row, DateTime now) {
    final id = row.sessionId;
    final menu = _menu;
    final menuOpen = menu != null && menu.threadId == id && menu.archived;
    return div(
      key: _anchor('archived:$id'),
      classes: menuOpen
          ? 'hermuse-sidebar-row hermuse-sidebar-row-archived hermuse-sidebar-row-active'
          : 'hermuse-sidebar-row hermuse-sidebar-row-archived',
      events: {
        'contextmenu': (event) => _contextMenu(event, id, archived: true),
      },
      [
        YsPressable(
          onPressed: component.readOnly
              ? null
              : () => _openMenu(id, archived: true),
          classes: 'hermuse-sidebar-row-main',
          attributes: {'aria-haspopup': 'menu', 'aria-expanded': '$menuOpen'},
          builder: (context, press) => .fragment([
            span(classes: 'hermuse-sidebar-row-title', [
              .text(sideChatTitle(row.title)),
            ]),
            span(classes: 'hermuse-sidebar-row-time', [
              .text(
                formatTimeAgo(
                  DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
                  now,
                ),
              ),
            ]),
          ]),
        ),
        if (!component.readOnly)
          span(classes: 'hermuse-sidebar-row-more', [
            YsButton.icon(
              icon: YsIcon.more,
              label: 'More thread actions',
              onPressed: () => _openMenu(id, archived: true),
              size: 24,
              iconSize: 20,
              attributes: {
                'aria-haspopup': 'menu',
                'aria-expanded': '$menuOpen',
              },
            ),
          ]),
      ],
    );
  }

  void _openArchive() {
    setState(() => _archiveOpen = true);
    _focusIn(_backButton, 'button');
  }

  void _closeArchive() {
    setState(() => _archiveOpen = false);
    _focusIn(_anchor(_optionsKey), 'button');
  }

  // ------------------------------------------------------------------ results

  Component _results(DateTime now) {
    final hits = _hits;
    if (hits == null) return div(classes: 'hermuse-sidebar-list', []);
    if (hits.isEmpty) {
      return p(classes: 'hermuse-sidebar-noresults', [.text('No results')]);
    }
    final query = _query.trim().toLowerCase();
    return div(classes: 'hermuse-sidebar-list', [
      for (final hit in hits)
        YsPressable(
          onPressed: () => component.onOpenThread(hit.threadId),
          classes: 'hermuse-sidebar-result',
          builder: (context, press) => .fragment([
            span(classes: 'hermuse-sidebar-result-text', [
              .text(_snippet(hit.text, query)),
            ]),
            span(classes: 'hermuse-sidebar-result-meta', [
              span(classes: 'hermuse-sidebar-result-thread', [
                .text(
                  hit.isTitle ? 'Side chat' : sideChatTitle(hit.threadTitle),
                ),
              ]),
              if (hit.updatedAt case final at?)
                span(classes: 'hermuse-sidebar-result-time', [
                  .text(formatTimeAgo(at, now)),
                ]),
            ]),
          ]),
        ),
    ]);
  }

  /// [text] on one line, starting shortly before the first query term so
  /// the match shows inside the two clamped lines.
  static String _snippet(String text, String query) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = flat.toLowerCase();
    var at = -1;
    for (final term in query.split(' ')) {
      if (term.isEmpty) continue;
      final found = lower.indexOf(term);
      if (found >= 0 && (at < 0 || found < at)) at = found;
    }
    if (at <= 40) return flat;
    final cut = flat.lastIndexOf(' ', at - 16);
    return '…${flat.substring(cut < 0 ? at : cut + 1)}';
  }

  // -------------------------------------------------------------------- menus

  /// Opens the options menu ([threadId] null) or a row's actions below its
  /// "…" button, or at [at] (context menu).
  void _openMenu(String? threadId, {bool archived = false, YsMenuAnchor? at}) {
    final anchor = at ?? _triggerOf(threadId, archived: archived);
    if (anchor == null) return;
    setState(
      () => _menu = _OpenMenu(anchor, threadId: threadId, archived: archived),
    );
  }

  YsMenuAnchor? _triggerOf(String? threadId, {required bool archived}) {
    if (threadId == null) {
      final options = _anchors[_optionsKey]?.currentNode;
      return options == null ? null : YsMenuAnchor.of(options);
    }
    final row = _anchors['${archived ? 'archived' : 'side'}:$threadId'];
    final more = row?.currentNode?.querySelector('.hermuse-sidebar-row-more');
    return more == null ? null : YsMenuAnchor.of(more);
  }

  void _contextMenu(web.Event event, String threadId, {bool archived = false}) {
    event.preventDefault();
    final mouse = event as web.MouseEvent;
    // Shift+F10 / the menu key carry no pointer position.
    final at = mouse.clientX == 0 && mouse.clientY == 0
        ? null
        : YsMenuAnchor.point(
            mouse.clientX.toDouble(),
            mouse.clientY.toDouble(),
          );
    _openMenu(threadId, archived: archived, at: at);
  }

  Component _menuOf(
    _OpenMenu menu,
    ChatPanelPrefs prefs,
    List<SideChatEntry> entries,
    List<SessionRow> archived,
  ) {
    void close() => setState(() => _menu = null);
    final id = menu.threadId;
    if (id == null) {
      return YsMenu(
        key: const ValueKey('menu:options'),
        label: 'Side chat options',
        anchor: menu.anchor,
        onClose: close,
        items: [
          YsMenuItem(
            label: 'Keep chat panel visible',
            checked: prefs.pinned,
            onSelected: () => component.onSetPinned(!prefs.pinned),
          ),
          YsMenuItem(
            label: 'Show archived chats',
            icon: YsIcon.archive,
            onSelected: _openArchive,
          ),
        ],
      );
    }
    if (menu.archived) {
      if (component.readOnly) return .fragment([]);
      final row = archived.where((r) => r.sessionId == id).firstOrNull;
      if (row == null) return .fragment([]);
      return YsMenu(
        key: ValueKey('menu:archived:$id'),
        label: 'More thread actions',
        anchor: menu.anchor,
        onClose: close,
        items: [
          YsMenuItem(
            label: 'Restore from archive',
            icon: YsIcon.archive,
            onSelected: () => _restore(row),
          ),
        ],
      );
    }
    final entry = entries.where((e) => e.threadId == id).firstOrNull;
    if (entry == null) return .fragment([]);
    return YsMenu(
      key: ValueKey('menu:side:$id'),
      label: 'More thread actions',
      anchor: menu.anchor,
      onClose: close,
      items: [
        // Pins are stored with the saved session: none for a draft.
        if (!id.startsWith('draft-'))
          YsMenuItem(
            label: entry.pinned ? 'Unpin' : 'Pin',
            icon: YsIcon.pin,
            onSelected: () => _pin(entry),
          ),
        if (!component.readOnly) ...[
          YsMenuItem(
            label: 'Rename',
            icon: YsIcon.pencil,
            onSelected: () => _startRename(entry),
          ),
          YsMenuItem(
            label: 'Archive',
            icon: YsIcon.archive,
            onSelected: () => _archiveThread(id),
          ),
          YsMenuItem(
            label: 'Delete',
            icon: YsIcon.trash,
            destructive: true,
            onSelected: () => setState(() => _deletingId = id),
          ),
        ],
      ],
    );
  }

  Component _confirmDelete(String id) => YsDialog(
    title: 'Delete side chat?',
    onClose: () => setState(() => _deletingId = null),
    actions: [
      YsButton.neutral(
        label: 'Cancel',
        onPressed: () => setState(() => _deletingId = null),
      ),
      YsButton.destructive(label: 'Delete', onPressed: () => _delete(id)),
    ],
    child: p(classes: 'hermuse-sidebar-dialog-body', [
      .text(
        'Deleting this side chat permanently removes it and cannot be undone.',
      ),
    ]),
  );

  // ------------------------------------------------------------------ actions

  /// Runs a thread action; a failure (server refusal, lost connection) shows
  /// in the panel notice.
  Future<void> _run(String action, Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not $action: ${_describe(e)}');
      }
    }
  }

  static String _describe(Object error) => switch (error) {
    HermesException(:final message) => message,
    StateError(:final message) => message,
    _ => '$error',
  };

  void _pin(SideChatEntry entry) => unawaited(
    _run(
      entry.pinned ? 'unpin this side chat' : 'pin this side chat',
      () => setSideChatPinned(
        HermuseScope.container.read(hermuseDatabaseProvider),
        ThreadRef(
          instanceId: _chat.instanceId,
          sessionId: entry.threadId,
          profile: _chat.profile,
        ),
        pinned: !entry.pinned,
      ),
    ),
  );

  void _startRename(SideChatEntry entry) {
    setState(() {
      _renamingId = entry.threadId;
      _renameDraft = sideChatTitle(entry.title);
    });
    _focusIn(_renameBox, 'input', select: true);
  }

  void _endRename(String id) {
    setState(() => _renamingId = null);
    _focusIn(_anchor('side:$id'), '.hermuse-sidebar-row-main');
  }

  void _confirmRename(SideChatEntry entry) {
    final title = _renameDraft.trim();
    _endRename(entry.threadId);
    if (title.isEmpty || title == entry.title) return;
    unawaited(
      _run(
        'rename this side chat',
        () => _chat.renameThread(entry.threadId, title),
      ),
    );
  }

  void _archiveThread(String id) =>
      unawaited(_run('archive this side chat', () => _chat.archiveThread(id)));

  void _delete(String id) {
    setState(() => _deletingId = null);
    unawaited(_run('delete this side chat', () => _chat.deleteThread(id)));
  }

  void _restore(SessionRow row) => unawaited(
    _run(
      'restore this side chat',
      () => _chat.restoreThread(row.sessionId, title: row.title),
    ),
  );

  Component _notice(String error) => div(
    classes: 'hermuse-sidebar-notice',
    attributes: {'role': 'alert'},
    [
      span(classes: 'hermuse-sidebar-notice-text', [.text(error)]),
      YsButton.icon(
        icon: YsIcon.close,
        label: 'Dismiss',
        onPressed: () => setState(() => _error = null),
        size: 24,
        iconSize: 16,
      ),
    ],
  );

  /// Focuses [selector] inside [key]'s element once the frame rendered.
  void _focusIn(
    GlobalNodeKey<web.HTMLElement> key,
    String selector, {
    bool select = false,
  }) {
    if (!kIsWeb) return;
    context.binding.addPostFrameCallback(() {
      final target = key.currentNode?.querySelector(selector);
      if (target == null) return;
      (target as web.HTMLElement).focus();
      if (select) (target as web.HTMLInputElement).select();
    });
  }

  // ------------------------------------------------------------------- resize

  Component _resizeHandle(double width) => div(
    classes: _dragStartX == null
        ? 'hermuse-sidebar-resize'
        : 'hermuse-sidebar-resize hermuse-sidebar-resize-active',
    attributes: {
      'role': 'separator',
      'aria-label': 'Resize panel',
      'aria-orientation': 'vertical',
      'aria-valuenow': '${width.round()}',
      'aria-valuemin': '${ChatPanelPrefs.minWidth.round()}',
      'aria-valuemax': '${ChatPanelPrefs.maxWidth.round()}',
      'tabindex': '0',
    },
    events: {
      'pointerdown': _dragStart,
      'pointermove': _dragMove,
      'pointerup': _dragEnd,
      'pointercancel': _dragEnd,
      'keydown': _resizeKey,
    },
    [],
  );

  void _dragStart(web.Event event) {
    final pointer = event as web.PointerEvent;
    if (pointer.button != 0) return;
    // No text selection or focus change while dragging.
    event.preventDefault();
    (event.currentTarget! as web.Element).setPointerCapture(pointer.pointerId);
    setState(() {
      _dragStartX = pointer.clientX.toDouble();
      _dragStartWidth = _width;
    });
  }

  void _dragMove(web.Event event) {
    final start = _dragStartX;
    if (start == null) return;
    final x = (event as web.PointerEvent).clientX.toDouble();
    _panel.setWidth(_dragStartWidth + x - start);
  }

  void _dragEnd(web.Event event) {
    if (_dragStartX == null) return;
    setState(() => _dragStartX = null);
    unawaited(_panel.saveWidth());
  }

  void _resizeKey(web.Event event) {
    final width = switch ((event as web.KeyboardEvent).key) {
      'ArrowLeft' => _width - _resizeStep,
      'ArrowRight' => _width + _resizeStep,
      'Home' => ChatPanelPrefs.minWidth,
      'End' => ChatPanelPrefs.maxWidth,
      _ => null,
    };
    if (width == null) return;
    event.preventDefault();
    _panel.setWidth(width);
    unawaited(_panel.saveWidth());
  }
}
