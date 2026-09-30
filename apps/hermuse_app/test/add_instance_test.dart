import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';

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
  });
}
