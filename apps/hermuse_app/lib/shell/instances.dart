import 'dart:async';

import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:uuid/uuid.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'screens.dart';

/// One-line state dot + label of an instance's connection; [signedOut] names
/// a failure that is the saved sign-in being refused.
final class InstanceStatusDot extends ConsumerWidget {
  const InstanceStatusDot(this.instanceId, {this.signedOut = false, super.key});

  final String instanceId;
  final bool signedOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final state = ref.watch(connectionStateProvider(instanceId));
    final failed = (palette.errorColor, signedOut ? 'Signed out' : 'Error');
    final (color, label) = switch (state) {
      AsyncData(:final value) => switch (value) {
        ConnectionState.ready => (palette.successColor, 'Connected'),
        ConnectionState.connecting => (palette.primaryColor, 'Connecting…'),
        ConnectionState.reconnecting => (palette.primaryColor, 'Reconnecting…'),
        ConnectionState.error => failed,
        ConnectionState.disconnected => (palette.contentSubtleColor, 'Idle'),
      },
      AsyncError() => failed,
      _ => (palette.contentSubtleColor, 'Idle'),
    };
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          YsPing(
            live: color == palette.successColor,
            color: color,
            child: SizedBox(
              width: YsLayout.statusDot,
              height: YsLayout.statusDot,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The registered Hermes instances, one row each: its chat, its model
/// accounts and components, everything else in the row's "More actions"
/// menu.
final class InstancesScreen extends ConsumerWidget {
  const InstancesScreen({
    required this.onAdd,
    required this.onClose,
    required this.onOpen,
    required this.onSetup,
    required this.onComponents,
    required this.onConnections,
    this.addOverSsh = false,
    this.onInstall,
    this.onRemoveFromServer,
    super.key,
  });

  final VoidCallback onAdd;

  /// Desktop: [onAdd] opens the SSH setup ("Connect to a machine", as on the
  /// welcome screen); elsewhere the dashboard URL form ("Add a Hermes").
  final bool addOverSsh;

  /// Desktop without a local instance: install/adopt Hermes here.
  final VoidCallback? onInstall;
  final VoidCallback onClose;

  /// Opens the instance's main chat, leaving this screen.
  final ValueChanged<String> onOpen;

  /// Runs the onboarding wizard again: the Hermes check, the default model.
  final ValueChanged<String> onSetup;

  /// What Hermuse needs on a remote instance, and its installs.
  final ValueChanged<String> onComponents;

  /// The model accounts the instance can use.
  final ValueChanged<String> onConnections;

  /// Desktop only: uninstalls Hermes from a remote instance's server.
  final ValueChanged<String>? onRemoveFromServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final instances = ref.watch(instancesProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: YsLayout.listWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperColor,
            borderRadius: BorderRadius.circular(YsRadius.bubble),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YsDialogHead(
                  art: YsArt.remote,
                  title: 'Hermes instances',
                  helper:
                      'The Hermes you chat with and the state of each '
                      'connection.',
                  trailing: YsButton.icon(
                    icon: YsIcon.close,
                    onPressed: onClose,
                    semanticLabel: 'Close instances',
                    tooltip: 'Close',
                  ),
                ),
                const SizedBox(height: 12),
                _instancesBody(context, ref, instances),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // Neutral: each row's "Open chat" is the accent.
                    YsButton.neutral(
                      label: addOverSsh
                          ? 'Connect to a machine'
                          : 'Add a Hermes',
                      icon: YsIcon.plus,
                      onPressed: onAdd,
                    ),
                    if (onInstall case final install?)
                      YsButton.neutral(
                        label: 'Install Hermes on this computer',
                        onPressed: install,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _instancesBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<HermesInstance>> instances,
  ) {
    final palette = YsTheme.of(context);
    final list = instances.value;
    if (list != null) {
      if (list.isEmpty) {
        return Text(
          'No instances yet. Add one to start chatting.',
          style: YsType.body.flutter.copyWith(color: palette.contentMutedColor),
        );
      }
      final defaultId = ref.watch(registryProvider).value?.primary?.id;
      return Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final instance in list) ...[
              _InstanceRow(
                key: ValueKey(instance.id),
                instance: instance,
                isDefault: instance.id == defaultId,
                onOpen: onOpen,
                onSetup: onSetup,
                onComponents: onComponents,
                onConnections: onConnections,
                onRemoveFromServer: onRemoveFromServer,
              ),
              const SizedBox(height: YsSpace.sm),
            ],
          ],
        ),
      );
    }
    if (instances.hasError) {
      return Text(
        'Could not load instances: ${instances.error}',
        style: YsType.body.flutter.copyWith(color: palette.errorColor),
      );
    }
    return const SizedBox(
      height: 48,
      child: Center(child: YsSpinner(size: 20)),
    );
  }
}

final class _InstanceRow extends ConsumerStatefulWidget {
  const _InstanceRow({
    required this.instance,
    required this.isDefault,
    required this.onOpen,
    required this.onSetup,
    required this.onComponents,
    required this.onConnections,
    this.onRemoveFromServer,
    super.key,
  });

  final HermesInstance instance;

  /// The instance Hermuse opens on start (the registry's primary).
  final bool isDefault;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onSetup;
  final ValueChanged<String> onComponents;
  final ValueChanged<String> onConnections;
  final ValueChanged<String>? onRemoveFromServer;

  @override
  ConsumerState<_InstanceRow> createState() => _InstanceRowState();
}

final class _InstanceRowState extends ConsumerState<_InstanceRow> {
  var _renaming = false;
  var _signingIn = false;
  final _removeDialog = OverlayPortalController();
  final _labelFocus = FocusNode();
  final _signUserFocus = FocusNode();
  late final TextEditingController _label;
  late final TextEditingController _signUser = TextEditingController();
  late final TextEditingController _signPassword = TextEditingController();
  var _signBusy = false;
  String? _error;

  /// The sign-in under way or just done, as its check line says it; null
  /// once another action starts.
  String? _signCheck;
  var _signedIn = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.instance.label);
  }

  @override
  void dispose() {
    _label.dispose();
    _signUser.dispose();
    _signPassword.dispose();
    _labelFocus.dispose();
    _signUserFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final username = _signUser.text.trim();
    final password = _signPassword.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _signBusy = true;
      _error = null;
      _signCheck = 'Signing in as $username…';
      _signedIn = false;
    });
    try {
      await ref
          .read(instanceAuthProvider)
          .signIn(widget.instance.id, username: username, password: password);
      if (mounted) {
        setState(() {
          _signingIn = false;
          _signCheck = 'Signed in as $username';
          _signedIn = true;
          _signUser.clear();
          _signPassword.clear();
        });
      }
    } on HermesException catch (e) {
      if (mounted) _failSignIn(e.message);
    } on Object catch (e) {
      if (mounted) _failSignIn('$e');
    } finally {
      if (mounted) setState(() => _signBusy = false);
    }
  }

  void _failSignIn(String message) => setState(() {
    _error = message;
    _signCheck = null;
  });

  /// Opens one of the row's forms, then puts the keyboard in its [focus]
  /// field; the last sign-in's line goes away.
  void _start(VoidCallback open, {FocusNode? focus}) {
    setState(() {
      _error = null;
      _signCheck = null;
      open();
    });
    if (focus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  Future<void> _rename() async {
    final label = _label.text.trim();
    if (label.isEmpty || label.length > HermesInstance.maxLabelLength) {
      setState(() => _error = 'Name must be 1–64 characters');
      return;
    }
    try {
      await (await ref.read(registryProvider.future))
          .update(widget.instance.copyWith(label: label));
      if (mounted) {
        setState(() {
          _renaming = false;
          _error = null;
        });
      }
    } on DuplicateInstance {
      if (mounted) setState(() => _error = 'That name is already used');
    }
  }

  Future<void> _makeDefault() async =>
      (await ref.read(registryProvider.future)).setPrimary(widget.instance.id);

  void _askRemove() {
    setState(() {
      _error = null;
      _signCheck = null;
    });
    _removeDialog.show();
  }

  /// Forgets the instance and its saved secrets; an open chat on it moves to
  /// what is left. The row goes away meanwhile, hence the container.
  Future<void> _remove() async {
    _removeDialog.hide();
    final id = widget.instance.id;
    final container = ProviderScope.containerOf(context, listen: false);
    final showing =
        container.read(activeThreadProvider).value?.instanceId == id;
    final registry = await container.read(registryProvider.future);
    try {
      await registry.remove(id);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not remove it: $e');
      return;
    }
    if (!showing) return;
    final next = registry.primary;
    if (next == null) {
      container.invalidate(activeThreadProvider);
    } else {
      await container.read(activeThreadProvider.notifier).openInstance(next.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final instance = widget.instance;
    final state = ref.watch(connectionStateProvider(instance.id));
    final connection = ref.watch(connectionProvider(instance.id));
    // Refused credentials, on the first connection or on a later reconnect
    // (the chat's sign-in banner reads the same).
    final signedOut =
        connection.error is HermesAuthFailed ||
        (state.value == ConnectionState.error &&
            connection.value?.transport.lastError is HermesAuthFailed);
    // Outlined, not filled: the neutral buttons and the monogram disc share
    // the neutral fill and would vanish on it (web `.hermuse-instance-row`).
    return OverlayPortal(
      controller: _removeDialog,
      overlayChildBuilder: _removeConfirmation,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YsRadius.row),
          border: Border.all(color: palette.lineColor, width: ysHairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _head(palette, signedOut: signedOut),
              // The sign-in's line: an empty box while it runs, ticked with
              // sparks once signed in; it stays until another action starts.
              if (_signCheck case final check?) ...[
                const SizedBox(height: YsSpace.sm),
                YsDialogCheck(
                  key: const ValueKey('sign-in'),
                  text: check,
                  done: _signedIn,
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: YsSpace.sm),
                YsDialogError(error),
              ],
              const SizedBox(height: YsSpace.md),
              if (_signingIn)
                ..._signInForm()
              else if (_renaming)
                _renameActions()
              else
                _actions(
                  signIn: signedOut && instance.auth == AuthMethod.password,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Monogram, name ("Default" beside the one opened on start), address and
  /// connection state; the name turns into its field while renaming.
  Widget _head(YsPalette palette, {required bool signedOut}) {
    final instance = widget.instance;
    return Row(
      children: [
        _Monogram(label: instance.label),
        const SizedBox(width: YsSpace.md),
        Expanded(
          child: _renaming
              ? YsInputBox(
                  controller: _label,
                  focusNode: _labelFocus,
                  semanticLabel: 'Instance name',
                  onSubmitted: (_) => _rename(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            instance.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YsType.label.flutter.copyWith(
                              color: palette.contentColor,
                            ),
                          ),
                        ),
                        if (widget.isDefault) ...[
                          const SizedBox(width: YsSpace.sm),
                          const _DefaultBadge(),
                        ],
                      ],
                    ),
                    Text(
                      instance.baseUrl.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YsType.caption.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: YsSpace.md),
        InstanceStatusDot(instance.id, signedOut: signedOut),
      ],
    );
  }

  /// One main action (sign in when the saved sign-in was refused, else the
  /// chat), the model accounts and components, the rest in "More actions".
  Widget _actions({required bool signIn}) {
    final instance = widget.instance;
    final more = 'More actions for ${instance.label}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: YsSpace.sm,
            runSpacing: YsSpace.sm,
            children: [
              if (signIn)
                YsButton.primary(
                  label: 'Sign in',
                  onPressed: () =>
                      _start(() => _signingIn = true, focus: _signUserFocus),
                )
              else
                YsButton.primary(
                  label: 'Open chat',
                  onPressed: () => widget.onOpen(instance.id),
                ),
              YsButton.neutral(
                label: 'Model accounts',
                onPressed: () => widget.onConnections(instance.id),
              ),
              if (instance.kind == InstanceKind.remote)
                YsButton.neutral(
                  label: 'Check components',
                  onPressed: () => widget.onComponents(instance.id),
                ),
            ],
          ),
        ),
        const SizedBox(width: YsSpace.sm),
        YsMenuAnchor(
          semanticLabel: more,
          items: [
            YsMenuItem(
              label: 'Rename',
              icon: YsIcon.pencil,
              onSelected: () => _start(() {
                _label.text = instance.label;
                _renaming = true;
              }, focus: _labelFocus),
            ),
            if (!widget.isDefault)
              YsMenuItem(
                label: 'Make default',
                icon: YsIcon.checkCircle,
                onSelected: () => unawaited(_makeDefault()),
              ),
            YsMenuItem(
              label: 'Run setup again',
              icon: YsIcon.sparkles,
              onSelected: () => widget.onSetup(instance.id),
            ),
            if (widget.onRemoveFromServer case final uninstall?
                when instance.kind == InstanceKind.remote)
              YsMenuItem(
                label: 'Uninstall from server…',
                icon: YsIcon.package,
                onSelected: () => uninstall(instance.id),
              ),
            YsMenuItem(
              label: 'Remove from Hermuse',
              icon: YsIcon.trash,
              destructive: true,
              onSelected: _askRemove,
            ),
          ],
          builder: (context, menu) => YsButton.icon(
            icon: YsIcon.more,
            onPressed: () => menu.open(),
            semanticLabel: more,
            tooltip: 'More actions',
            size: YsLayout.pillHeight,
          ),
        ),
      ],
    );
  }

  /// The row's sign-in, in place of its actions.
  List<Widget> _signInForm() => [
    YsInputBox(
      controller: _signUser,
      focusNode: _signUserFocus,
      placeholder: 'Username',
      semanticLabel: 'Username',
      icon: YsIcon.user,
      onSubmitted: (_) => _signIn(),
    ),
    const SizedBox(height: YsSpace.sm),
    YsInputBox(
      controller: _signPassword,
      placeholder: 'Password',
      semanticLabel: 'Password',
      icon: YsIcon.lock,
      obscure: true,
      onSubmitted: (_) => _signIn(),
    ),
    const SizedBox(height: YsSpace.sm),
    Row(
      children: [
        YsButton.primary(
          label: _signBusy ? 'Signing in…' : 'Sign in',
          onPressed: _signBusy ? null : _signIn,
        ),
        const SizedBox(width: YsSpace.sm),
        YsButton.neutral(
          label: 'Cancel',
          onPressed: _signBusy
              ? null
              : () => setState(() {
                  _signingIn = false;
                  _error = null;
                  _signCheck = null;
                }),
        ),
      ],
    ),
  ];

  Widget _renameActions() => Row(
    children: [
      YsButton.primary(label: 'Save', onPressed: _rename),
      const SizedBox(width: YsSpace.sm),
      YsButton.neutral(
        label: 'Cancel',
        onPressed: () => setState(() {
          _renaming = false;
          _error = null;
          _label.text = widget.instance.label;
        }),
      ),
    ],
  );

  /// Asks before forgetting the instance: only this app's connection and
  /// sign-in go, the Hermes keeps everything.
  Widget _removeConfirmation(BuildContext context) {
    final palette = YsTheme.of(context);
    final instance = widget.instance;
    final where = instance.kind == InstanceKind.local
        ? 'this computer'
        : 'the server';
    return YsDialog(
      title: 'Remove “${instance.label}” from Hermuse?',
      onClose: _removeDialog.hide,
      actions: [
        YsButton.neutral(label: 'Cancel', onPressed: _removeDialog.hide),
        YsButton.destructive(
          label: 'Remove',
          onPressed: () => unawaited(_remove()),
        ),
      ],
      child: Text(
        'Hermuse forgets this connection and the sign-in saved for it in '
        'this app. Nothing is deleted on $where: Hermes, its chats and its '
        'data stay as they are.',
        style: YsType.small.flutter.copyWith(color: palette.contentColor),
      ),
    );
  }
}

/// Circular label monogram of an instance row.
final class _Monogram extends StatelessWidget {
  const _Monogram({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final initial = label.trim().isEmpty
        ? '?'
        : label.trim().characters.first.toUpperCase();
    return SizedBox(
      width: YsLayout.monogram,
      height: YsLayout.monogram,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.neutralAmbientColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initial,
            style: YsType.monogram.flutter.copyWith(
              color: palette.contentColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Default" beside the name of the instance Hermuse opens on start.
final class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YsRadius.pill),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.sm,
          vertical: YsSpace.xxs,
        ),
        child: Text(
          'Default',
          style: YsType.caption.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
      ),
    );
  }
}

/// Add-instance flow: URL → status probe → credentials → test → save.
final class AddInstanceScreen extends ConsumerStatefulWidget {
  const AddInstanceScreen({
    required this.onDone,
    required this.onCancel,
    this.onSsh,
    this.initialUrl,
    this.initialUsername,
    this.initialPassword,
    this.autoProbe = false,
    super.key,
  });

  /// The instance is saved (its id): the caller opens it.
  final ValueChanged<String> onDone;

  /// Back where connecting started.
  final VoidCallback onCancel;

  /// Desktop: the SSH setup form instead (no dashboard address yet, or no
  /// Hermes on the machine). Null where SSH setup is not available.
  final VoidCallback? onSsh;

  /// In-memory handoff from remote setup; secrets are saved only after login.
  final String? initialUrl;
  final String? initialUsername;
  final String? initialPassword;
  final bool autoProbe;

  @override
  ConsumerState<AddInstanceScreen> createState() => AddInstanceScreenState();
}

final class AddInstanceScreenState extends ConsumerState<AddInstanceScreen> {
  final _url = TextEditingController();
  final _label = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  final _labelEdited = ValueNotifier(false);

  HermesStatus? _status;
  String? _error;
  var _busy = false;
  var _cancelled = false;
  var _initialCredentialsPending = true;
  late final Uri? _initialAddress;

  /// The address the running check reaches.
  Uri? _checking;

  /// The last check reached no usable Hermes: the drawing shows it
  /// unplugged and the check offers to try again.
  var _probeFailed = false;

  @override
  void initState() {
    super.initState();
    _url.text = widget.initialUrl ?? '';
    _initialAddress = _parsedUrl;
    if (widget.autoProbe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_cancelled) _probe();
      });
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _password.clear();
    _token.clear();
    _url.dispose();
    _label.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    _labelEdited.dispose();
    super.dispose();
  }

  /// The typed address, when it is a usable http(s) one.
  Uri? get _parsedUrl {
    try {
      final url = normalizeBaseUrl(_url.text);
      return url.host.isNotEmpty &&
              (url.isScheme('http') || url.isScheme('https'))
          ? url
          : null;
    } on Object {
      return null;
    }
  }

  /// A changed address needs a fresh probe. Never carry generated dashboard
  /// credentials over to another server.
  void _urlChanged(String _) => setState(() {
    _status = null;
    _error = null;
    _probeFailed = false;
    if (!_isInitialUrl) {
      _initialCredentialsPending = false;
      if (widget.initialPassword != null) {
        _username.clear();
        _password.clear();
      }
    }
  });

  bool get _isInitialUrl =>
      _initialAddress != null && _parsedUrl == _initialAddress;

  void _cancel() => _leave(widget.onCancel);

  /// Drops the typed secrets, then goes to [next].
  void _leave(VoidCallback next) {
    _cancelled = true;
    _password.clear();
    _token.clear();
    next();
  }

  void _failProbe(String message) => setState(() {
    _error = widget.initialUrl != null && _isInitialUrl
        ? '$message\n\nMake sure TCP ports 80 and 443 are reachable from '
              'the internet in both the server and provider firewalls.'
        : message;
    _probeFailed = true;
  });

  Future<void> _probe() async {
    if (_busy || _cancelled) return;
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
    bool current() => mounted && !_cancelled && _parsedUrl == url;
    try {
      final status = await HermesRestClient(
        ref.read(httpClientProvider),
        baseUrl: url,
      ).getStatus();
      checkSupportedVersion(status.version);
      if (!current()) return;
      if (status.loginMethod == null) {
        _failProbe(
          'This Hermes needs a login Hermuse does not support '
          '(${status.authProviders.join(', ')}).',
        );
        return;
      }
      setState(() {
        _status = status;
        if (!_labelEdited.value) _label.text = url.host;
        if (_initialCredentialsPending && _isInitialUrl) {
          _username.text = widget.initialUsername ?? '';
          _password.text = widget.initialPassword ?? '';
          _initialCredentialsPending = false;
        }
      });
    } on UnsupportedServerVersion catch (e) {
      if (current()) {
        _failProbe(
          'Hermes ${e.version} is not supported (needs ${e.supported}.x)',
        );
      }
    } on HermesUnreachable {
      if (current()) _failProbe('Host unreachable: $url');
    } on HermesException catch (e) {
      if (current()) _failProbe(e.message);
    } on Object catch (e) {
      if (current()) _failProbe('$e');
    } finally {
      if (mounted && !_cancelled) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _cancelled) return;
    final url = _parsedUrl;
    final login = _status?.loginMethod;
    if (url == null || login == null) return;
    final label = _label.text.trim();
    if (label.isEmpty || label.length > HermesInstance.maxLabelLength) {
      setState(() => _error = 'Name must be 1–64 characters');
      return;
    }
    final token = login == AuthMethod.loopbackToken;
    final secret = token ? _token.text.trim() : _password.text;
    if (secret.isEmpty) {
      setState(
        () => _error = token
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
      baseUrl: url,
      auth: login,
    );
    try {
      // Proved on a real connection before anything is stored; the secret
      // then goes to the keystore only.
      await ref
          .read(instanceAuthProvider)
          .add(
            candidate,
            secrets: token
                ? {SecretKeys.sessionToken: secret}
                : {
                    SecretKeys.username: _username.text,
                    SecretKeys.password: secret,
                  },
          );
      if (!mounted || _cancelled) return;
      _token.clear();
      _password.clear();
      widget.onDone(candidate.id);
    } on DuplicateInstance catch (e) {
      if (mounted) {
        setState(
          () => _error = e.field == 'label'
              ? 'That name is already used'
              : 'That Hermes is already registered',
        );
      }
    } on HermesAuthFailed {
      if (mounted) {
        setState(
          () => _error = token
              ? 'Wrong session token.'
              : 'Login rejected (401): check username and password',
        );
      }
    } on UnsupportedServerVersion catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Hermes ${e.version} is not supported (needs ${e.supported}.x)',
        );
      }
    } on HermesUnreachable {
      if (mounted) setState(() => _error = 'Host unreachable: $url');
    } on HermesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final status = _status;
    final checking = _busy && status == null;
    final check = checking
        ? 'Checking…'
        : _probeFailed
        ? 'Try again'
        : 'Check';
    final onCheck = _busy || _parsedUrl == null ? null : _probe;
    return YsEntrance(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: YsLayout.dialogNarrow),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperColor,
              borderRadius: BorderRadius.circular(YsRadius.bubble),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Reaching out while a check or a connection runs,
                  // unplugged when the check found no usable Hermes.
                  YsDialogHead(
                    art: _probeFailed ? YsArt.unreachable : YsArt.remote,
                    busy: _busy,
                    title: 'Add a Hermes',
                    helper: 'Paste the web address of your Hermes dashboard.',
                    trailing: YsButton.icon(
                      icon: YsIcon.close,
                      onPressed: _cancel,
                      semanticLabel: 'Cancel',
                      tooltip: 'Cancel',
                    ),
                  ),
                  const SizedBox(height: YsSpace.lg),
                  _Field(
                    label: 'Instance URL',
                    controller: _url,
                    placeholder: 'https://hermes.example.com',
                    semanticLabel: 'Instance URL',
                    icon: YsIcon.link,
                    url: true,
                    autofocus: true,
                    onChanged: _urlChanged,
                    onSubmitted: (_) => _probe(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    // The step's main action until a Hermes answers.
                    child: status == null
                        ? YsButton.primary(label: check, onPressed: onCheck)
                        : YsButton.neutral(label: check, onPressed: onCheck),
                  ),
                  if (checking || status != null) ...[
                    const SizedBox(height: YsSpace.md),
                    YsDialogCheck(
                      done: status != null,
                      // Web add-instance wording: no "no login" claim, since
                      // a gateless `hermes serve` still wants its token.
                      text: switch (status) {
                        null =>
                          'Looking for Hermes at '
                              '${_checking?.authority ?? ''}…',
                        HermesStatus(
                          loginMethod: AuthMethod.loopbackToken,
                          :final version,
                        ) =>
                          'Hermes $version · paste its session token '
                              '(HERMES_DASHBOARD_SESSION_TOKEN).',
                        HermesStatus(:final version) =>
                          'Hermes $version · sign in with your dashboard '
                              'account.',
                      },
                    ),
                  ],
                  YsResize(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (status != null)
                          YsEntrance(child: _credentials(status)),
                        if (_error case final error?) ...[
                          const SizedBox(height: YsSpace.md),
                          YsDialogError(error),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onSsh case final onSsh?) ...[
                    const SizedBox(height: YsSpace.lg),
                    YsButton.neutral(
                      label: 'Connect with SSH instead',
                      onPressed: _busy ? null : () => _leave(onSsh),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The sign-in fields and the save, once the check found a Hermes.
  Widget _credentials(HermesStatus status) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      _Field(
        label: 'Name',
        controller: _label,
        placeholder: status.version,
        semanticLabel: 'Instance name',
        icon: YsIcon.pencil,
        onChanged: (_) => _labelEdited.value = true,
      ),
      if (status.loginMethod == AuthMethod.loopbackToken) ...[
        const SizedBox(height: 12),
        _Field(
          label: 'Session token',
          controller: _token,
          placeholder: '••••••••',
          semanticLabel: 'Session token',
          icon: YsIcon.keyRound,
          obscure: true,
          onSubmitted: (_) => _save(),
        ),
      ] else ...[
        const SizedBox(height: 12),
        _Field(
          label: 'Username',
          controller: _username,
          placeholder: 'admin',
          semanticLabel: 'Username',
          icon: YsIcon.user,
        ),
        const SizedBox(height: 12),
        _Field(
          label: 'Password',
          controller: _password,
          placeholder: '••••••••',
          semanticLabel: 'Password',
          icon: YsIcon.lock,
          obscure: true,
          onSubmitted: (_) => _save(),
        ),
      ],
      const SizedBox(height: 16),
      YsButton.primary(
        label: _busy ? 'Connecting…' : 'Save and connect',
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}

final class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.semanticLabel,
    required this.icon,
    this.obscure = false,
    this.url = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final String semanticLabel;
  final YsIcon icon;
  final bool obscure;
  final bool url;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => YsField(
    label: label,
    child: YsInputBox(
      controller: controller,
      placeholder: placeholder,
      semanticLabel: semanticLabel,
      icon: icon,
      obscure: obscure,
      url: url,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  );
}
