import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_app/shell/instances.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

const _goodToken = 'good-token';

/// The system keyring: writing a secret takes a while (a D-Bus round trip,
/// here longer than a `pumpAndSettle` step), during which the app draws
/// frames.
final class _Keyring implements SecretStore {
  final _values = MemorySecretStore();

  @override
  Future<String?> read(String instanceId, String key) =>
      _values.read(instanceId, key);

  @override
  Future<void> write(String instanceId, String key, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _values.write(instanceId, key, value);
  }

  @override
  Future<void> delete(String instanceId) => _values.delete(instanceId);
}

/// A `hermes serve` without a dashboard gate: `/api/ws` wants the session
/// token, and only [_goodToken] opens it.
final class _TokenHermes {
  _TokenHermes() : db = openMemoryDatabase();

  final HermuseDatabase db;
  final secrets = _Keyring();
  final fake = FakeHermesTransport()
    ..on('session.list', (_) => const {'sessions': []})
    ..on(
      'session.create',
      (_) => {
        'session_id': 'live-1',
        'stored_session_id': 'stored-1',
        'message_count': 0,
        'messages': const [],
        'info': const <String, Object?>{},
      },
    );

  /// Tokens the trial connections were opened with.
  final tried = <String?>[];

  /// How many `/api/status` requests arrived.
  var probes = 0;

  /// How many of the next probes find no host.
  var unreachable = 0;

  Future<void> pump(WidgetTester tester) async {
    await open(tester);
    await check(tester, 'http://127.0.0.1:9119');
  }

  /// Starts the app and opens "Add a Hermes".
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
          httpClientProvider.overrideWithValue(
            MockClient((request) async {
              if (request.url.path == '/api/status') {
                probes++;
                if (unreachable > 0) {
                  unreachable--;
                  throw http.ClientException('Connection refused');
                }
              }
              return switch (request.url.path) {
                '/api/status' => http.Response(
                  jsonEncode({
                    'version': '0.21.5',
                    'auth_required': false,
                    'auth_providers': <String>[],
                    'auth_flows': <String>[],
                  }),
                  200,
                ),
                // Every other route checks the session token, like
                // `hermes serve`.
                _
                    when request.headers['x-hermes-session-token'] !=
                        _goodToken =>
                  http.Response('{"detail":"Unauthorized"}', 401),
                _ => http.Response('{}', 200),
              };
            }),
          ),
          // No socket opens in widget tests: the trial records the token the
          // `/api/ws` upgrade would carry.
          trialConnectProvider.overrideWithValue((instance, trial) async {
            tried.add(await trial.read(instance.id, SecretKeys.sessionToken));
          }),
          transportFactoryProvider.overrideWithValue((_) async => fake),
        ],
        child: const HermuseApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(YsChoiceCard, 'Connect to a Hermes'));
    await tester.pumpAndSettle();
  }

  /// Types [url] and presses Check.
  Future<void> check(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(EditableText).first, url);
    await tester.pump();
    await tester.tap(find.widgetWithText(YsButton, 'Check'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String token) async {
    await tester.enterText(find.byType(EditableText).at(2), token);
    await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await fake.close();
    await db.close();
  }
}

void main() {
  group('AddInstanceScreen', () {
    testWidgets('should connect a gateless Hermes with its session token', (
      tester,
    ) async {
      final hermes = _TokenHermes();
      addTearDown(hermes.dispose);
      await hermes.pump(tester);

      expect(find.textContaining('paste its session token'), findsOneWidget);
      expect(find.text('Session token'), findsOneWidget);
      expect(find.textContaining('no login'), findsNothing);
      expect(find.text('Username'), findsNothing);

      await hermes.save(tester, _goodToken);

      expect(hermes.tried, [_goodToken]);
      // The first Hermes saved goes on to what it has.
      expect(find.text("What's on 127.0.0.1"), findsOneWidget);
      final saved = await hermes.db.loadInstances();
      expect(saved.single.auth, AuthMethod.loopbackToken);
      expect(
        await hermes.secrets.read(saved.single.id, SecretKeys.sessionToken),
        _goodToken,
      );
      expect(
        await hermes.secrets.read(saved.single.id, SecretKeys.password),
        isNull,
      );
    });

    testWidgets('should keep nothing and say so when the token is wrong', (
      tester,
    ) async {
      final hermes = _TokenHermes();
      addTearDown(hermes.dispose);
      await hermes.pump(tester);

      await hermes.save(tester, 'wrong');

      expect(find.text('Wrong session token.'), findsOneWidget);
      expect(await hermes.db.loadInstances(), isEmpty);
    });

    testWidgets('should check nothing until an address is typed', (
      tester,
    ) async {
      final hermes = _TokenHermes();
      addTearDown(hermes.dispose);
      await hermes.open(tester);

      await tester.tap(find.widgetWithText(YsButton, 'Check'));
      await tester.pumpAndSettle();
      expect(hermes.probes, 0);

      await hermes.check(tester, 'http://127.0.0.1:9119');
      expect(hermes.probes, 1);
      expect(find.textContaining('Hermes 0.21.5'), findsOneWidget);
    });

    testWidgets('should say when nothing answers and check again on retry', (
      tester,
    ) async {
      final hermes = _TokenHermes()..unreachable = 1;
      addTearDown(hermes.dispose);
      await hermes.open(tester);

      await hermes.check(tester, 'http://127.0.0.1:9119');
      expect(find.textContaining('Host unreachable'), findsOneWidget);
      expect(find.text('Session token'), findsNothing);

      await tester.tap(find.widgetWithText(YsButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(hermes.probes, 2);
      expect(find.textContaining('Host unreachable'), findsNothing);
      expect(find.text('Session token'), findsOneWidget);
    });

    testWidgets(
      'should prove a generated dashboard login before storing it securely',
      (tester) async {
        final hermes = _DashboardHermes();
        addTearDown(hermes.db.close);
        await hermes.pump(tester);
        expect(
          tester
              .widget<EditableText>(_dashboardField('Password'))
              .controller
              .text,
          _dashboardPassword,
        );
        expect(await hermes.db.loadInstances(), isEmpty);

        await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));
        await tester.pump();
        await tester.pump();
        expect(await hermes.db.loadInstances(), isEmpty);
        expect(hermes.savedId, isNull);

        hermes.authenticated.complete();
        await tester.pumpAndSettle();
        final instance = (await hermes.db.loadInstances()).single;
        expect(hermes.savedId, isNull, reason: 'The keyring is still writing.');
        expect(
          await hermes.secrets.read(instance.id, SecretKeys.password),
          isNull,
        );
        hermes.secrets.writable.complete();
        await tester.pumpAndSettle();
        expect(instance.id, hermes.savedId);
        expect(instance.baseUrl, Uri.parse(_dashboardUrl));
        expect(instance.auth, AuthMethod.password);
        expect(
          await hermes.secrets.read(instance.id, SecretKeys.password),
          _dashboardPassword,
        );
        expect(
          await hermes.secrets.read(instance.id, SecretKeys.username),
          'admin',
        );
        expect(
          await hermes.secrets.read(instance.id, SecretKeys.sessionToken),
          isNull,
        );
        expect(
          tester
              .widget<EditableText>(_dashboardField('Password'))
              .controller
              .text,
          isEmpty,
        );
      },
    );

    testWidgets(
      'should discard a stale probe and never send generated credentials to an edited URL',
      (tester) async {
        final hermes = _DashboardHermes()..statusRelease = Completer<void>();
        addTearDown(hermes.db.close);
        await hermes.pump(tester, settle: false);
        await tester.enterText(
          _dashboardField('Instance URL'),
          'https://another.example',
        );
        hermes.statusRelease!.complete();
        await tester.pumpAndSettle();
        expect(_dashboardField('Password'), findsNothing);

        await tester.tap(find.widgetWithText(YsButton, 'Check'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(_dashboardField('Password'))
              .controller
              .text,
          isEmpty,
        );
        await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));
        await tester.pumpAndSettle();
        expect(hermes.logins, isEmpty);
        expect(await hermes.db.loadInstances(), isEmpty);
        expect(hermes.savedId, isNull);
      },
    );

    testWidgets(
      'should retain the generated sign-in after an unreachable dashboard becomes available',
      (tester) async {
        final hermes = _DashboardHermes()..unreachable = true;
        addTearDown(hermes.db.close);
        await hermes.pump(tester);
        expect(_dashboardField('Password'), findsNothing);
        expect(await hermes.db.loadInstances(), isEmpty);

        hermes.unreachable = false;
        await tester.tap(find.widgetWithText(YsButton, 'Try again'));
        await tester.pumpAndSettle();
        hermes.authenticated.complete();
        hermes.secrets.writable.complete();
        await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));
        await tester.pumpAndSettle();
        final instance = (await hermes.db.loadInstances()).single;
        expect(
          await hermes.secrets.read(instance.id, SecretKeys.password),
          _dashboardPassword,
        );
      },
    );
  });
}

const _dashboardUrl = 'https://hermuse.203-0-113-10.sslip.io';
const _dashboardPassword = 'generated-dashboard-secret';

Finder _dashboardField(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is YsInputBox && widget.semanticLabel == label,
  ),
  matching: find.byType(EditableText),
);

/// A keyring write completes only when the platform grants access.
final class _ControlledKeyring implements SecretStore {
  final _values = MemorySecretStore();
  final writable = Completer<void>();

  @override
  Future<String?> read(String instanceId, String key) =>
      _values.read(instanceId, key);

  @override
  Future<void> write(String instanceId, String key, String value) async {
    await writable.future;
    await _values.write(instanceId, key, value);
  }

  @override
  Future<void> delete(String instanceId) => _values.delete(instanceId);
}

final class _DashboardHermes {
  final db = openMemoryDatabase();
  final secrets = _ControlledKeyring();
  final authenticated = Completer<void>();
  final logins = <Uri>[];
  Completer<void>? statusRelease;
  var unreachable = false;
  String? savedId;

  Future<void> pump(WidgetTester tester, {bool settle = true}) async {
    tester.view
      ..physicalSize = const Size(900, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
          httpClientProvider.overrideWithValue(
            MockClient((request) async {
              await statusRelease?.future;
              if (unreachable) throw http.ClientException('Connection refused');
              return http.Response(
                jsonEncode({
                  'version': '0.21.5',
                  'auth_required': true,
                  'auth_providers': ['basic'],
                  'auth_flows': ['cookie'],
                }),
                200,
              );
            }),
          ),
          trialConnectProvider.overrideWithValue((instance, trial) async {
            logins.add(instance.baseUrl);
            if (await trial.read(instance.id, SecretKeys.username) != 'admin' ||
                await trial.read(instance.id, SecretKeys.password) !=
                    _dashboardPassword) {
              throw const HermesAuthFailed('Incorrect dashboard credentials');
            }
            await authenticated.future;
          }),
        ],
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: YsTheme(
              palette: YsPalette.dark,
              child: Overlay.wrap(
                child: AddInstanceScreen(
                  initialUrl: _dashboardUrl,
                  initialUsername: 'admin',
                  initialPassword: _dashboardPassword,
                  autoProbe: true,
                  onDone: (id) => savedId = id,
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}
