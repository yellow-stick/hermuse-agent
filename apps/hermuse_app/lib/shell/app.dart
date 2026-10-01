import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'package:hermuse_host/hermuse_host.dart'
    show DetectedHermes, RemoteInstallOutcome, localInstanceId;

import '../computer/computer_viewer.dart';
import '../host/install_flow.dart';
import '../host/linux_setup.dart';
import '../host/linux_setup_gate.dart';
import '../host/remote_install.dart';
import '../platform/local_host.dart';
import '../onboarding/components.dart';
import '../onboarding/connections.dart';
import '../onboarding/onboarding.dart';
import '../panel/profile_panel.dart';
import '../product/destination.dart';
import '../product/feed.dart';
import '../product/goals.dart';
import '../product/ideas.dart';
import '../product/library.dart';
import '../product/route.dart';
import '../sidebar/side_chats.dart';
import '../thread/thread_view.dart';
import 'brand.dart';
import 'chat_scope.dart';
import 'instances.dart';
import 'rail.dart';
import 'screens.dart';

/// App root: theme, chat scope, responsive shell.
///
/// The [ChatController] comes from [chatSessionProvider] for the active
/// thread; [controllerOverride] (tests only) bypasses the providers.
final class HermuseApp extends StatefulWidget {
  const HermuseApp({super.key, this.controllerOverride, this.keystoreError});

  final ChatController? controllerOverride;
  final Object? keystoreError;

  @override
  State<HermuseApp> createState() => HermuseAppState();
}

final class HermuseAppState extends State<HermuseApp> {
  ChatListenable? _chat;

  @override
  void dispose() {
    _chat?.dispose();
    super.dispose();
  }

  void _adopt(ChatController controller) {
    if (identical(_chat?.controller, controller)) return;
    _chat?.dispose();
    _chat = ChatListenable(controller);
  }

  @override
  Widget build(BuildContext context) {
    final keystoreError = widget.keystoreError;
    return YsTheme(
      palette: YsPalette.dark,
      child: WidgetsApp(
        title: 'Hermuse Agent',
        color: const Color(0xFF181819),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQueryData.fromView(View.of(context)),
          child: DefaultTextStyle(
            style: YsType.body.flutter.copyWith(
              color: YsPalette.dark.contentColor,
            ),
            // No Navigator (single screen), so no route Overlay: provide one
            // for kit overlays (tooltips, popovers) anchored in the shell.
            child: Overlay.wrap(
              child: keystoreError != null
                  ? ColoredBox(
                      color: YsPalette.dark.canvasColor,
                      child: KeystoreErrorScreen(error: keystoreError),
                    )
                  : _Root(
                      controllerOverride: widget.controllerOverride,
                      onAdopt: _adopt,
                      chat: () => _chat!,
                      current: () => _chat?.controller,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which full-screen surface the shell shows.
enum _Route {
  chat,
  welcome,
  addInstance,
  connectChoice,
  remoteInstall,
  remoteUninstall,
  install,
  instances,
  onboarding,
  connections,

  /// What Hermuse needs on a remote instance: after it is added, and from
  /// its row in the instances.
  components,
}

/// Picks the route (welcome / chat / instance screens) and the chat scope.
final class _Root extends ConsumerStatefulWidget {
  const _Root({
    required this.controllerOverride,
    required this.onAdopt,
    required this.chat,
    required this.current,
  });

  final ChatController? controllerOverride;
  final void Function(ChatController) onAdopt;
  final ChatListenable Function() chat;

  /// The chat currently on screen, if any.
  final ChatController? Function() current;

  @override
  ConsumerState<_Root> createState() => _RootState();
}

final class _RootState extends ConsumerState<_Root> {
  _Route _route = _Route.chat;
  String? _overlayInstanceId;
  _Route _connectReturn = _Route.chat;
  RemoteInstallOutcome? _remoteOutcome;

  /// The assistant keeps its state (the checklist's animations) when it
  /// moves between the full screen and the overlay.
  final _gateKey = GlobalKey();

  /// Whether the Linux setup assistant runs (Linux only, see `main()`).
  bool get _linux => ref.read(linuxSetupServicesProvider) != null;

  bool get _desktop => ref.read(localHostProvider) != null;

  @override
  void initState() {
    super.initState();
    if (widget.controllerOverride == null && _linux) {
      // Before anything connects: resume an unfinished install, or verify
      // the keyring the registered instances need.
      Future.microtask(() => ref.read(linuxSetupProvider.notifier).start());
    }
  }

  /// Takes the user where a finished setup leads.
  void _setupChanged(LinuxSetupState? previous, LinuxSetupState next) {
    if (next.phase is! SetupFinished) return;
    switch (next.goal) {
      case LinuxSetupGoal.connect:
        setState(
          () => _route = _desktop ? _Route.connectChoice : _Route.addInstance,
        );
      case LinuxSetupGoal.local:
        setState(() {
          _route = _Route.onboarding;
          _overlayInstanceId = localInstanceId;
        });
      case LinuxSetupGoal.reopen || LinuxSetupGoal.computer || null:
        break;
    }
    // A goal the user watched ends with its ready moment, which the
    // assistant acknowledges itself.
    if (!next.showsReady) {
      Future.microtask(ref.read(linuxSetupProvider.notifier).acknowledge);
    }
  }

  /// Connect to a Hermes server; on Linux the keyring comes first.
  void _connect() {
    _connectReturn = _route == _Route.instances
        ? _Route.instances
        : _Route.chat;
    _remoteOutcome = null;
    if (_linux && !ref.read(linuxSetupProvider).keystoreVerified) {
      unawaited(
        ref.read(linuxSetupProvider.notifier).prepare(LinuxSetupGoal.connect),
      );
      return;
    }
    setState(
      () => _route = _desktop ? _Route.connectChoice : _Route.addInstance,
    );
  }

  void _remoteInstalled(RemoteInstallOutcome outcome) => setState(() {
    _remoteOutcome = outcome;
    _route = _Route.addInstance;
  });

  void _cancelAdd() => setState(() {
    _remoteOutcome = null;
    _route = _desktop ? _Route.connectChoice : _Route.chat;
  });

  @override
  void dispose() {
    _remoteOutcome = null;
    super.dispose();
  }

  /// A Hermes was just saved: what it has shows first, its chat opens behind.
  void _added(String instanceId) {
    setState(() {
      _remoteOutcome = null;
      _route = _Route.components;
      _overlayInstanceId = instanceId;
    });
    unawaited(ref.read(activeThreadProvider.notifier).openInstance(instanceId));
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final override = widget.controllerOverride;
    if (override != null) {
      widget.onAdopt(override);
      return ChatScope(
        notifier: widget.chat(),
        child: ColoredBox(
          color: palette.canvasColor,
          child: _Shell(controller: override),
        ),
      );
    }
    if (ref.watch(linuxSetupServicesProvider) == null) return _routes(palette);
    final setup = ref.watch(linuxSetupProvider);
    ref.listen(linuxSetupProvider, _setupChanged);
    final instances = ref.watch(instancesProvider).value;
    // No registered instance connects before the keyring works, nor the
    // local one before its Docker engine is known.
    if ((instances == null || instances.isNotEmpty) &&
        (!setup.keystoreVerified ||
            (setup.goal == LinuxSetupGoal.reopen && setup.active))) {
      return LinuxSetupGate(key: _gateKey, canLeave: false);
    }
    final content = _routes(palette);
    if (!setup.active && !setup.showsReady) return content;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept alive under the assistant, back as it was once it closes.
        ExcludeFocus(child: Offstage(child: content)),
        LinuxSetupGate(key: _gateKey, canLeave: true),
      ],
    );
  }

  Widget _routes(YsPalette palette) {
    // The error/keyring screen reads nothing; everything else needs the DB.
    final instances = ref.watch(instancesProvider);
    final active = ref.watch(activeThreadProvider);
    final instanceList = instances.value;
    final thread = active.value;
    // Connection setup does not depend on an open chat. Keep its form alive
    // while the first instance saves to the keystore and registry.
    final connection = switch (_route) {
      _Route.connectChoice when _desktop => HermesPresentScreen(
        onYes: () => setState(() => _route = _Route.addInstance),
        onNo: () => setState(() => _route = _Route.remoteInstall),
        onCancel: () => setState(() => _route = _connectReturn),
      ),
      _Route.remoteInstall when _desktop => RemoteInstallScreen(
        onDone: _remoteInstalled,
        onCancel: () => setState(() => _route = _Route.connectChoice),
      ),
      _Route.remoteUninstall when _desktop => RemoteInstallScreen(
        remove: true,
        initialHost: instanceList
            ?.where((i) => i.id == _overlayInstanceId)
            .map((i) => i.baseUrl.host)
            .firstOrNull,
        onDone: _remoteInstalled,
        onCancel: () => setState(() => _route = _Route.instances),
      ),
      _Route.addInstance => AddInstanceScreen(
        initialUrl: _remoteOutcome?.baseUrl,
        initialUsername: _remoteOutcome?.username,
        initialPassword: _remoteOutcome?.password,
        autoProbe: _remoteOutcome != null,
        onDone: _added,
        onCancel: _cancelAdd,
      ),
      _ => null,
    };
    if (connection != null) {
      return ColoredBox(color: palette.canvasColor, child: connection);
    }
    if (instanceList != null && instanceList.isEmpty) {
      final host = ref.read(localHostProvider);
      return ColoredBox(
        color: palette.canvasColor,
        child: switch (_route) {
          _Route.install when host != null => _InstallRoute(
            host: host,
            onDone: () => setState(() => _route = _Route.chat),
            onCancel: () => setState(() => _route = _Route.chat),
          ),
          _ => WelcomeScreen(
            onConnect: _connect,
            onInstall: host == null
                ? null
                : _linux
                ? () => unawaited(
                    ref
                        .read(linuxSetupProvider.notifier)
                        .prepare(LinuxSetupGoal.local),
                  )
                : () => setState(() => _route = _Route.install),
          ),
        },
      );
    }
    // What a remote instance has needs no open chat.
    if (_route == _Route.components) {
      final instance = instanceList
          ?.where((i) => i.id == _overlayInstanceId)
          .firstOrNull;
      if (instance != null) {
        return ColoredBox(
          color: palette.canvasColor,
          child: ComponentsScreen(
            instance: instance,
            onChat: () async {
              setState(() => _route = _Route.chat);
              await ref
                  .read(activeThreadProvider.notifier)
                  .openInstance(instance.id);
            },
            onSetUpModel: () => setState(() {
              _route = _Route.onboarding;
              _overlayInstanceId = instance.id;
            }),
          ),
        );
      }
    }
    if (active.hasValue && thread != null) {
      return _ChatRoute(
        thread: thread,
        instances: instanceList ?? const [],
        route: _route,
        overlayInstanceId: _overlayInstanceId,
        onRoute: (route, [overlayId]) => setState(() {
          _route = route;
          _overlayInstanceId = overlayId;
        }),
        onConnect: _connect,
        onAdopt: widget.onAdopt,
        chat: widget.chat,
        current: widget.current,
      );
    }
    if (active.hasValue && thread == null && instanceList != null) {
      return ColoredBox(
        color: palette.canvasColor,
        child: Center(
          child: Text(
            'No conversation open',
            style: YsType.body.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ),
      );
    }
    final error = instances.hasError
        ? instances.error
        : active.hasError
        ? active.error
        : null;
    if (error != null) {
      return ColoredBox(
        color: palette.canvasColor,
        child: ChatErrorScreen(
          error: error,
          onRetry: () {
            ref.invalidate(instancesProvider);
            ref.invalidate(activeThreadProvider);
          },
          onManageInstances: () => setState(() => _route = _Route.instances),
        ),
      );
    }
    return LoadingScreen(art: YsArt.chats, label: 'Loading');
  }
}

/// Detects an existing install, then runs [InstallFlowScreen] (which
/// adopts it, or runs the official installer when there is none).
final class _InstallRoute extends StatefulWidget {
  const _InstallRoute({
    required this.host,
    required this.onDone,
    required this.onCancel,
  });

  final LocalHermesHost host;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  State<_InstallRoute> createState() => _InstallRouteState();
}

final class _InstallRouteState extends State<_InstallRoute> {
  late final Future<DetectedHermes?> _detected = widget.host.detector.detect();

  VoidCallback get onCancel => widget.onCancel;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _detected,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ChatErrorScreen(
          error: snapshot.error!,
          onRetry: onCancel,
          onManageInstances: onCancel,
        );
      }
      if (snapshot.connectionState != .done) {
        return LoadingScreen(
          art: YsArt.check,
          label: 'Looking for Hermes Agent',
        );
      }
      return InstallFlowScreen(
        host: widget.host,
        detected: snapshot.data,
        onDone: (_) => widget.onDone(),
        onCancel: onCancel,
      );
    },
  );
}

/// Loads the chat controller and shows the chat or an instance screen.
final class _ChatRoute extends ConsumerWidget {
  const _ChatRoute({
    required this.thread,
    required this.instances,
    required this.route,
    required this.overlayInstanceId,
    required this.onRoute,
    required this.onConnect,
    required this.onAdopt,
    required this.chat,
    required this.current,
  });

  final ThreadRef thread;
  final List<HermesInstance> instances;
  final _Route route;
  final String? overlayInstanceId;
  final void Function(_Route route, [String? overlayId]) onRoute;

  final VoidCallback onConnect;
  final void Function(ChatController) onAdopt;
  final ChatListenable Function() chat;
  final ChatController? Function() current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    switch (route) {
      case _Route.instances:
        return ColoredBox(
          color: palette.canvasColor,
          child: InstancesScreen(
            onAdd: onConnect,
            onInstall:
                ref.read(localHostProvider) != null &&
                    !instances.any((i) => i.kind == InstanceKind.local)
                ? ref.read(linuxSetupServicesProvider) != null
                      ? () => unawaited(
                          ref
                              .read(linuxSetupProvider.notifier)
                              .prepare(LinuxSetupGoal.local),
                        )
                      : () => onRoute(_Route.install)
                : null,
            onClose: () => onRoute(_Route.chat),
            onSetup: (id) => onRoute(_Route.onboarding, id),
            onComponents: (id) => onRoute(_Route.components, id),
            onConnections: (id) => onRoute(_Route.connections, id),
            onRemoveFromServer: ref.read(localHostProvider) != null
                ? (id) => onRoute(_Route.remoteUninstall, id)
                : null,
          ),
        );
      case _Route.onboarding:
      case _Route.connections:
        final overlayId = overlayInstanceId ?? thread.instanceId;
        final instance = instances.where((i) => i.id == overlayId).firstOrNull;
        if (instance != null) {
          return ColoredBox(
            color: palette.canvasColor,
            child: route == _Route.onboarding
                ? OnboardingScreen(
                    instance: instance,
                    onDone: (setup) async {
                      onRoute(_Route.chat);
                      final active = ref.read(activeThreadProvider.notifier);
                      // No setup conversation: just the instance's main chat.
                      await (setup.isNew
                          ? active.openInstance(setup.instanceId)
                          : active.openSetup(setup));
                    },
                    onSkipToChat: () => onRoute(_Route.chat),
                  )
                : ConnectionsScreen(
                    instance: instance,
                    onBack: () => onRoute(_Route.instances),
                  ),
          );
        }
        break;
      case _Route.install:
        final host = ref.read(localHostProvider);
        if (host != null) {
          return ColoredBox(
            color: palette.canvasColor,
            child: _InstallRoute(
              host: host,
              onDone: () => onRoute(_Route.chat),
              onCancel: () => onRoute(_Route.instances),
            ),
          );
        }
      // Shown by the root; an instance deleted meanwhile leaves the chat.
      case _Route.components:
      case _Route.addInstance:
      case _Route.connectChoice:
      case _Route.remoteInstall:
      case _Route.remoteUninstall:
      case _Route.welcome:
      case _Route.chat:
        break;
    }
    final session = ref.watch(chatSessionProvider(thread));
    final next = session.value;
    // Switching conversations keeps the current chat on screen (shell state,
    // scroll, sidebar all stay) until the next one has its transcript; only
    // then the thread content swaps. No spinner screen in between.
    final shown = current();
    if (next != null) {
      if (next.isReady || shown == null || identical(shown, next)) {
        return _adopted(context, next);
      }
      return FutureBuilder<void>(
        future: next.ready,
        builder: (context, snapshot) => snapshot.connectionState == .done
            ? _adopted(context, next)
            : _adopted(context, shown, switching: true),
      );
    }
    if (shown != null && !session.hasError) {
      return _adopted(context, shown, switching: true);
    }
    if (session.hasError) {
      return ColoredBox(
        color: palette.canvasColor,
        child: ChatErrorScreen(
          error: session.error!,
          onRetry: () => ref.invalidate(chatSessionProvider(thread)),
          onManageInstances: () => onRoute(_Route.instances),
        ),
      );
    }
    return LoadingScreen(art: YsArt.chats, label: 'Opening the chat');
  }

  Widget _adopted(
    BuildContext context,
    ChatController controller, {
    bool switching = false,
  }) {
    onAdopt(controller);
    final palette = YsTheme.of(context);
    return ChatScope(
      notifier: chat(),
      child: ColoredBox(
        color: palette.canvasColor,
        child: _Shell(
          // No per-thread key: the shell survives conversation switches.
          controller: controller,
          thread: switching ? null : thread,
          switching: switching,
          instance: instances
              .where((i) => i.id == controller.instanceId)
              .firstOrNull,
          onManageInstances: () => onRoute(_Route.instances),
        ),
      ),
    );
  }
}

final class _Shell extends ConsumerStatefulWidget {
  const _Shell({
    required this.controller,
    this.switching = false,
    this.thread,
    this.instance,
    this.onManageInstances,
  });

  final ChatController controller;
  final ThreadRef? thread;

  /// Another conversation is loading: this one stays, dimmed and inert.
  final bool switching;

  /// Instance of [thread]; product destinations need it.
  final HermesInstance? instance;
  final VoidCallback? onManageInstances;

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

/// Side-by-side chat column width on product routes.
const _splitChatWidth = 564.0;

/// Width a product route keeps beside the side-by-side chat before the
/// chat column narrows.
const _splitRouteMin = 360.0;

final class _ShellState extends ConsumerState<_Shell> {
  HermuseDestination _destination = HermuseDestination.chat;

  /// Chats panel opened from the thread header (desktop shells). It also
  /// shows while "Keep chat panel visible" is on.
  bool _chatsOpen = false;

  /// Chat docked beside the product routes (wide shell), kept while the app
  /// runs.
  bool _splitChat = false;

  // Null = follow the shell default: open on wide, closed elsewhere.
  bool? _panelOpenOverride;
  bool _drawerOpen = false;

  /// Keeps the thread (scroll, composer draft) across layout changes, e.g.
  /// docking it beside a route.
  final _threadKey = GlobalKey<ThreadViewState>();

  bool _panelOpenFor(YsShell shell) =>
      _panelOpenOverride ?? shell == YsShell.wide;

  /// The chat is on screen: the chat destination, or docked beside a route.
  bool _chatVisible(YsShell shell) =>
      widget.instance == null ||
      _destination == HermuseDestination.chat ||
      (shell == YsShell.wide && _splitChat);

  /// The docked chats panel shows (desktop shells, chat on screen).
  bool _chatsShown(YsShell shell, ChatPanelPrefs prefs) =>
      shell != YsShell.compact &&
      _chatVisible(shell) &&
      (prefs.pinned || _chatsOpen);

  void _openChats(YsShell shell) => setState(() {
    if (shell == YsShell.compact) {
      _drawerOpen = true;
    } else {
      _chatsOpen = true;
    }
  });

  /// A thread was picked in the docked panel: it closes unless kept visible.
  void _onPicked() => setState(() => _chatsOpen = false);

  /// Picked in the phone drawer: the drawer closes on the chat.
  void _onDrawerPicked() => setState(() {
    _drawerOpen = false;
    _destination = HermuseDestination.chat;
  });

  void _setKeepVisible(bool keep) {
    // Turning it off leaves the panel open until the next pick.
    setState(() => _chatsOpen = true);
    unawaited(ref.read(chatPanelProvider.notifier).setPinned(keep));
  }

  /// A rail destination; it also leaves the computer viewer.
  void _goTo(HermuseDestination destination) {
    if (widget.controller.state.computerOpen) {
      widget.controller.closeComputer();
    }
    setState(() => _destination = destination);
  }

  /// Discuss / Start in chat: [seed] lands in the main chat's composer,
  /// focused and not sent (a quote, never a new side chat). A
  /// docked side-by-side chat takes it without leaving the route.
  ///
  /// Product routes belong to the instance of [_Shell.controller], so its
  /// main chat is the instance's main chat.
  void _discuss(String seed) {
    final chat = widget.controller;
    chat.openThread(chat.state.mainThread.id);
    final shell = YsShell.forWidth(MediaQuery.sizeOf(context).width);
    // Always rebuilds, so the callback below runs once the chat is shown.
    setState(() {
      if (!(shell == YsShell.wide && _splitChat)) {
        _destination = HermuseDestination.chat;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _threadKey.currentState?.fillComposer(seed),
    );
  }

  /// The product page for [_destination], or null for the chat. A new page
  /// enters with [YsEntrance].
  Widget? _product() {
    final instance = widget.instance;
    if (instance == null) return null;
    final page = switch (_destination) {
      HermuseDestination.chat => null,
      HermuseDestination.feed => FeedScreen(
        instance: instance,
        onDiscuss: _discuss,
      ),
      HermuseDestination.ideas => IdeasScreen(
        instance: instance,
        onStartInChat: _discuss,
      ),
      HermuseDestination.goals => GoalsScreen(instance: instance),
      HermuseDestination.library => LibraryScreen(instance: instance),
    };
    return page == null
        ? null
        : YsEntrance(key: ValueKey(_destination), child: page);
  }

  KeyEventResult _onKeyFor(YsShell shell, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_drawerOpen) {
      setState(() => _drawerOpen = false);
      return KeyEventResult.handled;
    }
    final pinned = ref.read(chatPanelProvider).value?.pinned ?? false;
    if (_chatsOpen && !pinned && _chatsShown(shell, const ChatPanelPrefs())) {
      setState(() => _chatsOpen = false);
      return KeyEventResult.handled;
    }
    if (_panelOpenFor(shell)) {
      setState(() => _panelOpenOverride = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // The framework-free controller is not a Listenable; bridge it.
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChatChanged);
  }

  @override
  void didUpdateWidget(_Shell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChatChanged);
      widget.controller.addListener(_onChatChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChatChanged);
    super.dispose();
  }

  void _onChatChanged() => setState(() {});

  void _openApproval(PendingApprovalCard card) {
    widget.controller.openThread(card.threadId);
    if (_panelOpenOverride ?? true) {
      setState(() => _panelOpenOverride = false);
    }
  }

  List<PendingApprovalCard> _approvals(ChatState state) => [
    for (final thread in state.threads)
      for (final message in thread.messages)
        for (final block in message.blocks)
          if (block is ChoiceBlock &&
              block.customPlaceholder.isEmpty &&
              block.selected == null)
            PendingApprovalCard(
              threadId: thread.id,
              threadTitle: thread.title,
              messageId: message.id,
              prompt: block.prompt,
            ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final shell = YsShell.forWidth(width);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _onKeyFor(shell, node, event),
      child: ColoredBox(
        color: palette.canvasColor,
        child: _buildShell(context, palette, width, shell),
      ),
    );
  }

  Widget _buildShell(
    BuildContext context,
    YsPalette palette,
    double width,
    YsShell shell,
  ) {
    final state = widget.controller.state;
    final prefs = ref.watch(chatPanelProvider).value ?? const ChatPanelPrefs();
    final chatsShown = _chatsShown(shell, prefs);
    final compact = shell == YsShell.compact;
    final sideChats = SideChats(
      controller: widget.controller,
      onPicked: compact ? _onDrawerPicked : _onPicked,
      keepVisible: prefs.pinned,
      onKeepVisibleChanged: compact ? null : _setKeepVisible,
    );
    final panelOpen = _panelOpenFor(shell);
    void closePanel() => setState(() => _panelOpenOverride = false);
    void openPanel() => setState(() => _panelOpenOverride = true);
    final panel = ProfilePanel(
      agentName: state.agentName,
      activity: state.activity,
      approvals: _approvals(state),
      onOpenApproval: _openApproval,
      onOpenComputer: widget.controller.openComputer,
      onClose: closePanel,
    );
    Widget threadView({
      required double horizontalPadding,
      bool floatingHeader = true,
    }) => IgnorePointer(
      ignoring: widget.switching,
      child: AnimatedOpacity(
        opacity: widget.switching ? 0.55 : 1,
        duration: const Duration(milliseconds: YsMotion.fast),
        child: ThreadView(
          key: _threadKey,
          instanceId: widget.controller.instanceId,
          thread: state.activeThread,
          replyTo: state.replyTo,
          selectedOffers: state.selectedOffers,
          controller: widget.controller,
          chatsOpen: chatsShown,
          onOpenChats: () => _openChats(shell),
          panelOpen: panelOpen,
          onOpenPanel: openPanel,
          horizontalPadding: horizontalPadding,
          busy: state.busy,
          connection: state.connection,
          connectionError: state.connectionError,
          needsSignIn: state.needsSignIn,
          showFloatingHeader: floatingHeader,
        ),
      ),
    );
    var product = _product();
    final split = shell == YsShell.wide && product != null && _splitChat;
    if (product != null && shell == YsShell.wide) {
      product = RouteChatToggle(
        open: _splitChat,
        onToggle: () => setState(() => _splitChat = !_splitChat),
        child: product,
      );
    }
    final rail = HermuseRail(
      destination: _destination,
      onDestination: _goTo,
      onSettings: widget.onManageInstances ?? () {},
    );
    // The agent's computer replaces everything right of the rail.
    if (state.computerOpen) {
      return Row(
        children: [
          if (!compact) rail,
          Expanded(
            child: ComputerViewer(
              key: ValueKey(widget.controller.instanceId),
              controller: widget.controller,
              instanceId: widget.controller.instanceId,
            ),
          ),
        ],
      );
    }
    switch (shell) {
      case YsShell.compact:
        return _CompactShell(
          product: product,
          thread: threadView(
            horizontalPadding: YsLayout.threadGutterPhone,
            floatingHeader: false,
          ),
          destination: _destination,
          onDestination: _goTo,
          onMore: widget.onManageInstances ?? () {},
          state: state,
          controller: widget.controller,
          sideChats: sideChats,
          panel: panel,
          panelOpen: panelOpen,
          drawerOpen: _drawerOpen,
          onOpenPanel: openPanel,
          onCloseDrawer: () => setState(() => _drawerOpen = false),
          onOpenDrawer: () => setState(() => _drawerOpen = true),
        );
      case YsShell.medium:
        return Stack(
          children: [
            Row(
              children: [
                rail,
                if (chatsShown) DockedChatPanel(child: sideChats),
                Expanded(
                  child:
                      product ??
                      threadView(horizontalPadding: YsLayout.threadGutter),
                ),
              ],
            ),
            if (panelOpen) _PanelOverlay(panel: panel, onClose: closePanel),
          ],
        );
      case YsShell.wide:
        // Space left for the route and its side-by-side chat.
        final area =
            width -
            YsLayout.railWidth -
            (chatsShown ? prefs.width : 0) -
            (panelOpen ? YsLayout.panelWidth : 0);
        return Row(
          children: [
            rail,
            if (chatsShown) DockedChatPanel(child: sideChats),
            if (product == null)
              Expanded(
                child: threadView(horizontalPadding: YsLayout.threadGutter),
              )
            else ...[
              if (split)
                SizedBox(
                  width: math
                      .max(area - _splitRouteMin, area / 2)
                      .clamp(0.0, _splitChatWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: palette.lineColor,
                          width: ysHairline,
                        ),
                      ),
                    ),
                    child: threadView(horizontalPadding: YsLayout.threadGutter),
                  ),
                ),
              Expanded(child: product),
            ],
            if (panelOpen)
              SizedBox(
                width: YsLayout.panelWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: palette.lineColor,
                        width: ysHairline,
                      ),
                    ),
                  ),
                  child: panel,
                ),
              ),
          ],
        );
    }
  }
}

final class _PanelOverlay extends StatelessWidget {
  const _PanelOverlay({required this.panel, required this.onClose});

  final ProfilePanel panel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: palette.backdropColor),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: YsLayout.panelWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvasColor,
              border: Border(
                left: BorderSide(color: palette.lineColor, width: ysHairline),
              ),
            ),
            child: panel,
          ),
        ),
      ],
    );
  }
}

final class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.product,
    required this.thread,
    required this.destination,
    required this.onDestination,
    required this.onMore,
    required this.state,
    required this.controller,
    required this.sideChats,
    required this.panel,
    required this.panelOpen,
    required this.drawerOpen,
    required this.onOpenPanel,
    required this.onCloseDrawer,
    required this.onOpenDrawer,
  });

  /// Product page replacing the thread, or null for the chat.
  final Widget? product;
  final Widget thread;
  final HermuseDestination destination;
  final ValueChanged<HermuseDestination> onDestination;
  final VoidCallback onMore;
  final ChatState state;
  final ChatController controller;
  final SideChats sideChats;
  final ProfilePanel panel;
  final bool panelOpen;
  final bool drawerOpen;
  final VoidCallback onOpenPanel;
  final VoidCallback onCloseDrawer;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    if (panelOpen) {
      return panel;
    }
    final product = this.product;
    // A side chat on screen: back to the main chat, titled after it.
    final sideChat =
        product == null && state.activeThreadId != state.mainThread.id;
    return Stack(
      children: [
        Column(
          children: [
            SizedBox(
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: palette.lineColor,
                      width: ysHairline,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (sideChat)
                        YsButton.icon(
                          icon: YsIcon.arrowLeft,
                          onPressed: () =>
                              controller.openThread(state.mainThread.id),
                          semanticLabel: 'Back to main chat',
                          size: 36,
                          iconSize: 20,
                        ),
                      YsButton.icon(
                        icon: YsIcon.menu,
                        onPressed: onOpenDrawer,
                        semanticLabel: 'Open chats',
                        size: 36,
                        iconSize: 20,
                      ),
                      Expanded(
                        child: Text(
                          sideChat
                              ? sideChatLabel(state.activeThread.title)
                              : state.agentName,
                          style: YsType.heading.flutter.copyWith(
                            color: palette.contentColor,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      YsPressable(
                        onPressed: onOpenPanel,
                        semanticLabel: 'Open panel',
                        builder: (context, state) => YsAvatar(
                          hermuseAvatar,
                          size: 32,
                          semanticLabel: 'Open panel',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: product ?? thread),
            _BottomNav(
              destination: destination,
              onDestination: onDestination,
              onMore: onMore,
            ),
          ],
        ),
        if (drawerOpen)
          Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: onCloseDrawer,
                  child: ColoredBox(color: palette.backdropColor),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: YsLayout.sidebarWidth,
                child: ColoredBox(
                  color: palette.canvasColor,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 52,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: YsButton.icon(
                              icon: YsIcon.close,
                              onPressed: onCloseDrawer,
                              semanticLabel: 'Close chats',
                              size: 36,
                              iconSize: 20,
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: sideChats),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Phone bottom navigation: h52 bar, 6 icon-only 28px items (the five
/// destinations + More → instances).
final class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.destination,
    required this.onDestination,
    required this.onMore,
  });

  final HermuseDestination destination;
  final ValueChanged<HermuseDestination> onDestination;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return SizedBox(
      height: YsLayout.bottomNavHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.lineColor, width: ysHairline),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in HermuseDestination.values)
              _item(
                palette,
                item.icon,
                item.label,
                active: item == destination,
                onPressed: () => onDestination(item),
              ),
            _item(
              palette,
              YsIcon.more,
              'More',
              active: false,
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    YsPalette palette,
    YsIcon icon,
    String label, {
    required bool active,
    required VoidCallback onPressed,
  }) => Expanded(
    child: YsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: YsIconWidget(
            icon,
            size: YsLayout.bottomNavIconSize,
            color: active ? palette.contentColor : palette.contentMutedColor,
          ),
        ),
      ),
    ),
  );
}
