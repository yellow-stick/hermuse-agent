import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_demo/hermuse_demo.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'relay.dart';
import 'scope_vm.dart' if (dart.library.js_interop) 'scope_web.dart' as boot;
import 'screens.dart';

/// Build flag (`jaspr build --dart-define=HERMUSE_DEMO=true`): the app runs
/// the read-only demo of `package:hermuse_demo` — fictional instances and
/// chats answered in the browser — instead of reaching Hermes through a
/// relay. Off in production builds, where the demo code is compiled out.
const hermuseDemo = bool.fromEnvironment('HERMUSE_DEMO');

/// Owns the web app's [ProviderContainer]: database, secrets, HTTP client.
///
/// Created lazily on the client only (never during SSR): the drift WASM
/// worker needs a real browser. The first open can take a moment (worker
/// boot + OPFS): [loading] shows meanwhile, the pre-rendered wait, so the
/// page stays as it was; the container appears once the database answers.
final class HermuseScope extends StatefulComponent {
  const HermuseScope({required this.loading, required this.child, super.key});

  final Component loading;
  final Component child;

  @override
  State<HermuseScope> createState() => _HermuseScopeState();

  /// The page's single container. The app mounts exactly one scope and only
  /// builds its subtree once the database booted, so every reader below it
  /// (builds, event handlers, async continuations whose element may already
  /// be gone) resolves the same container without an inherited lookup.
  static ProviderContainer get container =>
      _current ?? (throw StateError('HermuseScope has not booted'));

  static ProviderContainer? _current;

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => hermuseScreenStyles;
}

class _HermuseScopeState extends State<HermuseScope> {
  ProviderContainer? _container;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _boot();
  }

  Future<void> _boot() async {
    try {
      // The demo keeps its own database: seeding it replaces its content.
      final db = await boot.openDatabase(
        name: hermuseDemo ? 'hermuse-demo' : 'hermuse',
      );
      if (hermuseDemo) await seedDemo(db);
      if (!mounted) {
        await db.close();
        return;
      }
      final container = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          // Tab-lifetime secrets: the relay keeps the upstream session
          // cookie server-side, so a page reload only re-resolves.
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          httpClientProvider.overrideWith((ref) {
            final client = http.Client();
            ref.onDispose(client.close);
            return client;
          }),
          if (hermuseDemo) ...demoOverrides(),
        ],
      );
      assert(HermuseScope._current == null, 'one HermuseScope per page');
      HermuseScope._current = container;
      setState(() => _container = container);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    final container = _container;
    if (container != null) {
      if (identical(HermuseScope._current, container)) {
        HermuseScope._current = null;
      }
      unawaited(
        container
            .read(hermuseDatabaseProvider)
            .close()
            .then((_) => container.dispose()),
      );
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final container = _container;
    final error = _error;
    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: component.child,
      );
    }
    if (error == null) return component.loading;
    return div(classes: 'hermuse-screen', [
      div(classes: 'hermuse-card hermuse-card-narrow', [
        HermuseCardArt(YsArt.unreachable),
        h1(classes: 'hermuse-card-title', [.text('Storage unavailable')]),
        p(classes: 'hermuse-card-body', [
          .text(
            'Hermuse could not open its local database in this browser '
            '($error). Private windows without storage access are not '
            'supported.',
          ),
        ]),
        div(classes: 'hermuse-card-actions', [
          YsButton.primary(
            label: 'Retry',
            onPressed: () {
              if (kIsWeb) web.window.location.reload();
            },
          ),
        ]),
      ]),
    ]);
  }
}

/// Reads a Riverpod provider of the app [HermuseScope].
///
/// `jaspr_riverpod`'s `BuildContext.watch` wires rebuilds inside `build`;
/// these helpers cover reads outside it (event callbacks, async steps).
extension HermuseBuildContext on BuildContext {
  ProviderContainer get container => HermuseScope.container;

  T readProvider<T>(ProviderListenable<T> provider) =>
      HermuseScope.container.read(provider);
}

/// `ChatController` (listener → `setState`) shared with the subtree.
final class HermuseChatScope extends InheritedComponent {
  const HermuseChatScope({
    required this.controller,
    required this.thread,
    required super.child,
    super.key,
  });

  final ChatController controller;
  final ThreadRef thread;

  static HermuseChatScope of(BuildContext context) =>
      context
              .getElementForInheritedComponentOfExactType<HermuseChatScope>()!
              .component
          as HermuseChatScope;

  @override
  bool updateShouldNotify(HermuseChatScope oldComponent) =>
      controller != oldComponent.controller || thread != oldComponent.thread;
}

/// The same-origin relay serving this page, or `null` when the site is
/// served without one.
final relayProvider = FutureProvider<Uri?>(
  (ref) => Relay.detect(ref.watch(httpClientProvider), Uri.base),
);
