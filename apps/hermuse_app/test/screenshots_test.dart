import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_app/shell/brand.dart';
import 'package:hermuse_app/sidebar/side_chats.dart';
import 'package:hermuse_app/thread/thread_view.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Screenshot + interaction evidence for the Flutter surface.
///
/// Screenshots render the real app with the real Inter fonts; interaction
/// tests drive the app through [ChatController] and the actual widgets.
/// The app is pumped with provider overrides: an in-memory database, a
/// memory secret store, and a scripted [FakeHermesTransport] whose
/// `session.resume` transcript resembles the old demo conversation.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final packageRoot = _packageRoot();
  await _loadInter(packageRoot);
  await _loadEmojiFallback();

  _runScreenshotTest(
    testerName: 'wide',
    size: const Size(1938, 1062),
    fileName: 'wide-1938x1062.png',
  );
  _runScreenshotTest(
    testerName: 'wide-1440',
    size: const Size(1440, 900),
    fileName: 'wide-1440x900.png',
  );
  _runScreenshotTest(
    testerName: 'medium-1023',
    size: const Size(1023, 900),
    fileName: 'medium-1023x900.png',
  );
  _runScreenshotTest(
    testerName: 'tablet-768',
    size: const Size(768, 900),
    fileName: 'tablet-768x900.png',
  );
  _runScreenshotTest(
    testerName: 'compact',
    size: const Size(390, 844),
    fileName: 'compact-390x844.png',
  );
  _runScreenshotTest(
    testerName: 'compact-500',
    size: const Size(500, 900),
    fileName: 'compact-500x900.png',
  );

  group('interactions', () {
    testWidgets('Enter in composer sends and clears the field', (tester) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.text('hello from the test'), findsNothing);

      await tester.enterText(find.byType(EditableText).first, '');
      await tester.pump();
      await tester.enterText(
        find.byType(EditableText).first,
        'hello from the test',
      );
      await tester.pump();
      // Real-world path: physical Enter key (no shift) submits.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('hello from the test'), findsOneWidget);
      final field = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(field.controller.text, isEmpty);
      expect(
        harness.fake.calls.where((c) => c.method == 'prompt.submit'),
        isNotEmpty,
      );
    });

    testWidgets('stop button appears while busy and calls session.interrupt', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.bySemanticsLabel('Stop'), findsNothing);

      await tester.enterText(find.byType(EditableText).first, 'book it');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.bySemanticsLabel('Stop'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Stop'));
      await tester.pumpAndSettle();
      expect(
        harness.fake.calls
            .where((c) => c.method == 'session.interrupt')
            .single
            .params['session_id'],
        'live-1',
      );
    });

    testWidgets('approval card answer sends the JSON-RPC reply', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);

      harness.fake.emitRequest('srq-9', 'approval', {
        'session_id': 'live-1',
        'request_id': 'r1',
        'command': 'rm -rf dist',
        'allow_permanent': false,
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('rm -rf dist'), findsOneWidget);

      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      expect(harness.fake.replies['srq-9']?['result'], {'choice': 'once'});
    });

    testWidgets('add-instance flow shows the 401 login error', (tester) async {
      final db = openMemoryDatabase();
      addTearDown(db.close);
      final httpClient = MockClient((request) async {
        if (request.url.path == '/api/status') {
          return http.Response(
            '{"version":"0.21.5","auth_required":true,'
            '"auth_providers":["basic"],"auth_flows":["cookie"]}',
            200,
          );
        }
        return http.Response('{"detail":"bad credentials"}', 401);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermuseDatabaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
            httpClientProvider.overrideWithValue(httpClient),
            transportFactoryProvider.overrideWith(
              (ref) =>
                  (instance) => DashboardTransport.connect(
                    instance: instance,
                    secrets: ref.read(secretStoreProvider),
                    httpClient: ref.read(httpClientProvider),
                  ),
            ),
          ],
          child: const HermuseApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect to a Hermes'), findsWidgets);
      await tester.tap(find.widgetWithText(YsButton, 'Connect to a Hermes'));
      await tester.pumpAndSettle();

      // One field now (URL); Name/Username/Password join after the probe.
      final fields = find.byType(EditableText);
      await tester.enterText(fields.first, 'https://hermes.example.com');
      await tester.tap(find.widgetWithText(YsButton, 'Check'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hermes 0.21.5'), findsOneWidget);

      await tester.enterText(fields.at(2), 'admin');
      await tester.enterText(fields.at(3), 'wrong');
      await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('401'), findsOneWidget);
      expect(await db.loadInstances(), isEmpty);
    });
    testWidgets('auth failure shows sign-in form, sign-in retries the chat', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.text('Sign in again'), findsNothing);

      // The stored password stops working mid-session (rotated server-side).
      harness.fake.setState(
        ConnectionState.error,
        const HermesAuthFailed('401 Unauthorized', statusCode: 401),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      // Empty submit validates locally without touching the store.
      await tester.tap(find.widgetWithText(YsButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your username and password.'), findsOneWidget);

      // Rejected credentials surface the server sentence, store nothing.
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'admin');
      await tester.enterText(fields.at(1), 'wrong');
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid credentials'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HermuseApp)),
      );
      final secrets = container.read(secretStoreProvider);
      expect(
        await secrets.read(_Harness.instanceId, SecretKeys.password),
        isNull,
      );

      // Accepted credentials are stored, the connection reopens and the chat
      // leaves the error state.
      await tester.enterText(fields.at(1), _Harness.goodPassword);
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(
        await secrets.read(_Harness.instanceId, SecretKeys.password),
        _Harness.goodPassword,
      );
      expect(find.textContaining('Sign in again'), findsNothing);
    });

    testWidgets('reply preview appears and cancels', (tester) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.bySemanticsLabel('Cancel reply'), findsNothing);

      final controller = await harness.controller(tester);
      controller.startReply('row-1');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Cancel reply'), findsOneWidget);
      expect(find.textContaining('find me flights from Lisbon'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Cancel reply'), findsNothing);
      expect(controller.state.replyToId, isNull);
    });

    testWidgets('empty chats panel starts a side chat with its own header', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.text('Start a side chat'), findsNothing);

      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      // No side chat yet: the empty state only, no Main chat row.
      expect(find.text('Start a side chat'), findsOneWidget);
      expect(find.text('Main chat'), findsNothing);
      await _capture(tester, 'side-chats-empty.png');

      final controller = await harness.controller(tester);
      await tester.tap(find.widgetWithText(YsButton, 'New side chat'));
      await tester.pumpAndSettle();
      expect(controller.state.threads.length, 2);
      expect(controller.state.activeThreadId, startsWith('draft-'));
      // The panel closed on the new chat: Back + untitled title pill.
      expect(find.text('Start a side chat'), findsNothing);
      expect(find.bySemanticsLabel('Back to main chat'), findsOneWidget);
      expect(find.text('New side chat'), findsOneWidget);

      await _capture(tester, 'proof-side-chat.png');

      await tester.tap(find.bySemanticsLabel('Back to main chat'));
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'stored-1');
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('panel tab switch shows Approvals empty text', (tester) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.text('Today'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Approvals'));
      await tester.pumpAndSettle();
      expect(find.text('No approvals yet'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('pending approval appears in the Approvals tab', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);

      harness.fake.emitRequest('srq-9', 'approval', {
        'session_id': 'live-1',
        'request_id': 'r1',
        'command': 'rm -rf dist',
        'allow_permanent': false,
      });
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Approvals'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(find.textContaining('Approve this command'), findsWidgets);
    });

    testWidgets('close panel then avatar button reopens it', (tester) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      expect(find.text('Today'), findsOneWidget);
      expect(find.bySemanticsLabel('Open panel'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Close panel'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsNothing);
      expect(find.bySemanticsLabel('Open panel'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Open panel'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);

      await _capture(tester, 'proof-panel-reopened.png');
    });

    testWidgets('hovering rail and message actions shows tooltips', (
      tester,
    ) async {
      final harness = await _Harness.open();
      addTearDown(harness.dispose);
      await _pumpApp(tester, const Size(1938, 1062), harness);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);

      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Feed')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Feed'), findsWidgets);

      // Hovering a message reveals its actions, whose buttons carry tooltips.
      await mouse.moveTo(
        tester.getCenter(find.textContaining('Here are direct flights').first),
      );
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getCenter(find.bySemanticsLabel('Reply').first),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Reply'), findsWidgets);
    });
  });

  group('side chats', () {
    testWidgets('panel: Main chat, pinned first; hover shows time and menu', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      // Main chat, then the pinned side chat, then by last activity; the
      // archived one is not listed. The floating Chats pill hides.
      expect(_top(tester, 'Main chat'), lessThan(_top(tester, 'Oslo hotels')));
      expect(
        _top(tester, 'Oslo hotels'),
        lessThan(_top(tester, 'Fjord day trips')),
      );
      expect(
        _top(tester, 'Fjord day trips'),
        lessThan(_top(tester, 'Night train to Bergen')),
      );
      expect(find.text('Visa questions'), findsNothing);
      expect(_icon(YsIcon.pin), findsOneWidget);
      expect(find.text('Chats'), findsNothing);
      await _capture(tester, 'side-chats-panel.png');

      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Fjord day trips')));
      await tester.pumpAndSettle();
      expect(find.text('4h'), findsOneWidget);
      expect(find.bySemanticsLabel('More thread actions'), findsOneWidget);
      await _capture(tester, 'side-chats-row-hover.png');

      await tester.tap(find.bySemanticsLabel('More thread actions'));
      await tester.pumpAndSettle();
      for (final item in ['Pin', 'Rename', 'Archive', 'Delete']) {
        expect(find.text(item), findsOneWidget);
      }
      await _capture(tester, 'side-chats-menu.png');

      // Escape closes the menu, not the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Main chat'), findsOneWidget);
    });

    testWidgets('pin (right-click menu) moves the side chat to the top', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      await _rightClick(tester, 'Night train to Bergen');
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      expect(
        _top(tester, 'Night train to Bergen'),
        lessThan(_top(tester, 'Oslo hotels')),
      );
      expect(_icon(YsIcon.pin), findsNWidgets(2));
      final rows = await harness.db.loadSideChats(
        _Harness.instanceId,
        'stored-1',
      );
      expect(rows.first.sessionId, 'side-rail');

      // Unpinned, it falls back to its place by activity.
      await _rightClick(tester, 'Night train to Bergen');
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(
        _top(tester, 'Fjord day trips'),
        lessThan(_top(tester, 'Night train to Bergen')),
      );
      expect(_icon(YsIcon.pin), findsOneWidget);
    });

    testWidgets('archive drops the row and opens the main chat; restore', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      final controller = await harness.controller(tester);

      // Picking a side chat closes the panel on its header.
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fjord day trips'));
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'side-fjord');
      expect(find.text('Main chat'), findsNothing);
      expect(find.bySemanticsLabel('Back to main chat'), findsOneWidget);
      await _capture(tester, 'side-chat-header.png');

      // Its title pill reopens the panel.
      await tester.tap(find.bySemanticsLabel('Chats: Fjord day trips'));
      await tester.pumpAndSettle();
      await _rightClick(tester, 'Fjord day trips');
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(harness.calls('session.set_hidden'), [
        {'session_id': 'side-fjord', 'hidden': true},
      ]);
      expect(find.text('Fjord day trips'), findsNothing);
      expect(controller.state.activeThreadId, 'stored-1');

      await tester.tap(find.bySemanticsLabel('Side chat options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show archived chats'));
      await tester.pumpAndSettle();
      expect(find.text('Archived chats'), findsOneWidget);
      expect(find.text('Visa questions'), findsOneWidget);
      expect(find.text('Fjord day trips'), findsOneWidget);
      await _capture(tester, 'side-chats-archived.png');

      // An archived row opens its menu: Restore from archive.
      await tester.tap(find.text('Fjord day trips'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore from archive'));
      await tester.pumpAndSettle();
      expect(harness.calls('session.set_hidden').last, {
        'session_id': 'side-fjord',
        'hidden': false,
      });
      expect(find.text('Fjord day trips'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Back to chat list'));
      await tester.pumpAndSettle();
      expect(find.text('Fjord day trips'), findsOneWidget);
      expect(
        controller.state.sideThreads.map((t) => t.id),
        contains('side-fjord'),
      );
    });

    testWidgets('rename inline: Escape cancels, Enter saves', (tester) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      Future<Finder> rename() async {
        await _rightClick(tester, 'Oslo hotels');
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        return find.byWidgetPredicate(
          (w) =>
              w is EditableText && w.focusNode.debugLabel == 'Rename side chat',
        );
      }

      var field = await rename();
      final editing = tester.widget<EditableText>(field);
      expect(editing.focusNode.hasFocus, isTrue);
      expect(
        editing.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      await _capture(tester, 'side-chats-rename.png');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(find.text('Oslo hotels'), findsOneWidget);
      expect(harness.calls('session.title'), isEmpty);

      field = await rename();
      await tester.enterText(field, 'Oslo stays');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.calls('session.title'), [
        {'session_id': 'live-side-oslo', 'title': 'Oslo stays'},
      ]);
      expect(field, findsNothing);
      expect(find.text('Oslo stays'), findsOneWidget);
    });

    testWidgets('delete asks for confirmation first', (tester) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      Future<void> askDelete() async {
        await _rightClick(tester, 'Night train to Bergen');
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete side chat?'), findsOneWidget);
      }

      await askDelete();
      expect(
        find.text(
          'Deleting this side chat permanently removes it and cannot be '
          'undone.',
        ),
        findsOneWidget,
      );
      await _capture(tester, 'side-chats-delete.png');
      // Escape and Cancel keep it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Delete side chat?'), findsNothing);
      await askDelete();
      await tester.tap(find.widgetWithText(YsButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete side chat?'), findsNothing);
      expect(find.text('Night train to Bergen'), findsOneWidget);
      expect(harness.calls('session.delete'), isEmpty);

      await askDelete();
      await tester.tap(find.widgetWithText(YsButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(harness.calls('session.delete'), [
        {'session_id': 'side-rail'},
      ]);
      expect(find.text('Night train to Bergen'), findsNothing);
      expect(
        (await harness.db.loadSideChats(
          _Harness.instanceId,
          'stored-1',
        )).map((r) => r.sessionId),
        isNot(contains('side-rail')),
      );
    });

    testWidgets('search replaces the list; a result opens its thread', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      final controller = await harness.controller(tester);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      Future<void> search(String query) async {
        await tester.enterText(_searchField, query);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
      }

      Finder inPanel(Finder finder) =>
          find.descendant(of: find.byType(SideChats), matching: finder);

      await search('oslo');
      // A side chat title, a main chat message and a side chat message
      // match; the list is gone.
      expect(inPanel(find.text('Oslo hotels')), findsOneWidget);
      expect(inPanel(find.text('Side chat')), findsOneWidget);
      expect(
        inPanel(find.text('find me flights from Lisbon to Oslo')),
        findsOneWidget,
      );
      expect(inPanel(find.text('Main chat')), findsOneWidget);
      expect(inPanel(find.textContaining('leaves Oslo S')), findsOneWidget);
      expect(inPanel(find.text('Fjord day trips')), findsNothing);
      await _capture(tester, 'side-chats-search.png');

      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pumpAndSettle();
      expect(inPanel(find.text('Fjord day trips')), findsOneWidget);

      await search('oslo');
      await tester.tap(inPanel(find.textContaining('leaves Oslo S')));
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'side-rail');
      // The panel closed on the thread.
      expect(find.byType(SideChats), findsNothing);
    });

    testWidgets('kept visible, the panel stays after a pick and resizes', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness);
      final controller = await harness.controller(tester);
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Side chat options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep chat panel visible'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Oslo hotels'));
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'side-oslo');
      expect(find.text('Main chat'), findsOneWidget);
      expect(find.bySemanticsLabel('Back to main chat'), findsNothing);
      expect(await harness.db.readSetting('chat_panel_pinned'), 'true');

      // Dragging the right edge resizes the panel; the width is saved.
      expect(tester.getSize(find.byType(DockedChatPanel)).width, 240);
      await tester.drag(
        find.bySemanticsLabel('Resize panel'),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DockedChatPanel)).width, 300);
      expect(await harness.db.readSetting('chat_panel_width'), '300.0');
    });

    testWidgets('side-by-side chat docks beside Feed; Discuss seeds main', (
      tester,
    ) async {
      final harness = await _Harness.open(sideChats: true);
      addTearDown(harness.dispose);
      await _pumpApp(tester, _desktop, harness, plugin: _feedRoutes());
      final controller = await harness.controller(tester);
      await tester.tap(find.bySemanticsLabel('Close panel'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Feed'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR FEED PROMPT'), findsOneWidget);
      expect(find.byType(ThreadView), findsNothing);

      await tester.tap(find.bySemanticsLabel('Open side-by-side chat'));
      await tester.pumpAndSettle();
      // The chat (header + composer) docks at 564 px; the route stays.
      expect(tester.getSize(find.byType(ThreadView)).width, 564);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('YOUR FEED PROMPT'), findsOneWidget);
      expect(find.bySemanticsLabel('Maximize'), findsOneWidget);
      await _capture(tester, 'side-by-side-feed.png');

      // A side chat in the column; Discuss puts the post in the main chat's
      // composer, focused, without sending it or leaving the route.
      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oslo hotels'));
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'side-oslo');
      await tester.tap(find.text('Discuss').first);
      await tester.pumpAndSettle();
      expect(controller.state.activeThreadId, 'stored-1');
      final composer = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.focusNode.debugLabel == 'Message',
        ),
      );
      expect(
        composer.controller.text,
        "Let's discuss: Oslo in May\n\nFjords are thawing and the coastal "
        'ferries are back on their summer timetable.',
      );
      expect(composer.focusNode.hasFocus, isTrue);
      expect(harness.calls('prompt.submit'), isEmpty);
      expect(find.text('YOUR FEED PROMPT'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Maximize'));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadView), findsNothing);
      expect(find.text('YOUR FEED PROMPT'), findsOneWidget);
    });
  });
}

/// Test app wiring: one instance, memory DB/secrets, scripted transport.
final class _Harness {
  static const goodPassword = 'new-password';

  _Harness._(this.db, this.fake, this.ref);

  static const instanceId = 'vps';

  final HermuseDatabase db;
  final FakeHermesTransport fake;
  final ThreadRef ref;

  /// Transcripts of the side chats seeded by [open] (`sideChats: true`).
  static const _sideTranscripts = {
    'side-oslo': (
      'Oslo hotels',
      [
        {'role': 'user', 'text': 'Where should we stay in Oslo?', 'row_id': 21},
        {
          'role': 'assistant',
          'text': 'Grünerløkka is lively; Frogner is calmer, near the park.',
          'row_id': 22,
        },
      ],
    ),
    'side-fjord': (
      'Fjord day trips',
      [
        {
          'role': 'user',
          'text': 'Best fjord day trip from Bergen?',
          'row_id': 41,
        },
        {
          'role': 'assistant',
          'text':
              'Norway in a Nutshell: train, Flåm railway and a fjord cruise.',
          'row_id': 42,
        },
      ],
    ),
    'side-rail': (
      'Night train to Bergen',
      [
        {
          'role': 'user',
          'text': 'Is there a night train to Bergen?',
          'row_id': 31,
        },
        {
          'role': 'assistant',
          'text':
              'Yes: the Bergen line leaves Oslo S at 23:25, arriving 07:43.',
          'row_id': 32,
        },
      ],
    ),
  };

  /// [sideChats] seeds side chats of the main chat (one pinned, one
  /// archived) and caches the Bergen transcript for search.
  static Future<_Harness> open({bool sideChats = false}) async {
    final db = openMemoryDatabase();
    final instance = HermesInstance(
      id: instanceId,
      label: 'VPS',
      kind: InstanceKind.remote,
      baseUrl: Uri.parse('https://hermes.example.com'),
      auth: AuthMethod.password,
    );
    await db.saveInstances([instance], primaryId: instanceId);
    await db.writeSetting(
      'active_thread',
      '{"instance_id":"$instanceId","session_id":"stored-1"}',
    );
    if (sideChats) {
      final now = DateTime.now();
      int ago(Duration age) => now.subtract(age).millisecondsSinceEpoch;
      SessionRow row(
        String id,
        String title,
        Duration age, {
        String? parentId = 'stored-1',
        Duration? pinned,
        bool archived = false,
      }) => SessionRow(
        instanceId: instanceId,
        sessionId: id,
        title: title,
        parentId: parentId,
        updatedAt: ago(age),
        archived: archived,
        pinnedAt: pinned == null ? null : ago(pinned),
      );
      for (final session in [
        row(
          'stored-1',
          'Trip planning',
          const Duration(minutes: 1),
          parentId: null,
        ),
        row(
          'side-oslo',
          'Oslo hotels',
          const Duration(minutes: 3),
          pinned: const Duration(hours: 1),
        ),
        row('side-fjord', 'Fjord day trips', const Duration(hours: 4)),
        row('side-rail', 'Night train to Bergen', const Duration(days: 3)),
        row(
          'side-visa',
          'Visa questions',
          const Duration(days: 9),
          archived: true,
        ),
      ]) {
        await db.upsertSession(session);
      }
      await db.cacheTranscript(instanceId, 'side-rail', [
        for (final m in _sideTranscripts['side-rail']!.$2)
          MessageRow(
            instanceId: instanceId,
            sessionId: 'side-rail',
            messageId: 'row-${m['row_id']}',
            author: m['role'] == 'user' ? 'user' : 'agent',
            bodyText: m['text']! as String,
            createdAt: m['row_id']! as int,
          ),
      ]);
    }
    final fake = FakeHermesTransport()
      ..on('session.resume', (params) {
        final id = params['session_id']! as String;
        if (_sideTranscripts[id] case (final title, final messages)) {
          return {
            'session_id': 'live-$id',
            'message_count': messages.length,
            'info': {'title': title},
            'messages': messages,
          };
        }
        assert(id == 'stored-1');
        return {
          'session_id': 'live-1',
          'message_count': 4,
          'info': {'title': 'Trip planning'},
          'messages': [
            {
              'role': 'user',
              'text': 'find me flights from Lisbon to Oslo',
              'row_id': 1,
            },
            {
              'role': 'assistant',
              'text': 'On it — searching direct flights.',
              'reasoning': 'The user wants direct flights; check carriers.',
              'row_id': 2,
            },
            {
              'role': 'tool',
              'name': 'web_search',
              'tool_call_id': 't0',
              'context': 'flights LIS OSL direct',
              'row_id': 3,
            },
            {
              'role': 'assistant',
              'text': 'Here are direct flights I found.',
              'row_id': 4,
            },
          ],
        };
      })
      ..on('prompt.submit', (_) => const <String, Object?>{})
      ..on('session.interrupt', (_) => {'status': 'interrupted'})
      ..on(
        'session.create',
        (_) => {
          'session_id': 'live-new',
          'stored_session_id': 'stored-new',
          'message_count': 0,
          'messages': const [],
          'info': const <String, Object?>{},
        },
      )
      ..on('session.list', (_) => const {'sessions': []})
      ..on(
        'session.set_hidden',
        (params) => {'hidden': params['hidden'], 'session_key': 'k'},
      )
      ..on('session.close', (_) => {'closed': true})
      ..on('session.delete', (params) => {'deleted': params['session_id']})
      ..on('session.title', (params) => {'title': params['title']});
    return _Harness._(
      db,
      fake,
      const ThreadRef(instanceId: instanceId, sessionId: 'stored-1'),
    );
  }

  Future<void> dispose() async {
    await fake.close();
    await db.close();
  }

  /// The chat controller the app opened for [ref].
  Future<ChatController> controller(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HermuseApp)),
    );
    return container.read(chatSessionProvider(ref).future);
  }

  /// Parameters of the scripted [method] calls, in order.
  List<Map<String, Object?>> calls(String method) => [
    for (final call in fake.calls)
      if (call.method == method) call.params,
  ];
}

/// Desktop viewport of the side chat captures (wide reference width).
const _desktop = Size(1440, 900);

/// Vertical position of [text] (row order).
double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Finder _icon(YsIcon icon) =>
    find.byWidgetPredicate((w) => w is YsIconWidget && w.icon == icon);

/// The chats panel search field.
Finder get _searchField => find.descendant(
  of: find.byType(SideChats),
  matching: find.byType(EditableText),
);

/// Opens the thread actions menu of the row titled [title] (right-click).
Future<void> _rightClick(WidgetTester tester, String title) async {
  await tester.tap(
    find.text(title),
    buttons: kSecondaryMouseButton,
    kind: ui.PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

/// Hermuse plugin REST for Feed: prompt, two posts, reactions.
Map<String, Object? Function(http.Request)> _feedRoutes() {
  Map<String, Object?> post(String id, String title, String body) => {
    'id': id,
    'title': title,
    'topic': 'travel',
    'body': body,
    'sources': <String>[],
    'file': 'feed/$id.md',
    'created_at': '2026-09-27',
    'reactions': <String, String>{},
  };
  final posts = [
    post(
      'p1',
      'Oslo in May',
      'Fjords are thawing and the coastal ferries are back on their summer '
          'timetable.',
    ),
    post(
      'p2',
      'The Bergen line at night',
      'A sleeper cabin beats an early flight: dinner in Oslo, breakfast in '
          'Bergen.',
    ),
  ];
  return {
    'GET /api/plugins/hermuse/files': (_) => {'files': <Object?>[]},
    'GET /api/plugins/hermuse/files/FEED_PROMPT.md': (_) => {
      'name': 'FEED_PROMPT.md',
      'content': 'Travel ideas for Norway: trains over flights.',
    },
    'GET /api/plugins/hermuse/feed': (_) => {'posts': posts},
    'POST /api/plugins/hermuse/feed/p1/react': (_) => {
      ...posts.first,
      'reactions': {'discuss': 'now'},
    },
  };
}

/// Pumps the app at [size] with [harness] overrides, settling animations.
///
/// Wraps the app in a keyed [RepaintBoundary] so [_capture] grabs full-app
/// pixels rather than a nested boundary.
final _captureKey = GlobalKey();

Future<void> _pumpApp(
  WidgetTester tester,
  Size size,
  _Harness harness, {
  http.Client? httpClient,
  Map<String, Object? Function(http.Request)>? plugin,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: ProviderScope(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(harness.db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          // A (re)opened connection starts healthy, like a new socket.
          transportFactoryProvider.overrideWithValue((_) async {
            if (harness.fake.currentState == ConnectionState.error) {
              harness.fake.setState(ConnectionState.ready);
            }
            return _SharedTransport(harness.fake);
          }),
          // No socket can open in widget tests: the trial connection accepts
          // exactly [_Harness.goodPassword].
          trialConnectProvider.overrideWithValue((instance, secrets) async {
            final password = await secrets.read(
              instance.id,
              SecretKeys.password,
            );
            if (password != _Harness.goodPassword) {
              throw const HermesAuthFailed(
                'Invalid credentials',
                statusCode: 401,
              );
            }
          }),
          if (httpClient != null)
            httpClientProvider.overrideWithValue(httpClient),
          // Hermuse plugin REST (`'METHOD /path'`); other routes answer 404.
          if (plugin != null)
            restClientProvider(_Harness.instanceId).overrideWith(
              (ref) => HermesRestClient(
                MockClient((request) async {
                  final route = plugin['${request.method} ${request.url.path}'];
                  return route == null
                      ? http.Response('{"detail":"Not Found"}', 404)
                      : http.Response(jsonEncode(route(request)), 200);
                }),
                baseUrl: Uri.parse('https://hermes.example.com'),
              ),
            ),
        ],
        child: const HermuseApp(),
      ),
    ),
  );
  // Asset images decode off the fake-async zone; wait for the avatar so
  // captures show it.
  await tester.runAsync(
    () => precacheImage(hermuseAvatar, tester.element(find.byType(HermuseApp))),
  );
  await tester.pumpAndSettle();
}

/// Captures the current app pixels to `.artifacts/flutter/[fileName]`.
Future<void> _capture(WidgetTester tester, String fileName) async {
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('${_artifactsDir.path}/$fileName')
      ..parent.createSync(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    if (kDebugMode) {
      debugPrint('wrote ${out.path}');
    }
  });
}

/// Absolute path of the workspace root: walk up from this test file.
String _packageRoot() {
  var dir = File(Platform.script.toFilePath()).parent;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/packages/yellow_stick_ui').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}

void _runScreenshotTest({
  required String testerName,
  required Size size,
  required String fileName,
}) {
  testWidgets('screenshot $testerName', (tester) async {
    final harness = await _Harness.open();
    addTearDown(harness.dispose);
    await _pumpApp(tester, size, harness);
    await _capture(tester, fileName);
  });
}

Future<void> _loadInter(String workspaceRoot) async {
  Future<ByteData> font(String name) async {
    final bytes = await File(
      '$workspaceRoot/packages/yellow_stick_ui/fonts/$name',
    ).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  // TextStyles using `package: 'yellow_stick_ui'` resolve this family.
  final packaged = FontLoader('packages/yellow_stick_ui/Inter')
    ..addFont(font('Inter-Regular.ttf'))
    ..addFont(font('Inter-Medium.ttf'))
    ..addFont(font('Inter-SemiBold.ttf'));
  await packaged.load();
}

Future<void> _loadEmojiFallback() async {
  const candidates = [
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    '/usr/share/fonts/truetype/google-fonts/SANS_SERIF/NotoColorEmoji-Regular.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      final loader = FontLoader('Noto Color Emoji')
        ..addFont(
          (() async => ByteData.sublistView(await file.readAsBytes()))(),
        );
      await loader.load();
      return;
    }
  }
}

/// `<workspace root>/.artifacts/flutter`, whatever directory the tests run
/// from (package dir under `flutter test`, root under `melos`).
final Directory _artifactsDir = () {
  var dir = Directory.current.absolute;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return Directory('${dir.path}/.artifacts/flutter');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('No pub workspace root above ${Directory.current.path}');
    }
    dir = parent;
  }
}();

/// The harness fake behind every (re)opened connection: closing a
/// connection (invalidate, sign-in) must not close the scripted fake.
final class _SharedTransport implements HermesTransport {
  _SharedTransport(this._fake);
  final FakeHermesTransport _fake;

  @override
  ConnectionState get currentState => _fake.currentState;

  @override
  Stream<ConnectionState> get state => _fake.state;

  @override
  Object? get lastError => _fake.lastError;

  @override
  Stream<HermesEvent> get events => _fake.events;

  @override
  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  ) => _fake.call(method, params);

  @override
  void onServerRequest(ServerRequestHandler handler) =>
      _fake.onServerRequest(handler);

  @override
  void redeliverServerRequest(
    String id,
    String method,
    Map<String, Object?> params,
  ) => _fake.redeliverServerRequest(id, method, params);

  @override
  Future<void> close() async {}
}
