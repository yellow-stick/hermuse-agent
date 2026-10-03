import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'add_instance.dart';
import 'agents.dart';
import 'components.dart';
import 'computer_viewer.dart';
import 'connections.dart';
import 'feed.dart';
import 'goals.dart';
import 'ideas.dart';
import 'instances.dart';
import 'library.dart';
import 'onboarding.dart';
import 'panel.dart';
import 'rail.dart';
import 'scope.dart';
import 'screens.dart';
import 'sidebar.dart';
import 'settings.dart';
import 'thread.dart';

/// The chat root: routes relay/instances/chat screens and owns the shell.
///
/// Pre-rendered on the server (SSR HTML contains the loading shell; no
/// network happens during pre-rendering) and hydrated in the browser, where
/// the [HermuseScope] database boots and the real screens take over.
@client
class HermuseChatRoot extends StatefulComponent {
  const HermuseChatRoot({super.key});

  @override
  State<HermuseChatRoot> createState() => _HermuseChatRootState();
}

/// Which full-screen surface is on top of the chat shell.
enum _Overlay {
  none,
  addInstance,
  instances,
  settings,
  onboarding,
  connections,
  components,
}

/// Width of the side-by-side chat column on product routes.
const _splitChatWidth = 564.0;

/// Narrowest viewport showing the side-by-side chat: the rail and the chat
/// column still leave the route a usable width.
const _splitMinViewport = 1024.0;

class _HermuseChatRootState extends State<HermuseChatRoot>
    with ChatListenerMixin {
  /// Viewport width; null during pre-rendering, where the wide shell is drawn.
  double? _width;

  /// User choice for the panel/chats panel; null follows the shell default.
  /// Cleared whenever the shell changes, so a panel opened full-screen on a
  /// phone-sized window does not stay over the thread after a resize.
  bool? _panelOverride;
  bool? _sidebarOverride;
  var _tab = PanelTab.activity;
  var _destination = HermuseDestination.chat;

  /// Side-by-side chat on product routes; remembered while the app runs.
  var _split = false;
  var _draft = '';
  var _customAnswer = '';
  var _overlay = _Overlay.none;

  /// Where a cancelled "Add a Hermes" goes back to: the instances it was
  /// opened from, else the chat.
  var _addReturn = _Overlay.none;
  String? _onboardingInstanceId;
  String? _agentEditorInstanceId;
  AgentProfile? _editingAgent;
  String? _copiedId;
  Timer? _copiedTimer;
  StreamSubscription<web.Event>? _keySub;
  StreamSubscription<web.Event>? _resizeSub;
  web.HTMLElement? _settingsOpener;

  /// The chat on screen. Switching instances keeps it (rail, panel, thread
  /// DOM all stay) until the next chat's transcript is loaded, then only the
  /// thread content changes: no blank shell in between.
  ChatController? _shown;
  HermesInstance? _shownInstance;
  ChatController? _awaited;

  /// Thread on screen and whether it had messages (see [_followThread]).
  String? _followed;

  YsShell get _shellKind => YsShell.forWidth(_width ?? YsLayout.wideMin);
  bool get _panelOpen => _panelOverride ?? _shellKind == YsShell.wide;

  /// The chats panel: the user's choice, else docked when "Keep chat panel
  /// visible" is on (wide shell; the compact drawer starts closed).
  bool _chatsOpen({required bool pinned}) =>
      _sidebarOverride ?? (pinned && _shellKind == YsShell.wide);

  bool get _splitFits => (_width ?? 0) >= _splitMinViewport;

  void _openSettings() {
    if (kIsWeb) {
      _settingsOpener = web.document.activeElement as web.HTMLElement?;
    }
    setState(() => _overlay = _Overlay.settings);
  }

  void _closeSettings() {
    setState(() => _overlay = _Overlay.none);
    if (kIsWeb) {
      context.binding.addPostFrameCallback(() {
        if (mounted && (_settingsOpener?.isConnected ?? false)) {
          _settingsOpener?.focus();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // SSR renders the wide shell (both open); the real width then picks
      // the defaults, and resizes keep following them.
      _width = web.window.innerWidth.toDouble();
      _resizeSub = web.EventStreamProviders.resizeEvent
          .forTarget(web.window)
          .listen((_) {
            final width = web.window.innerWidth.toDouble();
            final shellChanged = YsShell.forWidth(width) != _shellKind;
            setState(() {
              _width = width;
              if (shellChanged) _panelOverride = _sidebarOverride = null;
            });
          });
      _keySub = web.EventStreamProviders.keyDownEvent
          .forTarget(web.window)
          .listen((event) {
            if (event.key == 'Escape') {
              if (_overlay == _Overlay.settings) {
                _closeSettings();
                return;
              }
              setState(() {
                if (_overlay != _Overlay.none) {
                  _overlay = _Overlay.none;
                } else {
                  _panelOverride = false;
                }
              });
            }
          });
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _resizeSub?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!kIsWeb) return;
    // After the frame renders the new message, pin the log to the bottom.
    Timer.run(() {
      final scroller = web.document.querySelector('.hermuse-thread-scroll');
      if (scroller != null) scroller.scrollTop = scroller.scrollHeight;
    });
  }

  void _copy(String id, String text) {
    if (kIsWeb) {
      web.window.navigator.clipboard.writeText(text);
    }
    setState(() => _copiedId = id);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copiedId = null);
    });
  }

  void _send(ChatController controller) {
    if (_draft.trim().isEmpty) return;
    unawaited(controller.send(_draft));
    setState(() => _draft = '');
  }

  Future<void> _openInstance(String instanceId) => context
      .readProvider(activeThreadProvider.notifier)
      .openInstance(instanceId);

  Future<void> _openSetup(ThreadRef setup) =>
      context.readProvider(activeThreadProvider.notifier).openSetup(setup);

  void _editAgent(String instanceId, [AgentProfile? agent]) => setState(() {
    _agentEditorInstanceId = instanceId;
    _editingAgent = agent;
  });

  /// "Add a Hermes"; cancelling it goes back to [from].
  void _addInstance([_Overlay from = _Overlay.none]) => setState(() {
    _addReturn = from;
    _overlay = _Overlay.addInstance;
  });

  /// After adding an instance: its component checklist, what Hermuse needs
  /// on it; Continue then opens its chat, or its onboarding until a model
  /// answers.
  Future<void> _afterAdd(String instanceId) {
    setState(() {
      _overlay = _Overlay.components;
      _onboardingInstanceId = instanceId;
    });
    return _openInstance(instanceId);
  }

  /// Discuss / Start in chat: [seed] lands in the main chat's composer
  /// (quoted, never a new side chat). An open side-by-side chat receives it
  /// without leaving the route.
  void _discussSeed(ChatController controller, String seed) {
    controller.openThread(controller.state.mainThread.id);
    setState(() {
      if (!(_split && _splitFits)) _destination = HermuseDestination.chat;
      _draft = seed;
    });
  }

  /// Opens [threadId]; the chats panel then closes unless "Keep chat panel
  /// visible" docks it (the compact drawer always closes).
  void _pickThread(
    ChatController controller,
    String threadId, {
    required bool pinned,
  }) {
    if (controller.state.threads.any((t) => t.id == threadId)) {
      controller.openThread(threadId);
    }
    _afterPick(pinned: pinned);
  }

  void _newSideChat(ChatController controller, {required bool pinned}) {
    controller.newSideChat();
    _afterPick(pinned: pinned);
    if (!kIsWeb) return;
    Timer.run(() {
      final composer = web.document.querySelector('.hermuse-composer textarea');
      if (composer != null) (composer as web.HTMLElement).focus();
    });
  }

  void _afterPick({required bool pinned}) {
    if (!pinned || _shellKind != YsShell.wide) {
      setState(() => _sidebarOverride = false);
    }
  }

  /// Scrolls the log to the bottom when another thread shows or when the
  /// shown thread's transcript arrives.
  void _followThread(ChatState state) {
    final shown =
        '${state.activeThreadId}:${state.activeThread.messages.isEmpty}';
    if (shown == _followed) return;
    _followed = shown;
    _scrollToBottom();
  }

  @override
  Component build(BuildContext context) {
    // SSR, the first client frames and the database boot render the static
    // shell with its wait: the pre-rendered page stays as it is.
    if (!kIsWeb) return _loadingShell();
    return HermuseScope(
      loading: _loadingShell(),
      child: HermuseWatch(
        provider: appThemeProvider,
        builder: (context, theme) {
          final mode = theme.value ?? YsThemeMode.dark;
          web.document.documentElement?.setAttribute('data-theme', mode.name);
          // The demo answers every call in the browser: no relay to find.
          return hermuseDemo
              ? _instancesRoute()
              : HermuseWatch(
                  provider: relayProvider,
                  builder: (context, detected) {
                    if (!detected.hasValue) return _loadingShell();
                    if (detected.value == null) {
                      return _loadingShell(child: HermuseRelayRequired());
                    }
                    return _instancesRoute();
                  },
                );
        },
      ),
    );
  }

  Component _instancesRoute() => HermuseWatch(
    provider: instancesProvider,
    builder: (context, instances) => HermuseWatch(
      provider: activeThreadProvider,
      builder: (context, active) => .fragment([
        div(
          styles: Styles(
            display: _overlay == _Overlay.settings ? .none : .contents,
          ),
          [_route(context, instances, active)],
        ),
        if (_overlay == _Overlay.settings)
          _loadingShell(child: HermuseSettings(onBack: _closeSettings)),
      ]),
    ),
  );

  Component _route(
    BuildContext context,
    AsyncValue<List<HermesInstance>> instancesValue,
    AsyncValue<ThreadRef?> activeValue,
  ) {
    final instances = instancesValue.value;
    if (instances == null) return _loadingShell();
    if (_overlay == _Overlay.addInstance) {
      return _loadingShell(
        child: HermuseAddInstance(
          onDone: (instanceId) => unawaited(_afterAdd(instanceId)),
          onCancel: () => setState(() => _overlay = _addReturn),
        ),
      );
    }
    if (_overlay == _Overlay.instances && instances.isNotEmpty) {
      return _loadingShell(
        child: HermuseInstances(
          onAdd: () => _addInstance(_Overlay.instances),
          onBack: () => setState(() => _overlay = _Overlay.none),
          onOpen: (id) {
            setState(() => _overlay = _Overlay.none);
            unawaited(_openInstance(id));
          },
          onSetup: (id) => setState(() {
            _overlay = _Overlay.onboarding;
            _onboardingInstanceId = id;
          }),
          onComponents: (id) => setState(() {
            _overlay = _Overlay.components;
            _onboardingInstanceId = id;
          }),
          onConnections: (id) => setState(() {
            _overlay = _Overlay.connections;
            _onboardingInstanceId = id;
          }),
        ),
      );
    }
    final overlayId = _onboardingInstanceId;
    if (_overlay == _Overlay.onboarding &&
        overlayId != null &&
        instances.any((candidate) => candidate.id == overlayId)) {
      final instance = instances.firstWhere(
        (candidate) => candidate.id == overlayId,
      );
      return _loadingShell(
        child: HermuseOnboarding(
          instance: instance,
          onDone: (setup) {
            setState(() {
              _overlay = _Overlay.none;
              _onboardingInstanceId = null;
            });
            unawaited(
              setup == null ? _openInstance(instance.id) : _openSetup(setup),
            );
          },
          onSkipToChat: () => setState(() {
            _overlay = _Overlay.none;
            _onboardingInstanceId = null;
          }),
        ),
      );
    }
    if (_overlay == _Overlay.connections &&
        overlayId != null &&
        instances.any((candidate) => candidate.id == overlayId)) {
      final instance = instances.firstWhere(
        (candidate) => candidate.id == overlayId,
      );
      return _loadingShell(
        child: HermuseConnections(
          instance: instance,
          // Opened from its instance row: back to the instances.
          onBack: () => setState(() {
            _overlay = _Overlay.instances;
            _onboardingInstanceId = null;
          }),
        ),
      );
    }
    if (_overlay == _Overlay.components &&
        overlayId != null &&
        instances.any((candidate) => candidate.id == overlayId)) {
      final instance = instances.firstWhere(
        (candidate) => candidate.id == overlayId,
      );
      return _loadingShell(
        child: HermuseComponents(
          instance: instance,
          onChat: () {
            setState(() {
              _overlay = _Overlay.none;
              _onboardingInstanceId = null;
            });
            unawaited(_openInstance(instance.id));
          },
          onSetUpModel: () => setState(() => _overlay = _Overlay.onboarding),
        ),
      );
    }
    if (instances.isEmpty) {
      return _loadingShell(child: HermuseWelcome(onAdd: _addInstance));
    }
    final active = activeValue.value;
    final thread =
        active ??
        ThreadRef(instanceId: _primaryOrFirst(instances).id, sessionId: '');
    final instance = instances
        .where((candidate) => candidate.id == thread.instanceId)
        .firstOrNull;
    if (instance == null) {
      return _loadingShell(child: HermuseWelcome(onAdd: _addInstance));
    }
    return HermuseWatch(
      provider: chatSessionProvider(thread),
      builder: (context, session) {
        final next = session.value;
        final previous = _shown;
        if (next != null && (next.isReady || previous == null)) {
          if (!identical(previous, next)) {
            _shown = next;
            _shownInstance = instance;
            _draft = '';
            _customAnswer = '';
            _scrollToBottom();
          }
        } else if (next != null && !identical(_awaited, next)) {
          _awaited = next;
          unawaited(
            next.ready.whenComplete(() {
              if (mounted) setState(() {});
            }),
          );
        }
        final controller = _shown;
        if (controller == null) return _loadingShell(label: 'Opening the chat');
        syncChatListener(controller);
        return HermuseWatch(
          provider: chatPanelPinnedProvider,
          builder: (context, pinned) => HermuseWatch(
            provider: agentProfilesProvider(controller.instanceId),
            builder: (context, agents) => _chatShell(
              context,
              instances: instances,
              instance: _shownInstance ?? instance,
              controller: controller,
              agent: agents.value
                  ?.where((agent) => agent.profile == controller.profile)
                  .firstOrNull,
              switching: !identical(controller, next),
              pinned: pinned,
            ),
          ),
        );
      },
    );
  }

  HermesInstance _primaryOrFirst(List<HermesInstance> instances) {
    final registry = context.readProvider(registryProvider).value;
    final primary = registry?.primary;
    if (primary != null &&
        instances.any((candidate) => candidate.id == primary.id)) {
      return primary;
    }
    return instances.first;
  }

  /// Static shell (SSR + loading states): the drawing of a wait, [label]
  /// announced, or [child] in its place, so hydration matches.
  Component _loadingShell({Component? child, String label = 'Loading'}) =>
      div(classes: 'hermuse-shell', [
        div(classes: 'hermuse-nojs-note', [.text('Loading interactive chat…')]),
        child ?? HermuseLoading(art: YsArt.chats, label: label),
      ]);

  Component _chatShell(
    BuildContext context, {
    required List<HermesInstance> instances,
    required HermesInstance instance,
    required ChatController controller,
    required bool switching,
    required bool pinned,
    required AgentProfile? agent,
  }) {
    final state = controller.state;
    final activeThread = state.activeThread;
    final replyTo = state.replyTo;
    final onChat = _destination == HermuseDestination.chat;
    // Product routes can dock the chat beside them (wide viewports only).
    final split = !onChat && _split && _splitFits;
    final chatsOpen = _chatsOpen(pinned: pinned) && (onChat || split);
    // Side by side, the route keeps the rest: no profile panel.
    final profileOpen = _panelOpen && !split;
    final agentName = agent?.displayName ?? state.agentName;
    final avatarId = agent?.avatarId ?? 'hermuse';
    _followThread(state);

    Component agentPicker({String? subtitle}) => HermuseAgentPicker(
      key: ValueKey('agent:${instance.id}:${controller.profile}'),
      instanceId: instance.id,
      profile: controller.profile,
      chat: state,
      subtitle: subtitle,
      disabled: switching,
      readOnly: hermuseDemo,
      onCreate: () => _editAgent(instance.id),
      onEdit: (agent) => _editAgent(instance.id, agent),
    );
    // Phone top bar: a side chat on screen gets back to the main chat.
    final sideChat = onChat && activeThread.id != state.mainThread.id;

    Component header() => HermuseThreadHeader(
      state: state,
      panelOpen: chatsOpen,
      onOpenPanel: () => setState(() => _sidebarOverride = true),
      onBackToMain: () => controller.openThread(state.mainThread.id),
      agentPicker: agentPicker(),
    );

    Component thread() => HermuseThread(
      key: ValueKey('thread:${instance.id}:${controller.profile}'),
      readOnly: hermuseDemo,
      switching: switching,
      thread: activeThread,
      instanceId: instance.id,
      controller: controller,
      connection: state.connection,
      connectionError: state.connectionError,
      needsSignIn: state.needsSignIn,
      onRetry: controller.retry,
      busy: state.busy,
      onInterrupt: controller.interrupt,
      selectedOffers: state.selectedOffers,
      onToggleReaction: (id) => controller.toggleReaction(id, '👍'),
      onReply: hermuseDemo ? null : controller.startReply,
      onCopy: (id) => _copy(
        id,
        activeThread.messages.firstWhere((m) => m.id == id).plainText,
      ),
      copiedId: _copiedId,
      onChoose: (id, answer, blockIndex) =>
          controller.choose(id, answer, blockIndex: blockIndex),
      onSelectOffer: controller.selectOffer,
      customAnswer: _customAnswer,
      onCustomAnswer: (v) => setState(() => _customAnswer = v),
      draft: _draft,
      onDraft: (v) => setState(() => _draft = v),
      onSend: () => _send(controller),
      replyTo: replyTo,
      onCancelReply: controller.cancelReply,
    );

    Component rail() =>
        div(key: const ValueKey('rail'), classes: 'hermuse-rail-slot', [
          HermuseRail(
            instances: instances,
            activeInstanceId: instance.id,
            onSelectInstance: (id) => unawaited(_openInstance(id)),
            onAddInstance: hermuseDemo ? null : _addInstance,
            onOpenSettings: _openSettings,
            onOpenInstances: hermuseDemo
                ? null
                : () => setState(() => _overlay = _Overlay.instances),
            destination: _destination,
            onDestination: (target) => setState(() => _destination = target),
            chatsPanelOpen: chatsOpen,
            onToggleChatsPanel: () =>
                setState(() => _sidebarOverride = !chatsOpen),
          ),
        ]);

    // The product page on screen; null on the chat.
    final product = switch (_destination) {
      HermuseDestination.chat => null,
      HermuseDestination.feed => HermuseFeed(
        instance: instance,
        profile: controller.profile,
        onDiscuss: (seed) => _discussSeed(controller, seed),
      ),
      HermuseDestination.ideas => HermuseIdeas(
        instance: instance,
        profile: controller.profile,
        onStartInChat: (seed) => _discussSeed(controller, seed),
      ),
      HermuseDestination.goals => HermuseGoals(
        instance: instance,
        profile: controller.profile,
      ),
      HermuseDestination.library => HermuseLibrary(
        instance: instance,
        profile: controller.profile,
      ),
    };

    // The agent's computer takes everything right of the rail.
    if (state.computerOpen) {
      return div(classes: 'hermuse-shell', [
        div(classes: 'hermuse-nojs-note', [.text('Loading interactive chat…')]),
        rail(),
        HermuseComputerViewer(
          key: ValueKey('computer:${instance.id}:${controller.profile}'),
          controller: controller,
          instanceId: instance.id,
        ),
        div(classes: 'hermuse-computer-settings-menu', [
          HermuseSettingsMenu(
            onSettings: _openSettings,
            onInstances: hermuseDemo
                ? null
                : () => setState(() => _overlay = _Overlay.instances),
          ),
        ]),
      ]);
    }

    // Keys keep each column's DOM (and the panel's state) when a column
    // before it appears or goes.
    return div(classes: 'hermuse-shell', [
      div(classes: 'hermuse-nojs-note', [.text('Loading interactive chat…')]),
      rail(),
      if (chatsOpen)
        HermuseSidebar(
          key: ValueKey('chats-panel:${instance.id}:${controller.profile}'),
          controller: controller,
          readOnly: hermuseDemo,
          onOpenThread: (id) => _pickThread(controller, id, pinned: pinned),
          onNewSideChat: () => _newSideChat(controller, pinned: pinned),
          onSetPinned: (value) {
            // The open panel stays open whichever way the setting goes.
            setState(() => _sidebarOverride = true);
            unawaited(
              context.readProvider(chatPanelProvider.notifier).setPinned(value),
            );
          },
        ),
      if (split)
        div(key: const ValueKey('split-chat'), classes: 'hermuse-split-chat', [
          header(),
          thread(),
        ]),
      div(key: const ValueKey('thread-slot'), classes: 'hermuse-thread-slot', [
        if (product != null)
          // A product page enters with the page motion, once per destination.
          div(
            key: ValueKey(
              '${_destination.name}:${instance.id}:${controller.profile}',
            ),
            classes: 'hermuse-page ys-enter',
            [product],
          )
        else ...[
          header(),
          thread(),
        ],
        if (!onChat && _splitFits)
          div(classes: 'hermuse-floating-left', [
            YsTooltip(
              side: YsTooltipSide.below,
              label: split ? 'Maximize' : 'Open side-by-side chat',
              child: YsButton.icon(
                icon: split ? YsIcon.maximize : YsIcon.panelLeft,
                label: split ? 'Maximize' : 'Open side-by-side chat',
                onPressed: () => setState(() => _split = !split),
              ),
            ),
          ]),
        div(classes: 'hermuse-floating-right', [
          if (!profileOpen && !split)
            YsPressable(
              onPressed: () => setState(() => _panelOverride = true),
              label: 'Open profile panel',
              classes: 'hermuse-avatar-btn',
              builder: (context, press) => HermuseAgentAvatar(
                profile: controller.profile,
                avatarId: avatarId,
                chat: state,
                size: 36,
              ),
            ),
        ]),
        div(classes: 'hermuse-topbar', [
          div(classes: 'hermuse-topbar-lead', [
            if (sideChat)
              YsButton.icon(
                icon: YsIcon.arrowLeft,
                label: 'Back to main chat',
                onPressed: () => controller.openThread(state.mainThread.id),
              ),
            YsButton.icon(
              icon: YsIcon.menu,
              label: 'Open chats',
              onPressed: () => setState(() => _sidebarOverride = true),
            ),
          ]),
          div(classes: 'hermuse-topbar-title', [
            agentPicker(
              subtitle: !onChat
                  ? _destination.label
                  : sideChat
                  ? sideChatTitle(activeThread.title)
                  : 'Main chat',
            ),
          ]),
          div(classes: 'hermuse-topbar-trail', [
            YsPressable(
              onPressed: () => setState(() => _panelOverride = true),
              label: 'Open profile panel',
              classes: 'hermuse-avatar-btn hermuse-avatar-btn-sm',
              builder: (context, press) => HermuseAgentAvatar(
                profile: controller.profile,
                avatarId: avatarId,
                chat: state,
                size: 32,
              ),
            ),
          ]),
        ]),
        nav(
          classes: 'hermuse-bottomnav',
          attributes: {'aria-label': 'Primary'},
          [
            for (final target in HermuseDestination.values)
              YsPressable(
                onPressed: target == _destination
                    ? () {}
                    : () => setState(() => _destination = target),
                label: target.label,
                classes: 'hermuse-bottomnav-item',
                builder: (context, press) =>
                    YsIconView(target.icon, size: YsLayout.bottomNavIconSize),
              ),
            HermuseSettingsMenu(
              compact: true,
              onSettings: _openSettings,
              onInstances: hermuseDemo
                  ? null
                  : () => setState(() => _overlay = _Overlay.instances),
            ),
          ],
        ),
      ]),
      if (profileOpen)
        HermusePanel(
          agentName: agentName,
          profile: controller.profile,
          avatarId: avatarId,
          chat: state,
          onEditAgent: hermuseDemo || agent == null
              ? null
              : () => _editAgent(instance.id, agent),
          instanceId: controller.instanceId,
          threadIds: {for (final t in state.threads) t.id},
          approvals: state.approvals,
          tab: _tab,
          onTab: (t) => setState(() => _tab = t),
          onClose: () => setState(() => _panelOverride = false),
          onOpenThread: controller.openThread,
          onOpenApproval: (threadId) {
            controller.openThread(threadId);
            // Narrow layouts overlay the panel on the chat: show the chat.
            if (_shellKind != YsShell.wide) {
              setState(() => _panelOverride = false);
            }
          },
          onOpenComputer: controller.openComputer,
        ),
      if (profileOpen)
        div(
          classes: 'hermuse-panel-scrim',
          events: {'click': (_) => setState(() => _panelOverride = false)},
          [],
        ),
      if (chatsOpen)
        div(
          classes: 'hermuse-sidebar-scrim',
          events: {'click': (_) => setState(() => _sidebarOverride = false)},
          [],
        ),
      if (_agentEditorInstanceId case final editorInstanceId?)
        HermuseAgentEditor(
          key: ValueKey('editor:$editorInstanceId:${_editingAgent?.profile}'),
          instanceId: editorInstanceId,
          agent: _editingAgent,
          onClose: () => setState(() {
            _agentEditorInstanceId = null;
            _editingAgent = null;
          }),
        ),
    ]);
  }
}

/// Shell styles for [HermuseChatRoot] (`@css` cannot live on the private [State]).
@css
// ignore: unused_element
List<StyleRule> get hermuseShellStyles => [
  css('.hermuse-shell', [
    css('&').styles(
      height: 100.vh,
      display: .flex,
      flexDirection: .row,
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      overflow: .hidden,
      position: .relative(),
    ),
    css('& .hermuse-nojs-note').styles(display: .none),
    css('& .hermuse-rail-slot').styles(display: .contents),
    css('& .hermuse-thread-slot').styles(
      height: 100.percent,
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      position: .relative(),
      raw: {'min-width': '0', 'min-height': '0'},
    ),
    // A product page takes the slot like the route it holds.
    css('& .hermuse-page').styles(
      display: .flex,
      flexDirection: .column,
      flex: Flex(grow: 1, shrink: 1, basis: .zero),
      raw: {'min-width': '0', 'min-height': '0'},
    ),
    // Side-by-side chat on product routes: the chat (header, thread,
    // composer) docked between the rail and the route.
    css('& .hermuse-split-chat').styles(
      width: _splitChatWidth.px,
      height: 100.percent,
      display: .flex,
      flexDirection: .column,
      position: .relative(),
      border: .only(
        right: .solid(color: .variable('--line'), width: ysHairline.px),
      ),
      raw: {'flex-shrink': '0', 'min-height': '0'},
    ),
    // Floating header pills over the thread.
    css('& .hermuse-floating-left').styles(
      position: .absolute(top: 12.px, left: 12.px),
      raw: {'z-index': '10'},
    ),
    css('& .hermuse-floating-right').styles(
      position: .absolute(top: 12.px, right: 12.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
      raw: {'z-index': '10'},
    ),
    css('.hermuse-avatar-btn').styles(
      width: 36.px,
      height: 36.px,
      padding: .zero,
      radius: .circular(YsRadius.pill.px),
      overflow: .hidden,
      cursor: .pointer,
      border: .none,
      backgroundColor: Colors.transparent,
    ),
    css('.hermuse-avatar-btn:focus-visible').styles(
      outline: Outline(
        style: OutlineStyle.solid,
        color: .variable('--primary-ink'),
        width: OutlineWidth(2.px),
      ),
    ),
    css('& .hermuse-topbar').styles(display: .none),
    css('& .hermuse-bottomnav').styles(display: .none),
    // Scrims: hidden on wide, shown by media queries below.
    css('.hermuse-panel-scrim, .hermuse-sidebar-scrim').styles(
      display: .none,
      position: .absolute(top: 0.px, left: 0.px),
      width: 100.percent,
      height: 100.percent,
      backgroundColor: .variable('--backdrop'),
    ),
  ]),
  // Compact (<768): no rail, top bar, bottom nav, full-screen panel,
  // drawer sidebar. Every selector is scoped under `.hermuse-shell` so it
  // wins over the plain shell rules above regardless of emit order.
  css.media(MediaQuery.screen(maxWidth: 767.px), [
    css('.hermuse-shell .hermuse-rail-slot').styles(display: .none),
    css(
      '.hermuse-shell .hermuse-floating-left, .hermuse-shell .hermuse-floating-right',
    ).styles(display: .none),
    // Title centered on the bar whatever sits left (Back + Chats in a side
    // chat): equal flexible side columns.
    css('.hermuse-shell .hermuse-topbar').styles(
      height: YsLayout.topBarHeight.px,
      display: .grid,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
      padding: .symmetric(horizontal: YsSpace.sm.px),
      backgroundColor: .variable('--canvas'),
      border: .only(
        bottom: .solid(color: .variable('--line'), width: 1.2.px),
      ),
      raw: {
        'grid-template-columns': '1fr minmax(0, auto) 1fr',
        'flex-shrink': '0',
        'z-index': '10',
      },
    ),
    css('.hermuse-shell .hermuse-topbar-lead')
        .styles(display: .flex, alignItems: .center),
    css('.hermuse-shell .hermuse-topbar-trail').styles(
      display: .flex,
      justifyContent: .end,
      alignItems: .center,
      padding: .only(right: YsSpace.xs.px),
    ),
    css('.hermuse-shell .hermuse-topbar-title').styles(
      display: .flex,
      minWidth: 0.px,
      justifyContent: .center,
      textAlign: .center,
    ),
    css('.hermuse-shell .hermuse-bottomnav').styles(
      height: YsLayout.bottomNavHeight.px,
      display: .flex,
      flexDirection: .row,
      alignItems: .stretch,
      backgroundColor: .variable('--canvas'),
      border: .only(
        top: .solid(color: .variable('--line'), width: 1.2.px),
      ),
      raw: {'flex-shrink': '0', 'z-index': '10'},
    ),
    css('.hermuse-shell .hermuse-bottomnav-item').styles(
      flex: .grow(1),
      display: .flex,
      justifyContent: .center,
      alignItems: .center,
      padding: .symmetric(vertical: 12.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      opacity: 0.9,
    ),
    css('.hermuse-shell .hermuse-avatar-btn-sm')
        .styles(width: 32.px, height: 32.px),
    css('.hermuse-shell .hermuse-thread-slot > .hermuse-thread')
        .styles(raw: {'order': '1'}),
    css('.hermuse-shell .hermuse-thread-slot > .hermuse-bottomnav')
        .styles(raw: {'order': '2'}),
    css('.hermuse-shell .hermuse-thread .hermuse-thread-column').styles(
      padding: .only(
        top: 16.px,
        left: YsLayout.threadGutterPhone.px,
        right: YsLayout.threadGutterPhone.px,
        bottom: YsLayout.threadBottomPad.px,
      ),
    ),
    css('.hermuse-shell > .hermuse-sidebar').styles(
      position: .absolute(top: 0.px, left: 0.px),
      width: 280.px,
      raw: {'z-index': '30'},
    ),
    css('.hermuse-shell > .hermuse-sidebar-scrim')
        .styles(display: .block, raw: {'z-index': '20'}),
    css('.hermuse-shell > .hermuse-panel').styles(
      width: 100.percent,
      position: .absolute(top: 0.px, left: 0.px),
      border: .none,
      raw: {'z-index': '30'},
    ),
    css('.hermuse-shell > .hermuse-panel-scrim')
        .styles(display: .block, raw: {'z-index': '20'}),
    css('.hermuse-shell .hermuse-flights')
        .styles(width: 100.percent, maxWidth: 345.px),
  ]),
  // Mid band (768–1023): user bubbles go full width.
  css.media(MediaQuery.screen(maxWidth: 1023.px, minWidth: 768.px), [
    css('.hermuse-shell .hermuse-msg.hermuse-msg-user .hermuse-bubble-wrap')
        .styles(maxWidth: 100.percent),
  ]),
];
