import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/open_url.dart';

/// Connections page: card list for one instance (web `HermuseConnections`
/// parity), plus desktop subscription-bridge cards (marked Advanced).
///
/// Cards come from [connectionCardsProvider]: device-code logins show the
/// user code + verification URL with polling state and cancel; API keys use
/// a masked field with server validate errors; custom endpoints get an
/// add/delete form; external cards explain the terminal step. Bridge cards
/// only appear where [bridgeHostProvider] is overridden (desktop).
/// Model accounts of an instance, as a connector list: search, then
/// Connected and Available groups of compact rows that expand in place.
final class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({
    required this.instance,
    required this.onBack,
    super.key,
  });

  final HermesInstance instance;
  final VoidCallback onBack;

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

final class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final instance = widget.instance;
    final connections = ref.watch(connectionCardsProvider(instance.id));
    final state = connections.value;
    final needle = _query.text.trim().toLowerCase();
    final cards = [
      for (final card in state?.cards ?? const <ConnectionCard>[])
        if (needle.isEmpty || card.name.toLowerCase().contains(needle)) card,
    ];
    final muted = const YsTextStyle(
      14,
      20,
    ).flutter.copyWith(color: palette.contentMutedColor);
    final groupStyle = const YsTextStyle(
      13,
      18,
      YsWeight.medium,
    ).flutter.copyWith(color: palette.contentMutedColor);
    Widget group(String title, List<ConnectionCard> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(title, style: groupStyle),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(YsRadius.row),
          child: ColoredBox(
            color: palette.neutralAmbientColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, card) in list.indexed) ...[
                  if (i > 0)
                    Container(height: ysHairline, color: palette.lineColor),
                  _ConnectionCard(
                    key: ValueKey(card.id),
                    instanceId: instance.id,
                    card: card,
                    pendingLogin: state?.pendingLogin,
                    pendingBridgeLogin: state?.pendingBridgeLogin,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    final connected = [
      for (final c in cards)
        if (c.state == ConnectionCardState.connected) c,
    ];
    final available = [
      for (final c in cards)
        if (c.state != ConnectionCardState.connected) c,
    ];
    return ColoredBox(
      color: palette.canvasColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: YsLayout.listWidth),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connections',
                      style: YsType.title.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                    ),
                  ),
                  YsButton.icon(
                    icon: YsIcon.close,
                    onPressed: widget.onBack,
                    semanticLabel: 'Back',
                    size: 36,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Model accounts ${instance.label} can use.', style: muted),
              const SizedBox(height: 12),
              YsInputBox(
                controller: _query,
                placeholder: 'Search connections',
                semanticLabel: 'Search connections',
              ),
              if (connections.isLoading && state == null) ...[
                const SizedBox(height: 12),
                Text('Loading connections…', style: muted),
              ] else if (connections.hasError && state == null) ...[
                const SizedBox(height: 12),
                Text(
                  'Could not load connections: ${connections.error}.',
                  style: YsType.label.flutter.copyWith(
                    color: palette.primary2Color,
                  ),
                ),
              ] else ...[
                if (connected.isNotEmpty) group('Connected', connected),
                if (available.isNotEmpty) group('Available', available),
                if (cards.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text('No connection matches.', style: muted),
                ],
                const SizedBox(height: 8),
                Text('Custom endpoint', style: groupStyle),
                const SizedBox(height: 8),
                _CustomEndpointCard(instanceId: instance.id),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _ConnectionCard extends ConsumerStatefulWidget {
  const _ConnectionCard({
    required this.instanceId,
    required this.card,
    required this.pendingLogin,
    required this.pendingBridgeLogin,
    super.key,
  });

  final String instanceId;
  final ConnectionCard card;
  final DeviceCodeLogin? pendingLogin;
  final BridgeLogin? pendingBridgeLogin;

  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

final class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  var _open = false;
  // Save is enabled by the field's content: rebuild on every edit.
  late final TextEditingController _key = TextEditingController()
    ..addListener(() => setState(() {}));
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  ConnectionCards _cards() =>
      ref.read(connectionCardsProvider(widget.instanceId).notifier);

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final card = widget.card;
    final pending = widget.pendingLogin;
    final isPending = pending != null && pending.providerId == card.id;
    final bridgePending =
        widget.pendingBridgeLogin != null &&
        widget.pendingBridgeLogin!.cardId == card.id;
    // An in-flight login keeps its row open.
    final open = _open || isPending || bridgePending || _error != null;
    final connected = card.state == ConnectionCardState.connected;
    final (action, actionColor) = switch ((card.state, card.flow)) {
      (ConnectionCardState.connected, _) => (
        'Manage',
        palette.contentMutedColor,
      ),
      (ConnectionCardState.pending, _) => (
        'Waiting…',
        palette.contentMutedColor,
      ),
      (ConnectionCardState.error, _) => ('Retry', palette.primary2Color),
      (_, ConnectionFlow.external) => ('Terminal', palette.contentMutedColor),
      _ => ('Connect', palette.primary2Color),
    };
    final body = <Widget>[
      if (card.flow == ConnectionFlow.deviceCode && !connected)
        _deviceBody(card, isPending ? pending : null),
      if (card.flow == ConnectionFlow.apiKey && !connected) _keyBody(card),
      if (card.flow == ConnectionFlow.external)
        Text(
          card.cliCommand.isNotEmpty
              ? 'Sign in from a terminal: ${card.cliCommand}'
              : 'Sign in from a terminal; Hermes picks up the credentials.',
          style: const YsTextStyle(
            14,
            20,
          ).flutter.copyWith(color: palette.contentMutedColor),
        ),
      if (card.flow == ConnectionFlow.bridge)
        _bridgeBody(card, bridgePending ? widget.pendingBridgeLogin : null),
      if (card.poolEntries.isNotEmpty)
        Text(
          card.poolEntries
              .map(
                (e) =>
                    '#${e.index} ${e.label.isEmpty ? e.authType : e.label}'
                    '${e.tokenPreview.isEmpty ? '' : ' ${e.tokenPreview}'}',
              )
              .join(' · '),
          style: YsType.caption.flutter.copyWith(
            color: palette.contentSubtleColor,
          ),
        ),
      if (connected) ...[
        _ModelSlots(instanceId: widget.instanceId, card: card),
        Align(
          alignment: Alignment.centerRight,
          child: YsButton.neutral(
            label: _busy ? 'Working…' : 'Disconnect',
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await _cards().disconnect(card.id);
                    } on Object catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ),
      ],
      if (_error != null)
        Text(
          _error!,
          style: YsType.label.flutter.copyWith(color: palette.primary2Color),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsPressable(
          onPressed: () => setState(() => _open = !open),
          semanticLabel: '${card.name}: $action',
          builder: (context, state) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  _Logo(name: card.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                card.name,
                                style: YsType.label.flutter.copyWith(
                                  color: palette.contentColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (card.advanced) ...[
                              const SizedBox(width: 8),
                              _AdvancedChip(),
                            ],
                          ],
                        ),
                        if (card.detail.isNotEmpty && card.detail != card.name)
                          Text(
                            card.detail,
                            style: YsType.caption.flutter.copyWith(
                              color: palette.contentMutedColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    action,
                    style: YsType.label.flutter.copyWith(color: actionColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open && body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 14, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < body.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  body[i],
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _deviceBody(ConnectionCard card, DeviceCodeLogin? login) {
    if (login == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: YsButton.primary(
          label: _busy ? 'Starting…' : 'Connect',
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final result = await _cards().startDeviceCode(card.id);
                    if (mounted &&
                        result.outcome != DevicePollOutcome.approved) {
                      setState(() => _error = _deviceVerdict(result));
                    }
                  } on Object catch (e) {
                    if (mounted) setState(() => _error = '$e');
                  }
                  if (mounted) setState(() => _busy = false);
                },
        ),
      );
    }
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperClearColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              login.userCode,
              style: const YsTextStyle(
                22,
                28,
                YsWeight.semibold,
              ).flutter.copyWith(color: palette.contentColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _LinkRow(url: login.verificationUrl),
            const SizedBox(height: 8),
            Text(
              'Enter the code at the link, then wait for approval.',
              style: const YsTextStyle(
                14,
                20,
              ).flutter.copyWith(color: palette.contentMutedColor),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                YsButton.neutral(
                  label: 'Open link',
                  onPressed: () => openExternalUrl(login.verificationUrl),
                ),
                const Spacer(),
                YsButton.neutral(
                  label: 'Cancel',
                  onPressed: () => unawaited(_cards().cancelLogin()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyBody(ConnectionCard card) => Row(
    children: [
      Expanded(
        child: YsInputBox(
          controller: _key,
          placeholder: card.keyEnv.isEmpty
              ? 'API key'
              : 'API key (${card.keyEnv})',
          semanticLabel: '${card.name} API key',
          obscure: true,
          onSubmitted: (_) => unawaited(_saveKey(card)),
        ),
      ),
      const SizedBox(width: 8),
      YsButton.primary(
        label: _busy ? 'Saving…' : 'Save',
        onPressed: _busy || _key.text.trim().isEmpty
            ? null
            : () => unawaited(_saveKey(card)),
      ),
    ],
  );

  Future<void> _saveKey(ConnectionCard card) async {
    final key = _key.text;
    if (key.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _cards().saveApiKey(card.id, key);
      if (mounted) setState(_key.clear);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _bridgeBody(ConnectionCard card, BridgeLogin? login) {
    final palette = YsTheme.of(context);
    if (login == null) {
      final connected = card.state == ConnectionCardState.connected;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Uses your personal subscription through the on-device sidecar. '
            'This may breach the vendor ToS and can break without notice.',
            style: YsType.caption.flutter.copyWith(
              color: palette.contentSubtleColor,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: YsButton.primary(
              label: _busy
                  ? 'Starting…'
                  : connected
                  ? 'Reconnect'
                  : 'Connect',
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        final result = await _cards().startBridgeLogin(card.id);
                        if (mounted && result.outcome != BridgePollOutcome.ok) {
                          setState(() => _error = _bridgeVerdict(result));
                        }
                      } on Object catch (e) {
                        if (mounted) setState(() => _error = '$e');
                      }
                      if (mounted) setState(() => _busy = false);
                    },
            ),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperClearColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (login.userCode != null && login.userCode!.isNotEmpty) ...[
              SelectableText(
                login.userCode!,
                style: const YsTextStyle(
                  22,
                  28,
                  YsWeight.semibold,
                ).flutter.copyWith(color: palette.contentColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            _LinkRow(url: login.url),
            const SizedBox(height: 8),
            Text(
              login.deviceFlow
                  ? 'Enter the code at the link, then wait for approval.'
                  : 'Complete the login in the browser, then wait here.',
              style: const YsTextStyle(
                14,
                20,
              ).flutter.copyWith(color: palette.contentMutedColor),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                YsButton.neutral(
                  label: 'Open link',
                  onPressed: () => openExternalUrl(login.url),
                ),
                const Spacer(),
                YsButton.neutral(
                  label: 'Cancel',
                  onPressed: () => unawaited(_cards().cancelBridgeLogin()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _deviceVerdict(DevicePollResult result) =>
      switch (result.outcome) {
        DevicePollOutcome.denied => 'The login was denied in the browser.',
        DevicePollOutcome.expired => 'The code expired. Try again.',
        DevicePollOutcome.cancelled => 'The login was cancelled.',
        DevicePollOutcome.timeout => 'Timed out waiting for approval.',
        DevicePollOutcome.error =>
          result.message.isEmpty ? 'The login failed.' : result.message,
        DevicePollOutcome.approved => '',
      };

  static String _bridgeVerdict(BridgePollResult result) =>
      switch (result.outcome) {
        BridgePollOutcome.cancelled => 'The login was cancelled.',
        BridgePollOutcome.timeout => 'Timed out waiting for approval.',
        BridgePollOutcome.error =>
          result.message.isEmpty ? 'The login failed.' : result.message,
        BridgePollOutcome.ok => '',
      };
}

final class _Logo extends StatelessWidget {
  const _Logo({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final trimmed = name.trim();
    return SizedBox(
      width: 24,
      height: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.paperClearColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
            style: const YsTextStyle(
              12,
              16,
              YsWeight.semibold,
            ).flutter.copyWith(color: palette.contentColor),
          ),
        ),
      ),
    );
  }
}

final class _AdvancedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YsRadius.pill),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          'Advanced',
          style: YsType.caption.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
      ),
    );
  }
}

final class _LinkRow extends StatefulWidget {
  const _LinkRow({required this.url});

  final String url;

  @override
  State<_LinkRow> createState() => _LinkRowState();
}

final class _LinkRowState extends State<_LinkRow> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            widget.url,
            style: YsType.label.flutter.copyWith(color: palette.primary2Color),
          ),
        ),
        const SizedBox(width: 8),
        YsButton.neutral(
          label: _copied ? 'Copied' : 'Copy',
          onPressed: _copy,
          textStyle: YsType.small,
          height: 28,
        ),
      ],
    );
  }
}

/// The ≤2 selected models of a connected card, with a picker per slot and
/// "Use as default" (large → main, small → auxiliary).
final class _ModelSlots extends ConsumerStatefulWidget {
  const _ModelSlots({required this.instanceId, required this.card});

  final String instanceId;
  final ConnectionCard card;

  @override
  ConsumerState<_ModelSlots> createState() => _ModelSlotsState();
}

final class _ModelSlotsState extends ConsumerState<_ModelSlots> {
  var _busy = false;
  String? _error;

  Future<void> _select(ModelTier tier, String? modelId) async {
    setState(() => _error = null);
    try {
      await ref
          .read(
            modelSelectionProvider(widget.instanceId, widget.card.id).notifier,
          )
          .select(tier, modelId);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _makeDefault() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(
            modelSelectionProvider(widget.instanceId, widget.card.id).notifier,
          )
          .makeDefault();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final selection = ref.watch(
      modelSelectionProvider(widget.instanceId, widget.card.id),
    );
    final current = selection.value;
    if (selection.isLoading && current == null) {
      return Text(
        'Loading models…',
        style: YsType.caption.flutter.copyWith(
          color: palette.contentSubtleColor,
        ),
      );
    }
    if (current == null) {
      return Text(
        'Models unavailable: ${selection.error}',
        style: YsType.caption.flutter.copyWith(
          color: palette.contentSubtleColor,
        ),
      );
    }
    final options = [for (final id in current.allModels) (id, id)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Slot(
          label: 'Large',
          value: current.large ?? '',
          options: options,
          semanticLabel: '${widget.card.name} large model',
          onChanged: (v) =>
              unawaited(_select(ModelTier.large, v.isEmpty ? null : v)),
        ),
        const SizedBox(height: 8),
        _Slot(
          label: 'Small',
          value: current.small ?? '',
          options: options,
          semanticLabel: '${widget.card.name} small model',
          onChanged: (v) =>
              unawaited(_select(ModelTier.small, v.isEmpty ? null : v)),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: YsButton.neutral(
            label: _busy ? 'Working…' : 'Use as default',
            onPressed: _busy || current.large == null
                ? null
                : () => unawaited(_makeDefault()),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _error!,
              style: YsType.label.flutter.copyWith(
                color: palette.primary2Color,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

final class _Slot extends StatelessWidget {
  const _Slot({
    required this.label,
    required this.value,
    required this.options,
    required this.semanticLabel,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final String semanticLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: YsSelect(
            value: value,
            options: [('', 'None'), ...options],
            onChanged: onChanged,
            semanticLabel: semanticLabel,
          ),
        ),
      ],
    );
  }
}

final class _CustomEndpointCard extends ConsumerStatefulWidget {
  const _CustomEndpointCard({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_CustomEndpointCard> createState() =>
      _CustomEndpointCardState();
}

final class _CustomEndpointCardState
    extends ConsumerState<_CustomEndpointCard> {
  var _open = false;
  late final TextEditingController _name = TextEditingController();
  late final TextEditingController _baseUrl = TextEditingController();
  late final TextEditingController _apiKey = TextEditingController();
  late final TextEditingController _model = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    if (!_open) {
      return Align(
        alignment: Alignment.centerRight,
        child: YsButton.neutral(
          label: 'Add custom endpoint',
          onPressed: () => setState(() => _open = true),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralAmbientColor,
        borderRadius: BorderRadius.circular(YsRadius.bubble),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Custom endpoint',
              style: const YsTextStyle(
                15,
                20,
                YsWeight.semibold,
              ).flutter.copyWith(color: palette.contentColor),
            ),
            Text(
              'Any OpenAI-compatible API.',
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
            const SizedBox(height: 12),
            YsField(
              label: 'Name',
              child: YsInputBox(
                controller: _name,
                placeholder: 'Local model',
                semanticLabel: 'Endpoint name',
              ),
            ),
            const SizedBox(height: 12),
            YsField(
              label: 'Base URL',
              child: YsInputBox(
                controller: _baseUrl,
                placeholder: 'http://localhost:1234/v1',
                semanticLabel: 'Endpoint base URL',
              ),
            ),
            const SizedBox(height: 12),
            YsField(
              label: 'API key (optional)',
              child: YsInputBox(
                controller: _apiKey,
                placeholder: 'sk-…',
                semanticLabel: 'Endpoint API key',
                obscure: true,
              ),
            ),
            const SizedBox(height: 12),
            YsField(
              label: 'Model (optional)',
              child: YsInputBox(
                controller: _model,
                placeholder: 'model id',
                semanticLabel: 'Endpoint model',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: YsType.label.flutter.copyWith(
                  color: palette.primary2Color,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                YsButton.neutral(
                  label: 'Cancel',
                  onPressed: _busy ? null : () => setState(() => _open = false),
                ),
                const SizedBox(width: 12),
                YsButton.primary(
                  label: _busy ? 'Adding…' : 'Add',
                  onPressed:
                      _busy ||
                          _name.text.trim().isEmpty ||
                          _baseUrl.text.trim().isEmpty
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          try {
                            await ref
                                .read(
                                  connectionCardsProvider(widget.instanceId)
                                      .notifier,
                                )
                                .addCustomEndpoint(
                                  name: _name.text.trim(),
                                  baseUrl: _baseUrl.text.trim(),
                                  apiKey: _apiKey.text,
                                  model: _model.text.trim(),
                                );
                            if (mounted) {
                              setState(() {
                                _open = false;
                                _name.clear();
                                _baseUrl.clear();
                                _apiKey.clear();
                                _model.clear();
                              });
                            }
                          } on Object catch (e) {
                            if (mounted) setState(() => _error = '$e');
                          }
                          if (mounted) setState(() => _busy = false);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
