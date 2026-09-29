import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:uuid/uuid.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// One-line state dot + label of an instance's connection.
final class InstanceStatusDot extends ConsumerWidget {
  const InstanceStatusDot(this.instanceId, {super.key});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final state = ref.watch(connectionStateProvider(instanceId));
    final (color, label) = switch (state) {
      AsyncData(:final value) => switch (value) {
        ConnectionState.ready => (palette.successColor, 'Connected'),
        ConnectionState.connecting ||
        ConnectionState.reconnecting => (palette.primaryColor, 'Connecting…'),
        ConnectionState.error => (palette.errorColor, 'Error'),
        ConnectionState.disconnected => (palette.contentSubtleColor, 'Idle'),
      },
      AsyncError() => (palette.errorColor, 'Error'),
      _ => (palette.contentSubtleColor, 'Idle'),
    };
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

/// Manage the registered Hermes instances: add, rename, primary, delete.
final class InstancesScreen extends ConsumerWidget {
  const InstancesScreen({
    required this.onAdd,
    required this.onClose,
    required this.onSetup,
    required this.onConnections,
    this.onInstall,
    super.key,
  });

  final VoidCallback onAdd;

  /// Desktop without a local instance: install/adopt Hermes here.
  final VoidCallback? onInstall;
  final VoidCallback onClose;
  final ValueChanged<String> onSetup;
  final ValueChanged<String> onConnections;
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hermes instances',
                        style: YsType.title.flutter.copyWith(
                          color: palette.contentColor,
                        ),
                      ),
                    ),
                    YsButton.icon(
                      icon: YsIcon.close,
                      onPressed: onClose,
                      semanticLabel: 'Close instances',
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _instancesBody(context, ref, instances),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    YsButton.primary(
                      label: 'Add instance',
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
      return Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final instance in list) ...[
              _InstanceRow(
                instance: instance,
                onSetup: onSetup,
                onConnections: onConnections,
              ),
              const SizedBox(height: 8),
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
    required this.onSetup,
    required this.onConnections,
  });

  final HermesInstance instance;
  final ValueChanged<String> onSetup;
  final ValueChanged<String> onConnections;

  @override
  ConsumerState<_InstanceRow> createState() => _InstanceRowState();
}

final class _InstanceRowState extends ConsumerState<_InstanceRow> {
  var _renaming = false;
  var _confirmingDelete = false;
  var _signingIn = false;
  late final TextEditingController _label;
  late final TextEditingController _signUser = TextEditingController();
  late final TextEditingController _signPassword = TextEditingController();
  var _signBusy = false;
  String? _error;

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
    });
    try {
      await ref
          .read(instanceAuthProvider)
          .signIn(widget.instance.id, username: username, password: password);
      if (mounted) {
        setState(() {
          _signingIn = false;
          _signUser.clear();
          _signPassword.clear();
        });
      }
    } on HermesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _signBusy = false);
    }
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

  Future<void> _delete() async {
    await (await ref.read(registryProvider.future)).remove(widget.instance.id);
    // Point the open chat at what is left, if it pointed at the deleted one.
    final active = ref.read(activeThreadProvider).value;
    if (active != null && active.instanceId == widget.instance.id) {
      final registry = await ref.read(registryProvider.future);
      final next = registry.primary;
      if (next == null) {
        ref.invalidate(activeThreadProvider);
      } else {
        await ref.read(activeThreadProvider.notifier).openInstance(next.id);
      }
    }
  }

  Future<void> _open() async {
    await ref
        .read(activeThreadProvider.notifier)
        .openInstance(widget.instance.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final instance = widget.instance;
    // Outlined, not filled: the neutral buttons and the monogram disc share
    // the neutral fill and would vanish on it (web `.hermuse-instance-row`).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YsRadius.row),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Monogram(label: instance.label),
                const SizedBox(width: 12),
                Expanded(
                  child: _renaming
                      ? YsInputBox(
                          controller: _label,
                          semanticLabel: 'Instance name',
                          autofocus: true,
                          onSubmitted: (_) => _rename(),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              instance.label,
                              style: YsType.label.flutter.copyWith(
                                color: palette.contentColor,
                              ),
                            ),
                            Text(
                              instance.baseUrl.toString(),
                              style: YsType.caption.flutter.copyWith(
                                color: palette.contentMutedColor,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 12),
                InstanceStatusDot(instance.id),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: YsType.caption.flutter.copyWith(
                  color: palette.errorColor,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_signingIn) ...[
              YsInputBox(
                controller: _signUser,
                placeholder: 'Username',
                semanticLabel: 'Username',
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 8),
              YsInputBox(
                controller: _signPassword,
                placeholder: 'Password',
                semanticLabel: 'Password',
                obscure: true,
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  YsButton.primary(
                    label: _signBusy ? 'Signing in…' : 'Sign in',
                    onPressed: _signBusy ? null : _signIn,
                  ),
                  const SizedBox(width: 8),
                  YsButton.neutral(
                    label: 'Cancel',
                    onPressed: _signBusy
                        ? null
                        : () => setState(() {
                            _signingIn = false;
                            _error = null;
                          }),
                  ),
                ],
              ),
            ] else if (_confirmingDelete)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Delete “${instance.label}” and its saved credentials?',
                      style: YsType.small.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                    ),
                  ),
                  YsButton.neutral(
                    label: 'Delete',
                    onPressed: _delete,
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  const SizedBox(width: 8),
                  YsButton.icon(
                    icon: YsIcon.close,
                    onPressed: () => setState(() => _confirmingDelete = false),
                    semanticLabel: 'Cancel delete',
                    size: 28,
                    iconSize: 16,
                  ),
                ],
              )
            else if (_renaming)
              Row(
                children: [
                  YsButton.primary(label: 'Save', onPressed: _rename),
                  const SizedBox(width: 8),
                  YsButton.neutral(
                    label: 'Cancel',
                    onPressed: () => setState(() {
                      _renaming = false;
                      _error = null;
                      _label.text = instance.label;
                    }),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  YsButton.neutral(
                    label: 'Open',
                    onPressed: _open,
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  YsButton.neutral(
                    label: 'Rename',
                    onPressed: () => setState(() => _renaming = true),
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  YsButton.neutral(
                    label: 'Primary',
                    onPressed: () => ref
                        .read(registryProvider.future)
                        .then((r) => r.setPrimary(instance.id)),
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  YsButton.neutral(
                    label: 'Setup',
                    onPressed: () => widget.onSetup(instance.id),
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  YsButton.neutral(
                    label: 'Connections',
                    onPressed: () => widget.onConnections(instance.id),
                    textStyle: YsType.small,
                    height: 28,
                  ),
                  if (instance.auth == AuthMethod.password)
                    YsButton.neutral(
                      label: 'Sign in',
                      onPressed: () => setState(() {
                        _signingIn = true;
                        _error = null;
                      }),
                      textStyle: YsType.small,
                      height: 28,
                    ),
                  YsButton.icon(
                    icon: YsIcon.close,
                    onPressed: () => setState(() => _confirmingDelete = true),
                    semanticLabel: 'Delete ${instance.label}',
                    tooltip: 'Delete',
                    size: 28,
                    iconSize: 16,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Circular label monogram used in the rail switcher and instance rows.
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
      width: 32,
      height: 32,
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

/// Add-instance flow: URL → status probe → credentials → test → save.
final class AddInstanceScreen extends ConsumerStatefulWidget {
  const AddInstanceScreen({
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  ConsumerState<AddInstanceScreen> createState() => AddInstanceScreenState();
}

final class AddInstanceScreenState extends ConsumerState<AddInstanceScreen> {
  final _url = TextEditingController();
  final _label = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _labelEdited = ValueNotifier(false);

  HermesStatus? _status;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    _username.dispose();
    _password.dispose();
    _labelEdited.dispose();
    super.dispose();
  }

  Uri? get _parsedUrl {
    try {
      return normalizeBaseUrl(_url.text);
    } on Object {
      return null;
    }
  }

  Future<void> _probe() async {
    final url = _parsedUrl;
    if (url == null) {
      setState(() => _error = 'Enter a valid http(s) URL');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final status = await HermesRestClient(
        ref.read(httpClientProvider),
        baseUrl: url,
      ).getStatus();
      checkSupportedVersion(status.version);
      if (!mounted) return;
      setState(() {
        _status = status;
        if (!_labelEdited.value) _label.text = url.host;
      });
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

  Future<void> _save() async {
    final url = _parsedUrl;
    final status = _status;
    if (url == null || status == null) return;
    final label = _label.text.trim();
    if (label.isEmpty || label.length > HermesInstance.maxLabelLength) {
      setState(() => _error = 'Name must be 1–64 characters');
      return;
    }
    final password = _password.text;
    if (status.authRequired && password.isEmpty) {
      setState(() => _error = 'Enter the dashboard password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Validate by really connecting before persisting anything. The
      // trial transport reads the just-typed credentials from an
      // ephemeral store — never the keystore, which only gets them
      // once validation succeeds.
      final candidate = HermesInstance(
        id: const Uuid().v4(),
        label: label,
        kind: InstanceKind.remote,
        baseUrl: url,
        auth: AuthMethod.password,
      );
      final trialSecrets = MemorySecretStore();
      await trialSecrets.write(
        candidate.id,
        SecretKeys.username,
        _username.text,
      );
      await trialSecrets.write(candidate.id, SecretKeys.password, password);
      final trial = await DashboardTransport.connect(
        instance: candidate,
        secrets: trialSecrets,
        httpClient: ref.read(httpClientProvider),
      );
      await trial.close();
      final registry = await ref.read(registryProvider.future);
      try {
        await registry.add(candidate);
      } on DuplicateInstance catch (e) {
        if (mounted) {
          setState(
            () => _error = e.field == 'label'
                ? 'That name is already used'
                : 'That Hermes is already registered',
          );
        }
        return;
      }
      final secrets = ref.read(secretStoreProvider);
      await secrets.write(candidate.id, SecretKeys.username, _username.text);
      await secrets.write(candidate.id, SecretKeys.password, password);
      await ref.read(activeThreadProvider.notifier).openInstance(candidate.id);
      widget.onDone(candidate.id);
    } on HermesAuthFailed {
      if (mounted) {
        setState(
          () => _error = 'Login rejected (401): check username and password',
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
    return Center(
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add a Hermes',
                        style: YsType.title.flutter.copyWith(
                          color: palette.contentColor,
                        ),
                      ),
                    ),
                    YsButton.icon(
                      icon: YsIcon.close,
                      onPressed: widget.onCancel,
                      semanticLabel: 'Cancel',
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Instance URL',
                  controller: _url,
                  placeholder: 'https://hermes.example.com',
                  semanticLabel: 'Instance URL',
                  onSubmitted: (_) => _probe(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: YsButton.neutral(
                    label: _busy && status == null ? 'Checking…' : 'Check',
                    onPressed: _busy ? null : _probe,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Hermes ${status.version} · '
                    '${status.authRequired ? 'login required (${status.authProviders.join(', ')})' : 'no login'}',
                    style: YsType.small.flutter.copyWith(
                      color: palette.successColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Name',
                    controller: _label,
                    placeholder: status.version,
                    semanticLabel: 'Instance name',
                    onChanged: (_) => _labelEdited.value = true,
                  ),
                  if (status.authRequired) ...[
                    const SizedBox(height: 12),
                    _Field(
                      label: 'Username',
                      controller: _username,
                      placeholder: 'admin',
                      semanticLabel: 'Username',
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      label: 'Password',
                      controller: _password,
                      placeholder: '••••••••',
                      semanticLabel: 'Password',
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
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: YsType.body.flutter.copyWith(
                      color: palette.errorColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.semanticLabel,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final String semanticLabel;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => YsField(
    label: label,
    child: YsInputBox(
      controller: controller,
      placeholder: placeholder,
      semanticLabel: semanticLabel,
      obscure: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  );
}
