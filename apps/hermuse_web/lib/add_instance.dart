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

/// "Add a Hermes": URL → relay resolve → status probe → credentials → real
/// connect test → save (desktop `AddInstanceScreen` parity).
///
/// Every step runs against the same-origin relay (`<relay>/relay/resolve`
/// then `<relay>/hermes/<id>/…`); nothing ever talks to the typed URL
/// directly. The check is the main action until a Hermes answers: its
/// drawing loops while it runs, a box ticks with sparks when a Hermes
/// answers and the sign-in fields come in; when none answers the drawing
/// shows a pulled plug and the check offers to try again. On success the
/// secrets land in the tab-lifetime [SecretStore], the metadata in drift
/// via [registryProvider], and [onDone] receives the new instance id (the
/// shell opens its main chat).
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
    // A form: left-aligned, unlike the centred status cards.
    css('.hermuse-screen .hermuse-card.hermuse-add')
        .styles(alignItems: .stretch, gap: .all(YsSpace.md.px)),
    css('.hermuse-add', [
      css('.hermuse-add-check').styles(display: .flex),
      css('.hermuse-add-credentials').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(YsSpace.md.px),
      ),
    ]),
  ];
}

class _HermuseAddInstanceState extends State<HermuseAddInstance> {
  final _urlField = GlobalNodeKey<web.HTMLElement>();
  var _url = '';
  var _label = '';
  var _labelEdited = false;
  var _username = 'admin';
  var _password = '';
  var _token = '';
  var _busy = false;
  String? _error;
  HermesStatus? _status;
  String? _upstreamId;

  /// The address the running check reaches.
  Uri? _checking;

  /// The last check reached no usable Hermes: the drawing shows it
  /// unplugged and the check offers to try again.
  var _probeFailed = false;

  http.Client get _http => context.readProvider(httpClientProvider);
  Uri get _relay => context.readProvider(relayProvider).value!;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    // The address field has focus when the dialog opens.
    context.binding.addPostFrameCallback(() {
      final field = _urlField.currentNode?.querySelector('input');
      if (mounted) (field as web.HTMLElement?)?.focus();
    });
  }

  /// The typed address, when it is a usable http(s) one.
  Uri? get _parsedUrl {
    try {
      final url = normalizeBaseUrl(_url);
      return url.host.isNotEmpty &&
              (url.isScheme('http') || url.isScheme('https'))
          ? url
          : null;
    } on Object {
      return null;
    }
  }

  /// A new address drops what the check said about the previous one.
  void _urlChanged(String value) => setState(() {
    _url = value;
    if (_status != null) return;
    _error = null;
    _probeFailed = false;
  });

  void _failProbe(String message) => setState(() {
    _busy = false;
    _error = message;
    _probeFailed = true;
  });

  Future<void> _probe() async {
    if (_busy) return;
    final url = _parsedUrl;
    if (url == null) {
      setState(() => _error = 'Enter a valid http(s) URL');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _probeFailed = false;
      _status = null;
      _checking = url;
    });
    try {
      final resolved = await Relay.resolve(
        _http,
        _relay,
        _url.trim(),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (resolved == null) {
        _failProbe(
          'This Hermes is not registered on this relay. Ask the relay '
          'administrator to add it (POST /admin/upstreams).',
        );
        return;
      }
      final status = await HermesRestClient(
        _http,
        baseUrl: Relay.instanceBase(_relay, resolved.id),
      ).getStatus().timeout(const Duration(seconds: 15));
      checkSupportedVersion(status.version);
      if (!mounted) return;
      if (status.loginMethod == null) {
        _failProbe(
          'This Hermes needs a login the web app does not support '
          '(${status.authProviders.join(', ')}).',
        );
        return;
      }
      setState(() {
        _busy = false;
        _status = status;
        _upstreamId = resolved.id;
        if (!_labelEdited) {
          _label = resolved.label.isEmpty ? url.host : resolved.label;
        }
      });
    } on TimeoutException {
      if (mounted) _failProbe('The relay did not answer in time. Try again.');
    } on UnsupportedServerVersion catch (e) {
      if (mounted) _failProbe('${e.message}. This app targets Hermes 0.21.x.');
    } on HermesException catch (e) {
      if (mounted) _failProbe(e.message);
    } on Object catch (e) {
      if (mounted) _failProbe('Could not reach the relay ($e).');
    }
  }

  /// Connect-tests the candidate, then persists metadata + secrets.
  Future<void> _save() async {
    final status = _status;
    final upstreamId = _upstreamId;
    final login = status?.loginMethod;
    if (_busy || upstreamId == null || login == null) return;
    final label = _label.trim();
    if (label.isEmpty || label.length > HermesInstance.maxLabelLength) {
      setState(() => _error = 'Name must be 1–64 characters');
      return;
    }
    final loopback = login == AuthMethod.loopbackToken;
    final username = _username.trim();
    if (!loopback && username.isEmpty) {
      setState(() => _error = 'Enter the dashboard username');
      return;
    }
    final secret = loopback ? _token.trim() : _password;
    if (secret.isEmpty) {
      setState(
        () => _error = loopback
            ? 'Enter the session token'
            : 'Enter the dashboard password',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final candidate = HermesInstance(
      id: const Uuid().v4(),
      label: label,
      kind: InstanceKind.remote,
      baseUrl: Relay.instanceBase(_relay, upstreamId),
      auth: login,
    );
    final error = await _connect(
      candidate,
      loopback
          ? {SecretKeys.sessionToken: secret}
          : {SecretKeys.username: username, SecretKeys.password: secret},
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    // Drop secrets from the widget state the moment they are stored.
    setState(() {
      _password = '';
      _token = '';
    });
    component.onDone(candidate.id);
  }

  /// Registers [candidate] once [secrets] open a real connection: null when
  /// it is saved, else why it is not.
  ///
  /// Each failure returns its own message. A nullable message assigned in
  /// the catch clauses and tested after them was compiled by dart2js as set
  /// on success too (to the new id), so a saved instance never left the
  /// dialog.
  Future<String?> _connect(
    HermesInstance candidate,
    Map<String, String> secrets,
  ) async {
    try {
      // Proved on a real connection before anything is stored.
      await context.container
          .read(instanceAuthProvider)
          .add(candidate, secrets: secrets)
          .timeout(const Duration(seconds: 30));
      return null;
    } on TimeoutException {
      return 'The connection test timed out. Try again.';
    } on HermesAuthFailed {
      return candidate.auth == AuthMethod.loopbackToken
          ? 'Wrong session token.'
          : 'Wrong username or password.';
    } on HermesException catch (e) {
      return e.message;
    } on DuplicateInstance catch (e) {
      return e.field == 'label'
          ? 'That name is already used'
          : 'That Hermes is already registered';
    } on Object catch (e) {
      return '$e';
    }
  }

  @override
  Component build(BuildContext context) {
    final status = _status;
    final checking = _busy && status == null;
    final check = checking
        ? 'Checking…'
        : _probeFailed
        ? 'Try again'
        : 'Check';
    final onCheck = _busy || _parsedUrl == null
        ? null
        : () => unawaited(_probe());
    return div(classes: 'hermuse-screen', [
      div(classes: 'hermuse-card hermuse-card-narrow hermuse-add', [
        // Reaching out while a check or a connection runs, unplugged when
        // the check found no usable Hermes.
        HermuseDialogHead(
          art: _probeFailed ? YsArt.unreachable : YsArt.remote,
          busy: _busy,
          title: 'Add a Hermes',
          helper: 'Paste the web address of your Hermes dashboard.',
          trailing: YsButton.icon(
            icon: YsIcon.close,
            label: 'Cancel',
            onPressed: component.onCancel,
          ),
        ),
        div(key: _urlField, [
          YsField(
            label: 'Instance URL',
            child: YsInputBox(
              value: _url,
              onChanged: _urlChanged,
              onSubmitted: () => unawaited(_probe()),
              placeholder: 'https://hermes.example.com',
              name: 'hermes-url',
              label: 'Instance URL',
              url: true,
              icon: YsIcon.link,
              autocomplete: 'url',
            ),
          ),
        ]),
        div(classes: 'hermuse-add-check', [
          // The step's main action until a Hermes answers.
          if (status == null)
            YsButton.primary(label: check, onPressed: onCheck)
          else
            YsButton.neutral(label: check, onPressed: onCheck),
        ]),
        if (checking || status != null)
          HermuseCheckLine(
            done: status != null,
            text: switch (status) {
              null => 'Looking for Hermes at ${_checking?.authority ?? ''}…',
              HermesStatus(
                loginMethod: AuthMethod.loopbackToken,
                :final version,
              ) =>
                'Hermes $version · paste its session token '
                    '(HERMES_DASHBOARD_SESSION_TOKEN).',
              HermesStatus(:final version) =>
                'Hermes $version · sign in with your dashboard account.',
            },
          ),
        if (status != null) _credentials(status),
        if (_error case final error?) HermuseErrorNotice(error),
      ]),
    ]);
  }

  /// The sign-in fields and the save, once the check found a Hermes; they
  /// come in with the page motion.
  Component _credentials(HermesStatus status) {
    void submit() => unawaited(_save());
    return div(classes: 'hermuse-add-credentials ys-enter', [
      YsField(
        label: 'Name',
        child: YsInputBox(
          value: _label,
          onChanged: (v) => setState(() {
            _label = v;
            _labelEdited = true;
          }),
          onSubmitted: submit,
          placeholder: status.version,
          name: 'hermes-name',
          label: 'Instance name',
          icon: YsIcon.pencil,
          autocomplete: 'off',
        ),
      ),
      if (status.loginMethod == AuthMethod.loopbackToken)
        YsField(
          label: 'Session token',
          child: YsInputBox(
            value: _token,
            onChanged: (v) => setState(() => _token = v),
            onSubmitted: submit,
            placeholder: '••••••••',
            name: 'hermes-token',
            label: 'Session token',
            obscure: true,
            icon: YsIcon.keyRound,
            autocomplete: 'off',
          ),
        )
      else ...[
        YsField(
          label: 'Username',
          child: YsInputBox(
            value: _username,
            onChanged: (v) => setState(() => _username = v),
            onSubmitted: submit,
            placeholder: 'Dashboard username',
            name: 'hermes-username',
            label: 'Username',
            icon: YsIcon.user,
            autocomplete: 'username',
          ),
        ),
        YsField(
          label: 'Password',
          child: YsInputBox(
            value: _password,
            onChanged: (v) => setState(() => _password = v),
            onSubmitted: submit,
            placeholder: '••••••••',
            name: 'hermes-password',
            label: 'Password',
            obscure: true,
            icon: YsIcon.lock,
            autocomplete: 'current-password',
          ),
        ),
      ],
      div(classes: 'hermuse-card-cta', [
        YsButton.primary(
          label: _busy ? 'Connecting…' : 'Save and connect',
          onPressed: _busy ? null : submit,
        ),
      ]),
    ]);
  }
}
