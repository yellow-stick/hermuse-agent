import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

import 'dart:convert';

void main() {
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ProviderContainer container;
  late List<http.Request> restCalls;
  late Map<String, http.Response> restRoutes;

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    restCalls = [];
    restRoutes = {};
    final mock = MockClient((request) async {
      restCalls.add(request);
      return restRoutes['${request.method} ${request.url.path}'] ??
          http.Response('no route', 500);
    });
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider('vps').overrideWith(
          (ref) =>
              HermesRestClient(mock, baseUrl: Uri.parse('https://vps.example')),
        ),
      ],
    );
    final registry = await container.read(registryProvider.future);
    await registry.add(
      HermesInstance(
        id: 'vps',
        label: 'VPS',
        kind: InstanceKind.remote,
        baseUrl: Uri.parse('https://vps.example'),
        auth: AuthMethod.password,
      ),
    );
    // Default: nothing configured, no free tier — the onboarding entry.
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': false,
          'ready': true,
          'free_tier': false,
          'other_providers': false,
          'inference_provider': '',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => {'ok': false, 'error': 'No Hermes provider is configured.'},
      )
      ..on(
        'free_tier.status',
        (_) => {
          'has_guest': false,
          'enabled': false,
          'available': false,
          'notice_pending': false,
          'model': 'nous/welcome',
          'label': 'Nous · free tier',
        },
      );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<OnboardingState> onboarding() =>
      container.read(onboardingProvider('vps').future);

  test('unconfigured instance starts at the connections step', () async {
    final state = await onboarding();
    expect(state.step, OnboardingStep.connections);
    expect(state.providerConfigured, isFalse);
  });

  test('configured-but-unservable instance shows runtime problems', () async {
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': true,
          'ready': true,
          'free_tier': false,
          'other_providers': true,
          'inference_provider': 'openai-api',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => {
          'ok': false,
          'provider': 'openai-api',
          'model': 'gpt-5',
          'source': 'env:OPENAI_API_KEY',
          'error': 'No usable credentials found for openai-api.',
        },
      );
    final state = await onboarding();
    expect(state.step, OnboardingStep.runtimeCheck);
    expect(state.problems, hasLength(1));
    expect(state.problems.single.message, contains('No usable credentials'));
    expect(state.problems.single.fixHint, contains('openai-api'));
  });

  test('an instance that already serves its model opens at ready', () async {
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': true,
          'ready': true,
          'free_tier': false,
          'other_providers': true,
          'inference_provider': 'anthropic',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => {
          'ok': true,
          'provider': 'anthropic',
          'model': 'claude-opus-4-5-20251101',
          'source': 'env:ANTHROPIC_API_KEY',
          'free_tier': false,
        },
      );
    final state = await onboarding();
    expect(state.step, OnboardingStep.ready);
    expect(state.providerConfigured, isTrue);
    expect(state.problems, isEmpty);
  });

  test('setup.ready re-probes and moves the step', () async {
    var configured = false;
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': configured,
          'ready': true,
          'free_tier': false,
          'other_providers': configured,
          'inference_provider': configured ? 'anthropic' : '',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => configured
            ? {
                'ok': true,
                'provider': 'anthropic',
                'model': 'm',
                'source': 'env:K',
                'free_tier': false,
              }
            : {'ok': false, 'error': 'No Hermes provider is configured.'},
      );
    expect((await onboarding()).step, OnboardingStep.connections);
    configured = true;
    fake.emitFrame({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': 'setup.ready',
        'payload': {
          'provider_configured': true,
          'inference_provider': 'anthropic',
          'free_tier': false,
          'has_identity': false,
          'other_providers': true,
          'finished_at': 1.0,
        },
      },
    });
    final moved = Completer<void>();
    container.listen(onboardingProvider('vps'), (_, next) {
      if (next.value?.step == OnboardingStep.defaultModel &&
          !moved.isCompleted) {
        moved.complete();
      }
    });
    await moved.future.timeout(const Duration(seconds: 10));
  });

  test('free-tier provision failure keeps the failure detail', () async {
    fake
      ..on(
        'free_tier.status',
        (_) => {
          'has_guest': false,
          'enabled': true,
          'available': false,
          'notice_pending': false,
          'model': 'nous/welcome',
          'label': 'Nous · free tier',
        },
      )
      ..on(
        'free_tier.provision',
        (_) => {'has_guest': false, 'enabled': true, 'error': 'portal down'},
      );
    final state = await onboarding();
    expect(state.freeTier?.enabled, isTrue);
    expect(state.freeTier?.available, isFalse);
    final notifier = container.read(onboardingProvider('vps').notifier);
    expect(await notifier.provisionFreeTier(), isFalse);
  });

  test('chooseModel posts the assignment and ack clears the notice', () async {
    // A fresh instance: no provider until the connections step is done.
    var configured = false;
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': configured,
          'ready': true,
          'free_tier': false,
          'other_providers': configured,
          'inference_provider': configured ? 'anthropic' : '',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => {
          'ok': true,
          'provider': 'anthropic',
          'model': 'm',
          'source': 's',
          'free_tier': false,
        },
      )
      ..on(
        'free_tier.status',
        (_) => {
          'has_guest': true,
          'enabled': true,
          'available': true,
          'notice_pending': true,
          'model': 'nous/welcome',
          'label': 'Nous · free tier',
        },
      )
      ..on('free_tier.ack_notice', (_) => {'acked': true})
      ..on(
        'model.options',
        (_) => {
          'providers': [
            {
              'slug': 'anthropic',
              'name': 'Anthropic',
              'authenticated': true,
              'models': ['m'],
            },
          ],
          'model': 'm',
          'provider': 'anthropic',
        },
      );
    restRoutes['POST /api/model/set'] = http.Response(
      jsonEncode({'ok': true, 'scope': 'main'}),
      200,
    );
    expect((await onboarding()).step, OnboardingStep.connections);
    final notifier = container.read(onboardingProvider('vps').notifier);
    configured = true;
    await notifier.refresh();
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.defaultModel,
    );
    // Loading the picker inventory must not advance the step.
    await notifier.loadModelOptions();
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.defaultModel,
    );
    await notifier.chooseModel(provider: 'anthropic', model: 'm');
    expect(restCalls.single.url.path, '/api/model/set');
    expect(
      jsonDecode(restCalls.single.body) as Map<String, Object?>,
      containsPair('scope', 'main'),
    );
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.profile,
    );

    restRoutes['POST /api/model/set'] = http.Response(
      jsonEncode({
        'ok': false,
        'scope': 'main',
        'confirm_required': true,
        'confirm_message': 'That one costs real money.',
      }),
      200,
    );
    // A ready instance can re-open the model step, then confirm a pricey one.
    notifier.skip(); // profile → ready
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.ready,
    );
    notifier.revisit(OnboardingStep.defaultModel);
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.defaultModel,
    );
    await expectLater(
      container
          .read(onboardingProvider('vps').notifier)
          .chooseModel(provider: 'anthropic', model: 'm'),
      throwsA(
        isA<ExpensiveModelConfirmation>().having(
          (e) => e.message,
          'message',
          'That one costs real money.',
        ),
      ),
    );

    expect(
      await container
          .read(onboardingProvider('vps').notifier)
          .ackFreeTierNotice(),
      isTrue,
    );
    expect(
      container.read(onboardingProvider('vps')).value?.freeTier?.noticePending,
      isFalse,
    );
  });

  test('profile conversation adopts the existing guide chat', () async {
    fake
      ..on(
        'setup.status',
        (params) => params['profile'] == 'hermes-setup'
            ? {
                'provider_configured': true,
                'ready': true,
                'free_tier': false,
                'other_providers': true,
                'inference_provider': 'anthropic',
              }
            : {
                'provider_configured': true,
                'ready': true,
                'free_tier': false,
                'other_providers': true,
                'inference_provider': 'anthropic',
              },
      )
      ..on(
        'setup.runtime_check',
        (_) => {
          'ok': true,
          'provider': 'anthropic',
          'model': 'm',
          'source': 's',
          'free_tier': false,
        },
      )
      ..on(
        'onboarding.ensure_setup_profile',
        (_) => {
          'name': 'hermes-setup',
          'path': '/tmp/hermes-setup',
          'created': false,
          'role': 'setup',
        },
      )
      ..on(
        'session.list',
        (_) => {
          'sessions': [
            {
              'id': 'guide-stored',
              'title': 'Welcome to Hermes',
              'preview': '',
              'started_at': 1.0,
              'message_count': 2,
              'source': 'hermuse',
            },
          ],
        },
      );
    await onboarding();
    final thread = await container
        .read(onboardingProvider('vps').notifier)
        .startProfileConversation();
    expect(thread.instanceId, 'vps');
    expect(thread.sessionId, 'guide-stored');
    expect(
      container.read(onboardingProvider('vps')).value?.step,
      OnboardingStep.ready,
    );
    // The guide lookup went to the setup profile, by exact title.
    final list = fake.calls.where((c) => c.method == 'session.list').single;
    expect(list.params['profile'], 'hermes-setup');
    expect(list.params['title'], 'Welcome to Hermes');
  });
}
