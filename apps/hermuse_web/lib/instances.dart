import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart' hide ConnectionState;
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
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

/// Registered instances, one row each: its state, its chat, its model
/// accounts and components; rename, default, setup again and removal in the
/// row's "More actions" menu (desktop `InstancesScreen` parity).
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

  /// Runs the onboarding again: the Hermes check, the default model.
  final ValueChanged<String> onSetup;

  /// Opens the component checklist of an instance: what Hermuse needs on
  /// its Hermes.
  final ValueChanged<String> onComponents;

  /// The model accounts the instance can use.
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
              state: state,
              // Refused credentials, on the first connection or on a later
              // reconnect (the chat's sign-in banner reads the same).
              authFailed:
                  connection.error is HermesAuthFailed ||
                  (state.value == ConnectionState.error &&
                      connection.value?.transport.lastError
                          is HermesAuthFailed),
              isDefault: registry.value?.primary?.id == instance.id,
              onOpen: () => onOpen(instance.id),
              onRename: (name) => _rename(context, instance, name),
              onMakeDefault: () => _setPrimary(context, instance),
              onRemove: () => _remove(context, instance),
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

  /// Forgets [instance] and its secrets; an open chat on it moves to what is
  /// left (desktop parity).
  Future<void> _remove(BuildContext context, HermesInstance instance) async {
    final container = context.container;
    final showing =
        container.read(activeThreadProvider).value?.instanceId == instance.id;
    final registry = await container.read(registryProvider.future);
    await registry.remove(instance.id);
    if (!showing) return;
    final next = registry.primary;
    if (next == null) {
      container.invalidate(activeThreadProvider);
    } else {
      await container.read(activeThreadProvider.notifier).openInstance(next.id);
    }
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
    // Outlined, so the neutral buttons and the monogram disc stay visible on
    // it (desktop `_InstanceRow`).
    css('.hermuse-instance-row').styles(
      padding: .all(YsSpace.md.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.md.px),
      border: .all(
        style: .solid,
        color: .variable('--line'),
        width: ysHairline.px,
      ),
    ),
    css('.hermuse-instance-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-instance-monogram').styles(
      width: YsLayout.monogram.px,
      height: YsLayout.monogram.px,
      radius: .circular(YsRadius.pill.px),
      display: .flex,
      justifyContent: .center,
      alignItems: .center,
      color: .variable('--content'),
      backgroundColor: .variable('--neutral-ambient'),
      fontSize: YsType.monogram.size.px,
      fontWeight: .w600,
      lineHeight: YsType.monogram.lineHeight.px,
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-instance-body').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      raw: {'min-width': '0'},
    ),
    css('.hermuse-instance-name').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
      raw: {'min-width': '0'},
    ),
    css('.hermuse-instance-label').styles(
      fontSize: YsType.label.size.px,
      lineHeight: YsType.label.lineHeight.px,
      fontWeight: .w500,
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap', 'min-width': '0'},
    ),
    css('.hermuse-instance-badge').styles(
      padding: .symmetric(vertical: YsSpace.xxs.px, horizontal: YsSpace.sm.px),
      radius: .circular(YsRadius.pill.px),
      color: .variable('--content-muted'),
      border: .all(
        style: .solid,
        color: .variable('--line'),
        width: ysHairline.px,
      ),
      fontSize: YsType.caption.size.px,
      lineHeight: YsType.caption.lineHeight.px,
      raw: {'white-space': 'nowrap', 'flex-shrink': '0'},
    ),
    css('.hermuse-instance-sub').styles(
      fontSize: YsType.caption.size.px,
      lineHeight: YsType.caption.lineHeight.px,
      color: .variable('--content-muted'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-instance-status').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all((YsSpace.xs + YsSpace.xxs).px),
      color: .variable('--content-muted'),
      fontSize: YsType.caption.size.px,
      lineHeight: YsType.caption.lineHeight.px,
      raw: {'white-space': 'nowrap', 'flex-shrink': '0'},
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
    css('.hermuse-instance-dot-error')
        .styles(backgroundColor: .variable('--error')),
    // The buttons wrap; "More actions" stays at the end of the first line.
    css('.hermuse-instance-actions').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-instance-buttons').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .row,
      flexWrap: .wrap,
      gap: .all(YsSpace.sm.px),
      raw: {'min-width': '0'},
    ),
    css('.hermuse-instance-more')
        .styles(display: .flex, raw: {'flex-shrink': '0'}),
    css(
      '.hermuse-instance-signin-col',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.sm.px)),
    css('.hermuse-instance-signin').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-instance-signin-field')
        .styles(flex: .grow(1), raw: {'min-width': '0'}),
    css('.hermuse-instance-dialog-body').styles(
      margin: .zero,
      fontSize: YsType.small.size.px,
      lineHeight: YsType.small.lineHeight.px,
    ),
  ];
}

class _InstanceRow extends StatefulComponent {
  const _InstanceRow({
    required this.instance,
    required this.state,
    required this.authFailed,
    required this.isDefault,
    required this.onOpen,
    required this.onRename,
    required this.onMakeDefault,
    required this.onRemove,
    required this.onSetup,
    required this.onComponents,
    required this.onConnections,
  });

  final HermesInstance instance;
  final AsyncValue<ConnectionState> state;

  /// True when the connection failed with auth (offer the sign-in).
  final bool authFailed;

  /// The instance Hermuse opens on start (the registry's primary).
  final bool isDefault;
  final VoidCallback onOpen;
  final ValueChanged<String> onRename;
  final VoidCallback onMakeDefault;
  final VoidCallback onRemove;
  final VoidCallback onSetup;
  final VoidCallback onComponents;
  final VoidCallback onConnections;

  @override
  State<_InstanceRow> createState() => _InstanceRowState();
}

class _InstanceRowState extends State<_InstanceRow> {
  final _nameBox = GlobalNodeKey<web.HTMLElement>();
  final _signInBox = GlobalNodeKey<web.HTMLElement>();
  final _more = GlobalNodeKey<web.HTMLElement>();

  /// Where the "More actions" menu opens; null while it is closed.
  YsMenuAnchor? _menu;
  var _renaming = false;
  var _draft = '';
  var _confirmRemove = false;
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
    final (dot, status) = _status();
    return div(classes: 'hermuse-instance-row', [
      div(classes: 'hermuse-instance-head', [
        span(
          classes: 'hermuse-instance-monogram',
          attributes: {'aria-hidden': 'true'},
          [.text(_initial(instance.label))],
        ),
        div(classes: 'hermuse-instance-body', [
          if (_renaming)
            div(key: _nameBox, [
              YsInputBox(
                value: _draft,
                onChanged: (v) => setState(() => _draft = v),
                onSubmitted: _saveName,
                name: 'instance-name-${instance.id}',
                label: 'Instance name',
                autocomplete: 'off',
              ),
            ])
          else
            div(classes: 'hermuse-instance-name', [
              span(classes: 'hermuse-instance-label', [.text(instance.label)]),
              if (component.isDefault)
                span(classes: 'hermuse-instance-badge', [.text('Default')]),
            ]),
          // Behind the relay the URL host is the relay itself: omit it.
          if (!instance.baseUrl.path.startsWith('/hermes/'))
            span(classes: 'hermuse-instance-sub', [
              .text(instance.baseUrl.toString()),
            ]),
        ]),
        div(classes: 'hermuse-instance-status', [
          YsPing(
            live: component.state.value == ConnectionState.ready,
            color: YsTheme.success,
            child: div(classes: dot, []),
          ),
          span([.text(status)]),
        ]),
      ]),
      // The sign-in's line: an empty box while it runs, ticked with
      // sparks once signed in; it stays until another action starts.
      if (_signCheck case final check?)
        HermuseCheckLine(
          key: const ValueKey('sign-in'),
          text: check,
          done: _signedIn,
        ),
      if (_signingIn)
        _signInForm()
      else if (_renaming)
        div(classes: 'hermuse-instance-buttons', [
          YsButton.primary(label: 'Save', onPressed: _saveName),
          YsButton.neutral(
            label: 'Cancel',
            onPressed: () => setState(() => _renaming = false),
          ),
        ])
      else
        _actions(),
      if (_menu case final at?) _moreMenu(at),
      if (_confirmRemove) _removeConfirmation(),
    ]);
  }

  static String _initial(String label) {
    final trimmed = label.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  /// The dot's classes and the state's words (desktop `InstanceStatusDot`).
  (String, String) _status() {
    const dot = 'hermuse-instance-dot';
    const idle = (dot, 'Idle');
    final failed = (
      '$dot hermuse-instance-dot-error',
      component.authFailed ? 'Signed out' : 'Error',
    );
    return switch (component.state) {
      AsyncData(:final value) => switch (value) {
        ConnectionState.ready => (
          '$dot hermuse-instance-dot-ready',
          'Connected',
        ),
        ConnectionState.connecting => (
          '$dot hermuse-instance-dot-busy',
          'Connecting…',
        ),
        ConnectionState.reconnecting => (
          '$dot hermuse-instance-dot-busy',
          'Reconnecting…',
        ),
        ConnectionState.error => failed,
        ConnectionState.disconnected => idle,
      },
      AsyncError() => failed,
      _ => idle,
    };
  }

  /// One main action (sign in when the saved sign-in was refused, else the
  /// chat), the model accounts and components, the rest in "More actions"
  /// (desktop `_InstanceRow` parity).
  Component _actions() {
    final instance = component.instance;
    final signIn = component.authFailed && instance.auth == AuthMethod.password;
    return div(classes: 'hermuse-instance-actions', [
      div(classes: 'hermuse-instance-buttons', [
        if (signIn)
          YsButton.primary(label: 'Sign in', onPressed: _startSignIn)
        else
          YsButton.primary(label: 'Open chat', onPressed: component.onOpen),
        YsButton.neutral(
          label: 'Model accounts',
          onPressed: component.onConnections,
        ),
        if (instance.kind == InstanceKind.remote)
          YsButton.neutral(
            label: 'Check components',
            onPressed: component.onComponents,
          ),
      ]),
      span(key: _more, classes: 'hermuse-instance-more', [
        YsButton.icon(
          icon: YsIcon.more,
          label: 'More actions for ${instance.label}',
          onPressed: _openMenu,
          attributes: {
            'aria-haspopup': 'menu',
            'aria-expanded': '${_menu != null}',
          },
        ),
      ]),
    ]);
  }

  void _openMenu() {
    final trigger = _more.currentNode;
    if (trigger == null) return;
    setState(() => _menu = YsMenuAnchor.of(trigger));
  }

  /// The row's other actions (desktop parity, without the SSH uninstall the
  /// web cannot run).
  Component _moreMenu(YsMenuAnchor at) => YsMenu(
    label: 'More actions for ${component.instance.label}',
    anchor: at,
    onClose: () => setState(() => _menu = null),
    items: [
      YsMenuItem(
        label: 'Rename',
        icon: YsIcon.pencil,
        onSelected: _startRename,
      ),
      if (!component.isDefault)
        YsMenuItem(
          label: 'Make default',
          icon: YsIcon.checkCircle,
          onSelected: component.onMakeDefault,
        ),
      YsMenuItem(
        label: 'Run setup again',
        icon: YsIcon.sparkles,
        onSelected: component.onSetup,
      ),
      YsMenuItem(
        label: 'Remove from Hermuse',
        icon: YsIcon.trash,
        destructive: true,
        onSelected: () => setState(() {
          _confirmRemove = true;
          _signCheck = null;
        }),
      ),
    ],
  );

  void _startRename() {
    setState(() {
      _draft = component.instance.label;
      _renaming = true;
      _signCheck = null;
    });
    _focusIn(_nameBox, select: true);
  }

  void _saveName() {
    component.onRename(_draft);
    setState(() => _renaming = false);
  }

  void _startSignIn() {
    setState(() {
      _signingIn = true;
      _signInError = null;
      _signCheck = null;
    });
    _focusIn(_signInBox);
  }

  /// Puts the keyboard in the first field inside [key] once it rendered.
  void _focusIn(GlobalNodeKey<web.HTMLElement> key, {bool select = false}) {
    if (!kIsWeb) return;
    context.binding.addPostFrameCallback(() {
      final field = key.currentNode?.querySelector('input');
      if (field == null) return;
      (field as web.HTMLElement).focus();
      if (select) (field as web.HTMLInputElement).select();
    });
  }

  /// The row's sign-in, in place of its actions.
  Component _signInForm() {
    final id = component.instance.id;
    void submit() => unawaited(_signIn());
    final ready = !_signInBusy && _username.isNotEmpty && _password.isNotEmpty;
    return div(key: _signInBox, classes: 'hermuse-instance-signin-col', [
      div(classes: 'hermuse-instance-signin', [
        div(classes: 'hermuse-instance-signin-field', [
          YsInputBox(
            value: _username,
            onChanged: (v) => setState(() => _username = v),
            onSubmitted: submit,
            placeholder: 'Username',
            name: 'row-username-$id',
            label: 'Username',
            icon: YsIcon.user,
            autocomplete: 'username',
          ),
        ]),
        div(classes: 'hermuse-instance-signin-field', [
          YsInputBox(
            value: _password,
            onChanged: (v) => setState(() => _password = v),
            onSubmitted: submit,
            placeholder: 'Password',
            name: 'row-password-$id',
            label: 'Password',
            obscure: true,
            icon: YsIcon.lock,
            autocomplete: 'current-password',
          ),
        ]),
      ]),
      if (_signInError case final message?) HermuseErrorNotice(message),
      div(classes: 'hermuse-instance-buttons', [
        YsButton.primary(
          label: _signInBusy ? 'Signing in…' : 'Sign in',
          onPressed: ready ? submit : null,
        ),
        YsButton.neutral(
          label: 'Cancel',
          onPressed: _signInBusy
              ? null
              : () => setState(() {
                  _signingIn = false;
                  _signInError = null;
                  _signCheck = null;
                }),
        ),
      ]),
    ]);
  }

  Future<void> _signIn() async {
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

  /// Asks before forgetting the instance: only this app's connection and
  /// sign-in go, the Hermes keeps everything (desktop parity).
  Component _removeConfirmation() {
    void close() => setState(() => _confirmRemove = false);
    return YsDialog(
      title: 'Remove “${component.instance.label}” from Hermuse?',
      onClose: close,
      actions: [
        YsButton.neutral(label: 'Cancel', onPressed: close),
        YsButton.destructive(
          label: 'Remove',
          onPressed: () {
            close();
            component.onRemove();
          },
        ),
      ],
      child: p(classes: 'hermuse-instance-dialog-body', [
        .text(
          'Hermuse forgets this connection and the sign-in saved for it in '
          'this app. Nothing is deleted on the server: Hermes, its chats and '
          'its data stay as they are.',
        ),
      ]),
    );
  }
}
