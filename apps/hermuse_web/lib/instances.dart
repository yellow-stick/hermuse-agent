import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart' hide ConnectionState;
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'mascot.dart';
import 'scope.dart';
import 'screens.dart';

/// Welcome screen: no instance is registered yet. The mascot says hello
/// above the one way to start on the web: connecting with a dashboard URL.
class HermuseWelcome extends StatelessComponent {
  const HermuseWelcome({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Component build(BuildContext context) =>
      div(classes: 'hermuse-screen hermuse-welcome-screen', [
        div(classes: 'hermuse-welcome ys-enter', [
          const HermuseMascot(),
          h1(classes: 'hermuse-welcome-title', [.text("Hi, I'm Hermuse")]),
          p(classes: 'hermuse-welcome-body', [
            .text('I run on your own Hermes Agent. Connect to start chatting.'),
          ]),
          div(classes: 'hermuse-welcome-choices', [
            YsChoiceCard(
              art: YsArt.remote,
              title: 'Connect to a machine',
              body: 'Enter the dashboard URL of a Hermes Agent already running on your machine or a server.',
              onPressed: onAdd,
            ),
          ]),
        ]),
      ]);

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    // Centred while it fits, scrolling from the top once it does not.
    css('.hermuse-screen.hermuse-welcome-screen').styles(
      alignItems: .start,
      overflow: .only(y: .auto, x: .hidden),
    ),
    css('.hermuse-welcome', [
      css('&').styles(
        width: 100.percent,
        maxWidth: YsLayout.listWidth.px,
        padding: .all(YsSpace.xl.px),
        margin: .all(.auto),
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        color: .variable('--content'),
        textAlign: .center,
      ),
      css('.hermuse-welcome-title').styles(
        margin: .fromLTRB(.zero, YsSpace.xl.px, .zero, .zero),
        fontSize: YsType.title.size.px,
        fontWeight: .w500,
        lineHeight: YsType.title.lineHeight.px,
      ),
      css('.hermuse-welcome-body').styles(
        margin: .fromLTRB(.zero, YsSpace.sm.px, .zero, .zero),
        color: .variable('--content-muted'),
        fontSize: YsType.body.size.px,
        lineHeight: YsType.body.lineHeight.px,
      ),
      css('.hermuse-welcome-choices').styles(
        width: 100.percent,
        margin: .only(top: YsSpace.xxl.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(YsSpace.md.px),
      ),
    ]),
  ];
}

/// Registered instances: state dot, version, rename, primary, the setup,
/// the components on the Hermes and its connections, delete.
class HermuseInstances extends StatelessComponent {
  const HermuseInstances({
    required this.onAdd,
    required this.onBack,
    required this.onOpen,
    required this.onSetup,
    required this.onComponents,
    required this.onConnections,
    super.key,
  });

  final VoidCallback onAdd;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onSetup;

  /// Opens the component checklist of an instance: what Hermuse needs on
  /// its Hermes.
  final ValueChanged<String> onComponents;
  final ValueChanged<String> onConnections;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: instancesProvider,
    builder: (context, instances) => HermuseWatch(
      provider: registryProvider,
      builder: (context, registry) =>
          _body(context, instances.value ?? const [], registry),
    ),
  );

  Component _body(
    BuildContext context,
    List<HermesInstance> instances,
    AsyncValue<HermesRegistry> registry,
  ) => div(classes: 'hermuse-screen hermuse-screen-top', [
    div(classes: 'hermuse-list-card', [
      HermuseDialogHead(
        art: YsArt.remote,
        title: 'Instances',
        helper: 'The Hermes you chat with and the state of each connection.',
        trailing: YsButton.icon(
          icon: YsIcon.close,
          label: 'Back to chat',
          onPressed: onBack,
          size: 36,
        ),
      ),
      for (final instance in instances)
        HermuseWatch(
          key: ValueKey(instance.id),
          provider: connectionStateProvider(instance.id),
          builder: (context, state) => HermuseWatch(
            provider: connectionProvider(instance.id),
            builder: (context, connection) => _InstanceRow(
              instance: instance,
              state: state.value,
              // Refused credentials, on the first connection or on a later
              // reconnect (the chat's sign-in banner reads the same).
              authFailed:
                  connection.error is HermesAuthFailed ||
                  (state.value == ConnectionState.error &&
                      connection.value?.transport.lastError
                          is HermesAuthFailed),
              isPrimary: registry.value?.primary?.id == instance.id,
              onOpen: () => onOpen(instance.id),
              onRename: (name) => _rename(context, instance, name),
              onSetPrimary: () => _setPrimary(context, instance),
              onDelete: () => _delete(context, instance),
              onSetup: () => onSetup(instance.id),
              onComponents: () => onComponents(instance.id),
              onConnections: () => onConnections(instance.id),
            ),
          ),
        ),
      div(classes: 'hermuse-card-actions', [
        YsButton.neutral(label: 'Add a Hermes', onPressed: onAdd),
      ]),
    ]),
  ]);

  Future<void> _rename(
    BuildContext context,
    HermesInstance instance,
    String label,
  ) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == instance.label) return;
    try {
      final registry = await context.container.read(registryProvider.future);
      await registry.update(instance.copyWith(label: trimmed));
    } on Object catch (_) {
      // Duplicate label: the row keeps its old name; the next sync shows it.
    }
  }

  Future<void> _setPrimary(
    BuildContext context,
    HermesInstance instance,
  ) async {
    final registry = await context.container.read(registryProvider.future);
    await registry.setPrimary(instance.id);
  }

  Future<void> _delete(BuildContext context, HermesInstance instance) async {
    final registry = await context.container.read(registryProvider.future);
    await registry.remove(instance.id);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    css('.hermuse-screen-top').styles(alignItems: .start),
    css('.hermuse-list-card').styles(
      width: 100.percent,
      maxWidth: YsLayout.listWidth.px,
      margin: .symmetric(horizontal: 24.px, vertical: 48.px),
      padding: .symmetric(vertical: 20.px, horizontal: 20.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(12.px),
      color: .variable('--content'),
      backgroundColor: .variable('--paper'),
    ),
    css('.hermuse-instance-body > .hermuse-check-line')
        .styles(margin: .only(top: YsSpace.sm.px)),
    css('.hermuse-instance-row').styles(
      padding: .symmetric(vertical: 12.px, horizontal: 12.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(12.px),
      // Outlined, so the neutral action buttons stay visible on it.
      border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
    ),
    css('.hermuse-instance-dot').styles(
      width: YsLayout.statusDot.px,
      height: YsLayout.statusDot.px,
      radius: .circular(YsRadius.pill.px),
      backgroundColor: .variable('--content-subtle'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-instance-dot-ready')
        .styles(backgroundColor: .variable('--success')),
    css('.hermuse-instance-dot-busy')
        .styles(backgroundColor: .variable('--primary')),
    css('.hermuse-instance-body').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      gap: .all(2.px),
      raw: {'min-width': '0'},
    ),
    css('.hermuse-instance-open').styles(
      padding: .zero,
      display: .flex,
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      border: .none,
      cursor: .pointer,
      textAlign: .left,
      raw: {'min-width': '0', 'font-family': 'inherit'},
    ),
    css('.hermuse-instance-label').styles(
      fontSize: 15.px,
      lineHeight: 20.px,
      fontWeight: .w600,
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-instance-sub').styles(
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-instance-actions').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(4.px),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-instance-edit').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-instance-input').styles(
      height: 36.px,
      padding: .symmetric(horizontal: 12.px),
      radius: .circular(YsRadius.row.px),
      flex: .grow(1),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
      fontSize: 15.px,
      raw: {'outline': 'none', 'font-family': 'inherit'},
    ),
    css('.hermuse-instance-signin').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
      margin: .only(top: 8.px),
    ),
    css('.hermuse-instance-signin-col')
        .styles(display: .flex, flexDirection: .column, gap: .all(8.px)),
    css('.hermuse-instance-signin .ys-inputbox')
        .styles(height: 36.px, fontSize: 14.px, lineHeight: 20.px),
    css('.hermuse-instance-signin-field')
        .styles(flex: .grow(1), raw: {'min-width': '0'}),
    css('.hermuse-instance-signin-link').styles(
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--primary-2'),
      cursor: .pointer,
      border: .none,
      backgroundColor: Colors.transparent,
      padding: .zero,
    ),
    // Phones: the actions leave the name its line and wrap under it,
    // right-aligned.
    css.media(MediaQuery.screen(maxWidth: 767.px), [
      css('.hermuse-instance-row').styles(flexWrap: .wrap),
      css('.hermuse-instance-actions')
          .styles(width: 100.percent, flexWrap: .wrap, justifyContent: .end),
    ]),
  ];
}

class _InstanceRow extends StatefulComponent {
  const _InstanceRow({
    required this.instance,
    required this.state,
    required this.authFailed,
    required this.isPrimary,
    required this.onOpen,
    required this.onRename,
    required this.onSetPrimary,
    required this.onDelete,
    required this.onSetup,
    required this.onComponents,
    required this.onConnections,
  });

  final HermesInstance instance;
  final ConnectionState? state;

  /// True when the connection failed with auth (show sign-in form).
  final bool authFailed;
  final bool isPrimary;
  final VoidCallback onOpen;
  final ValueChanged<String> onRename;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;
  final VoidCallback onSetup;
  final VoidCallback onComponents;
  final VoidCallback onConnections;
  @override
  State<_InstanceRow> createState() => _InstanceRowState();
}

class _InstanceRowState extends State<_InstanceRow> {
  var _editing = false;
  var _draft = '';
  var _confirmDelete = false;
  var _signingIn = false;
  var _username = '';
  var _password = '';
  var _signInBusy = false;
  String? _signInError;

  /// The sign-in under way or just done, as its check line says it; null
  /// once another action starts.
  String? _signCheck;
  var _signedIn = false;

  @override
  void initState() {
    super.initState();
    _draft = component.instance.label;
  }

  @override
  Component build(BuildContext context) {
    final instance = component.instance;
    final dot = switch (component.state) {
      ConnectionState.ready =>
        'hermuse-instance-dot hermuse-instance-dot-ready',
      ConnectionState.connecting || ConnectionState.reconnecting =>
        'hermuse-instance-dot hermuse-instance-dot-busy',
      _ => 'hermuse-instance-dot',
    };
    return div(classes: 'hermuse-instance-row', [
      YsPing(
        live: component.state == ConnectionState.ready,
        color: YsTheme.success,
        child: div(classes: dot, []),
      ),
      div(classes: 'hermuse-instance-body', [
        if (_editing)
          div(classes: 'hermuse-instance-edit', [
            input<String>(
              type: .text,
              value: _draft,
              classes: 'hermuse-instance-input',
              attributes: {'aria-label': 'Instance name'},
              onInput: (v) => setState(() => _draft = v),
            ),
            YsButton.icon(
              icon: YsIcon.check,
              label: 'Save name',
              onPressed: () {
                component.onRename(_draft);
                setState(() => _editing = false);
              },
              size: 32,
            ),
          ])
        else
          YsPressable(
            onPressed: component.onOpen,
            label: 'Open ${instance.label}',
            classes: 'hermuse-instance-open',
            builder: (context, press) => span(
              classes: 'hermuse-instance-label',
              [.text(instance.label)],
            ),
          ),
        span(classes: 'hermuse-instance-sub', [
          .text(
            [
              // Behind the relay the URL host is the relay itself: omit it.
              if (!instance.baseUrl.path.startsWith('/hermes/'))
                instance.baseUrl.host,
              if (component.isPrimary) 'primary',
              switch (component.state) {
                ConnectionState.ready => 'connected',
                ConnectionState.connecting => 'connecting…',
                ConnectionState.reconnecting => 'reconnecting…',
                ConnectionState.error =>
                  component.authFailed ? 'signed out' : 'error',
                _ => 'idle',
              },
            ].join(' · '),
          ),
        ]),
        // The sign-in's line: an empty box while it runs, ticked with
        // sparks once signed in; it stays until another action starts.
        if (_signCheck case final check?)
          HermuseCheckLine(
            key: const ValueKey('sign-in'),
            text: check,
            done: _signedIn,
          ),
        if (component.authFailed && instance.auth == AuthMethod.password)
          _RowSignIn(
            instanceId: instance.id,
            expanded: _signingIn,
            username: _username,
            password: _password,
            busy: _signInBusy,
            error: _signInError,
            onToggle: () => setState(() {
              _signingIn = !_signingIn;
              _signInError = null;
              _signCheck = null;
            }),
            onUsername: (v) => setState(() => _username = v),
            onPassword: (v) => setState(() => _password = v),
            onSubmit: () => unawaited(_signIn(context)),
          ),
      ]),
      div(classes: 'hermuse-instance-actions', [
        if (_confirmDelete)
          YsButton.neutral(label: 'Delete?', onPressed: component.onDelete)
        else ...[
          YsButton.icon(
            icon: YsIcon.pencil,
            label: 'Rename',
            onPressed: () => setState(() {
              _draft = instance.label;
              _editing = !_editing;
              _signCheck = null;
            }),
            size: 32,
          ),
          if (!component.isPrimary)
            YsButton.icon(
              icon: YsIcon.checkCircle,
              label: 'Set as primary',
              onPressed: component.onSetPrimary,
              size: 32,
            ),
          YsButton.neutral(label: 'Setup', onPressed: component.onSetup),
          YsButton.neutral(
            label: 'Components',
            onPressed: component.onComponents,
          ),
          YsButton.neutral(
            label: 'Connections',
            onPressed: component.onConnections,
          ),
          YsButton.icon(
            icon: YsIcon.close,
            label: 'Delete',
            onPressed: () => setState(() {
              _confirmDelete = true;
              _signCheck = null;
            }),
            size: 32,
          ),
        ],
      ]),
    ]);
  }

  Future<void> _signIn(BuildContext context) async {
    if (_signInBusy || _username.isEmpty || _password.isEmpty) return;
    final username = _username;
    setState(() {
      _signInBusy = true;
      _signInError = null;
      _signCheck = 'Signing in as $username…';
      _signedIn = false;
    });
    try {
      await HermuseScope.container
          .read(instanceAuthProvider)
          .signIn(
            component.instance.id,
            username: username,
            password: _password,
          );
      if (mounted) {
        setState(() {
          _username = '';
          _password = '';
          _signingIn = false;
          _signCheck = 'Signed in as $username';
          _signedIn = true;
        });
      }
    } on HermesAuthFailed {
      if (mounted) _failSignIn('Wrong username or password.');
    } on Object catch (e) {
      if (mounted) _failSignIn('$e');
    }
    if (mounted) setState(() => _signInBusy = false);
  }

  void _failSignIn(String message) => setState(() {
    _signInError = message;
    _signCheck = null;
  });
}

/// Collapsed "Sign in" link expanding to an inline credential form.
class _RowSignIn extends StatelessComponent {
  const _RowSignIn({
    required this.instanceId,
    required this.expanded,
    required this.username,
    required this.password,
    required this.busy,
    required this.error,
    required this.onToggle,
    required this.onUsername,
    required this.onPassword,
    required this.onSubmit,
  });

  final String instanceId;
  final bool expanded;
  final String username;
  final String password;
  final bool busy;
  final String? error;
  final VoidCallback onToggle;
  final ValueChanged<String> onUsername;
  final ValueChanged<String> onPassword;
  final VoidCallback onSubmit;

  @override
  Component build(BuildContext context) {
    if (!expanded) {
      return YsPressable(
        onPressed: onToggle,
        label: 'Sign in again',
        classes: 'hermuse-instance-signin-link',
        builder: (context, press) => span([.text('Sign in again')]),
      );
    }
    return div(classes: 'hermuse-instance-signin-col', [
      div(classes: 'hermuse-instance-signin', [
        div(classes: 'hermuse-instance-signin-field', [
          YsInputBox(
            value: username,
            onChanged: onUsername,
            onSubmitted: onSubmit,
            placeholder: 'Username',
            name: 'row-username-$instanceId',
            label: 'Username',
            icon: YsIcon.user,
            autocomplete: 'username',
          ),
        ]),
        div(classes: 'hermuse-instance-signin-field', [
          YsInputBox(
            value: password,
            onChanged: onPassword,
            onSubmitted: onSubmit,
            placeholder: 'Password',
            name: 'row-password-$instanceId',
            label: 'Password',
            obscure: true,
            icon: YsIcon.lock,
            autocomplete: 'current-password',
          ),
        ]),
        YsButton.primary(
          label: busy ? 'Signing in…' : 'Sign in',
          onPressed: busy || username.isEmpty || password.isEmpty
              ? null
              : onSubmit,
        ),
      ]),
      if (error case final message?) HermuseErrorNotice(message),
    ]);
  }
}
