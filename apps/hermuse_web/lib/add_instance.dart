import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:universal_web/web.dart' as web;
import 'package:uuid/uuid.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'relay.dart';
import 'scope.dart';
import 'screens.dart';

/// "Add a Hermes" wizard: URL → relay resolve → status probe → credentials →
/// real connect test → save.
///
/// Every step runs against the same-origin relay (`<relay>/relay/resolve`
/// then `<relay>/hermes/<id>/…`); nothing ever talks to the typed URL
/// directly. On success the secrets land in the tab-lifetime [SecretStore],
/// the metadata in drift via [registryProvider], and [onDone] receives the
/// new instance id (the shell opens its main chat).
class HermuseAddInstance extends StatefulComponent {
  const HermuseAddInstance({
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<HermuseAddInstance> createState() => _HermuseAddInstanceState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    css('.hermuse-field').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .column,
      gap: .all(6.px),
    ),
    css('.hermuse-field-label').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-field-input').styles(
      height: 44.px,
      padding: .symmetric(horizontal: 14.px),
      radius: .circular(YsRadius.row.px),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
      fontSize: 15.px,
      raw: {'outline': 'none', 'font-family': 'inherit'},
    ),
    css('.hermuse-field-input:focus').styles(
      border: .all(style: .solid, color: .variable('--primary'), width: 1.2.px),
    ),
    css('.hermuse-field-input::placeholder')
        .styles(color: .variable('--content-subtle')),
  ];
}

enum _Step { url, credentials, saving }

class _HermuseAddInstanceState extends State<HermuseAddInstance> {
  var _step = _Step.url;
  var _url = '';
  var _label = '';
  var _username = '';
  var _password = '';
  var _token = '';
  var _busy = false;
  String? _error;
  HermesStatus? _status;
  String? _upstreamId;

  http.Client get _http => context.readProvider(httpClientProvider);
  Uri get _relay => context.readProvider(relayProvider).value!;

  Future<void> _resolve() async {
    final url = _url.trim();
    if (url.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resolved = await Relay.resolve(
        _http,
        _relay,
        url,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (resolved == null) {
        setState(() {
          _busy = false;
          _error =
              'This Hermes is not registered on this relay. Ask the relay '
              'administrator to add it (POST /admin/upstreams).';
        });
        return;
      }
      final base = Relay.instanceBase(_relay, resolved.id);
      final status = await HermesRestClient(
        _http,
        baseUrl: base,
      ).getStatus().timeout(const Duration(seconds: 15));
      checkSupportedVersion(status.version);
      if (!mounted) return;
      if (status.authRequired && !status.authProviders.contains('basic')) {
        setState(() {
          _busy = false;
          _error =
              'This Hermes needs a login the web app does not support '
              '(${status.authProviders.join(', ')}).';
        });
        return;
      }
      setState(() {
        _busy = false;
        _status = status;
        _upstreamId = resolved.id;
        if (_label.trim().isEmpty) _label = resolved.label;
        // Gateless (loopback-token) instances ask for the session token;
        // gated ones ask for username + password.
        _step = _Step.credentials;
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The relay did not answer in time. Try again.';
        });
      }
    } on UnsupportedServerVersion catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${e.message}. This app targets Hermes 0.21.x.';
        });
      }
    } on HermesException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not reach the relay ($e).';
        });
      }
    }
  }

  /// Connect-tests the candidate, then persists metadata + secrets.
  Future<void> _save({String? password, String? token}) async {
    if (_busy && _step == _Step.saving) return;
    setState(() {
      _busy = true;
      _error = null;
      _step = _Step.saving;
    });
    final loopback = token != null;
    final id = const Uuid().v4();
    final base = Relay.instanceBase(_relay, _upstreamId!);
    final candidate = HermesInstance(
      id: id,
      label: _label.trim().isEmpty ? base.host : _label.trim(),
      kind: InstanceKind.remote,
      baseUrl: base,
      auth: loopback ? AuthMethod.loopbackToken : AuthMethod.password,
    );
    final secrets = context.readProvider(secretStoreProvider);
    // Validate before persisting: a temporary store proves the credentials
    // against a real transport; only then is anything written.
    final trial = MemorySecretStore();
    if (password != null) {
      await trial.write(id, SecretKeys.username, _username.trim());
      await trial.write(id, SecretKeys.password, password);
    }
    if (token != null) {
      await trial.write(id, SecretKeys.sessionToken, token);
    }
    try {
      final transport = await DashboardTransport.connect(
        instance: candidate,
        secrets: trial,
        httpClient: _http,
      ).timeout(const Duration(seconds: 30));
      await transport.close();
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.credentials;
          _error = 'The connection test timed out. Try again.';
        });
      }
      return;
    } on HermesAuthFailed {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.credentials;
          _error = loopback
              ? 'Wrong session token.'
              : 'Wrong username or password.';
        });
      }
      return;
    } on HermesException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.credentials;
          _error = e.message;
        });
      }
      return;
    }
    if (!mounted) return;
    try {
      // Registry first: writing secrets beforehand would orphan them under
      // the new id when the add fails (e.g. DuplicateInstance).
      final registry = await context.container.read(registryProvider.future);
      await registry.add(candidate);
      if (password != null) {
        await secrets.write(id, SecretKeys.username, _username.trim());
        await secrets.write(id, SecretKeys.password, password);
      }
      if (token != null) {
        await secrets.write(id, SecretKeys.sessionToken, token);
      }
    } on DuplicateInstance catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.url;
          _error = 'Already registered: ${e.value}.';
        });
      }
      return;
    }
    // Drop secrets from the widget state the moment they are stored.
    setState(() {
      _password = '';
      _token = '';
    });
    component.onDone(id);
  }

  bool get _loopback => _status != null && !_status!.authRequired;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-screen', [
    div(classes: 'hermuse-card hermuse-card-narrow', [
      h1(classes: 'hermuse-card-title', [.text('Add a Hermes')]),
      if (_step == _Step.url) ...[
        p(classes: 'hermuse-card-body', [
          .text('Enter the address of your Hermes instance.'),
        ]),
        _field(
          label: 'Hermes URL',
          value: _url,
          placeholder: 'https://hermes.example.com',
          type: InputType.url,
          onChanged: (v) => setState(() => _url = v),
          onSubmitted: _resolve,
        ),
        _field(
          label: 'Name (optional)',
          value: _label,
          placeholder: 'Home server',
          onChanged: (v) => setState(() => _label = v),
          onSubmitted: _resolve,
        ),
      ] else if (_loopback) ...[
        p(classes: 'hermuse-card-body', [
          .text(
            'Hermes ${_status?.version ?? ''} · paste its session token '
            '(HERMES_DASHBOARD_SESSION_TOKEN).',
          ),
        ]),
        _field(
          label: 'Session token',
          value: _token,
          placeholder: '••••••••',
          type: InputType.password,
          onChanged: (v) => setState(() => _token = v),
          onSubmitted: _submitToken,
        ),
      ] else ...[
        p(classes: 'hermuse-card-body', [
          .text(
            'Hermes ${_status?.version ?? ''} · sign in with your dashboard account.',
          ),
        ]),
        _field(
          label: 'Username',
          value: _username,
          placeholder: 'admin',
          onChanged: (v) => setState(() => _username = v),
          onSubmitted: _submitCredentials,
        ),
        _field(
          label: 'Password',
          value: _password,
          placeholder: '••••••••',
          type: InputType.password,
          onChanged: (v) => setState(() => _password = v),
          onSubmitted: _submitCredentials,
        ),
      ],
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
      if (_busy)
        p(classes: 'hermuse-card-body', [
          .text(
            _step == _Step.saving ? 'Testing the connection…' : 'Checking…',
          ),
        ]),
      div(classes: 'hermuse-card-actions', [
        YsButton.neutral(
          label: 'Cancel',
          onPressed: _busy ? null : component.onCancel,
        ),
        if (_step == _Step.url)
          YsButton.primary(
            label: 'Continue',
            onPressed: _busy || _url.trim().isEmpty ? null : _resolve,
          )
        else if (_loopback)
          YsButton.primary(
            label: 'Add',
            onPressed: _busy || _token.isEmpty ? null : _submitToken,
          )
        else
          YsButton.primary(
            label: 'Add',
            onPressed: _busy || _username.trim().isEmpty || _password.isEmpty
                ? null
                : _submitCredentials,
          ),
      ]),
    ]),
  ]);

  void _submitCredentials() {
    final password = _password;
    if (password.isEmpty || _username.trim().isEmpty) return;
    unawaited(_save(password: password));
  }

  void _submitToken() {
    final token = _token;
    if (token.isEmpty) return;
    unawaited(_save(token: token));
  }

  Component _field({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    required VoidCallback onSubmitted,
    String? placeholder,
    InputType type = .text,
  }) => div(classes: 'hermuse-field', [
    span(classes: 'hermuse-field-label', [.text(label)]),
    input<String>(
      type: type,
      value: value,
      classes: 'hermuse-field-input',
      attributes: {
        'placeholder': ?placeholder,
        'aria-label': label,
        if (type == .password) 'autocomplete': 'current-password',
      },
      onInput: onChanged,
      events: {
        'keydown': (event) {
          if ((event as web.KeyboardEvent).key == 'Enter') {
            event.preventDefault();
            onSubmitted();
          }
        },
      },
    ),
  ]);
}
