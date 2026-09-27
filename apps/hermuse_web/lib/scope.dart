import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'relay.dart';
import 'scope_vm.dart' if (dart.library.js_interop) 'scope_web.dart' as boot;

/// Owns the web app's [ProviderContainer]: database, secrets, HTTP client.
///
/// Created lazily on the client only (never during SSR): the drift WASM
/// worker needs a real browser. The first open can take a moment (worker
/// boot + OPFS); the container appears once the database answers.
final class HermuseScope extends StatefulComponent {
  const HermuseScope({required this.child, super.key});

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
  static List<StyleRule> get styles => [
    css('.hermuse-boot', [
      css('&').styles(
        flex: .grow(1),
        height: 100.percent,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        backgroundColor: .variable('--canvas'),
      ),
      css('.hermuse-boot-card').styles(
        maxWidth: YsLayout.dialogNarrow.px,
        margin: .symmetric(horizontal: 24.px),
        padding: .symmetric(vertical: 32.px, horizontal: 28.px),
        radius: .circular(YsRadius.bubble.px),
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        gap: .all(16.px),
        color: .variable('--content'),
        backgroundColor: .variable('--paper'),
      ),
      css('.hermuse-boot-title').styles(
        margin: .zero,
        fontSize: 22.px,
        lineHeight: 28.px,
        fontWeight: .w500,
      ),
      css('.hermuse-boot-body').styles(
        margin: .zero,
        textAlign: .center,
        fontSize: 16.px,
        lineHeight: 22.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-boot-spinner').styles(
        width: 28.px,
        height: 28.px,
        radius: .circular(14.px),
        border: .all(style: .solid, color: .variable('--line'), width: 3.px),
        raw: {
          'border-top-color': 'var(--primary)',
          'animation': 'hermuse-spin 800ms linear infinite',
        },
      ),
      css('.hermuse-boot-retry').styles(
        height: 40.px,
        padding: .symmetric(horizontal: 20.px),
        radius: .circular(YsRadius.pill.px),
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
        cursor: .pointer,
        border: .none,
        fontSize: 15.px,
        fontWeight: .w600,
      ),
    ]),
    css('@keyframes hermuse-spin', [
      css('to').styles(raw: {'transform': 'rotate(360deg)'}),
    ]),
  ];
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
      final db = await boot.openDatabase();
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
    return div(classes: 'hermuse-boot', [
      if (error != null)
        div(classes: 'hermuse-boot-card', [
          h1(classes: 'hermuse-boot-title', [.text('Storage unavailable')]),
          p(classes: 'hermuse-boot-body', [
            .text(
              'Hermuse could not open its local database in this browser '
              '($error). Private windows without storage access are not '
              'supported.',
            ),
          ]),
          button(
            classes: 'hermuse-boot-retry',
            onClick: () {
              if (kIsWeb) web.window.location.reload();
            },
            [.text('Retry')],
          ),
        ])
      else
        div(classes: 'hermuse-boot-card', [
          div(classes: 'hermuse-boot-spinner', []),
          p(classes: 'hermuse-boot-body', [.text('Opening Hermuse…')]),
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
