import 'dart:async';

import 'package:cliproxy_client/cliproxy_client.dart' show CliproxyProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/open_url.dart';
import '../product/route.dart' show HermuseRouteSkeleton;
import '../shell/screens.dart' show YsDialogError, YsDialogHead;

/// Connections page: the model accounts of one instance (web
/// `HermuseConnections` parity).
///
/// Subscription sign-ins come first ([_featuredSignIns]), then the
/// connected providers; "Show other providers" unfolds the available ones
/// and the custom endpoint form. A connected provider never folds away and
/// a search shows every match.
///
/// Cards come from [connectionCardsProvider]: device-code logins show the
/// user code + verification URL with polling state and cancel; API keys use
/// a masked field with server validate errors; custom endpoints get an
/// add/delete form; external cards explain the terminal step. Bridge cards
/// only appear where [bridgeHostProvider] is overridden (desktop).
final class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({
    required this.instance,
    required this.onBack,
    this.lead,
    super.key,
  });

  final HermesInstance instance;
  final VoidCallback onBack;

  /// Shown above the page head: the onboarding stepper when the page is the
  /// onboarding's Accounts step.
  final Widget? lead;

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

final class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  final _query = TextEditingController();

  /// "Show other providers" unfolded the available providers and the custom
  /// endpoint form.
  var _others = false;

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
    bool matches(String text) => text.toLowerCase().contains(needle);
    // A featured sign-in is found by what its row shows, too.
    bool featuredMatches(ConnectionCard card, _SignIn signIn) =>
        matches(card.name) ||
        matches('Sign in with ${signIn.product}') ||
        matches(signIn.plan);
    final (signIns, rest) = _featuredSignIns(state?.cards ?? const []);
    final featured = [
      for (final (card, signIn) in signIns)
        if (featuredMatches(card, signIn)) (card, signIn),
    ];
    final others = [
      for (final card in rest)
        if (matches(card.name)) card,
    ];
    final connected = [
      for (final c in others)
        if (c.state == ConnectionCardState.connected) c,
    ];
    final available = [
      for (final c in others)
        if (c.state != ConnectionCardState.connected) c,
    ];
    // Connected providers never fold away and a search shows every match;
    // with no sign-in to feature, the other providers are the whole page.
    final foldable = needle.isEmpty && signIns.isNotEmpty;
    final unfolded = !foldable || _others;
    final muted = const YsTextStyle(
      14,
      20,
    ).flutter.copyWith(color: palette.contentMutedColor);
    final groupStyle = const YsTextStyle(
      13,
      18,
      YsWeight.medium,
    ).flutter.copyWith(color: palette.contentMutedColor);
    Widget row(ConnectionCard card, [_SignIn? signIn]) => _ConnectionCard(
      key: ValueKey(card.id),
      instanceId: instance.id,
      card: card,
      signIn: signIn,
      pendingLogin: state?.pendingLogin,
      pendingBridgeLogin: state?.pendingBridgeLogin,
    );
    Widget group(String title, List<Widget> rows) => Column(
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
                for (final (i, child) in rows.indexed) ...[
                  if (i > 0)
                    Container(height: ysHairline, color: palette.lineColor),
                  child,
                ],
              ],
            ),
          ),
        ),
      ],
    );
    // The drawing loops while the list loads and shows a pulled plug when
    // it cannot load (web `HermuseConnections` parity).
    final failed = connections.hasError && state == null;
    return ColoredBox(
      color: palette.canvasColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: YsLayout.listWidth),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.lead case final lead?) ...[
                lead,
                const SizedBox(height: YsSpace.lg),
              ],
              YsDialogHead(
                art: failed ? YsArt.unreachable : YsArt.accounts,
                busy: connections.isLoading,
                title: 'Model accounts',
                helper: 'Subscriptions and API keys ${instance.label} can use.',
                trailing: YsButton.icon(
                  icon: YsIcon.close,
                  onPressed: widget.onBack,
                  semanticLabel: 'Back',
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              YsInputBox(
                controller: _query,
                placeholder: 'Search connections',
                semanticLabel: 'Search connections',
                icon: YsIcon.search,
              ),
              if (connections.isLoading && state == null) ...[
                const SizedBox(height: 12),
                const HermuseRouteSkeleton(label: 'Loading connections…'),
              ] else if (failed) ...[
                const SizedBox(height: 12),
                YsDialogError(
                  'Could not load connections: ${connections.error}.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: YsButton.neutral(
                    label: 'Try again',
                    onPressed: () =>
                        ref.invalidate(connectionCardsProvider(instance.id)),
                  ),
                ),
              ] else ...[
                if (featured.isNotEmpty)
                  group('Use your subscription', [
                    for (final (card, signIn) in featured) row(card, signIn),
                  ]),
                if (connected.isNotEmpty)
                  group('Connected', [for (final c in connected) row(c)]),
                if (foldable) ...[
                  const SizedBox(height: YsSpace.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      expanded: _others,
                      child: YsButton.neutral(
                        label: _others
                            ? 'Hide other providers'
                            : 'Show other providers',
                        onPressed: () => setState(() => _others = !_others),
                      ),
                    ),
                  ),
                  const SizedBox(height: YsSpace.sm),
                ],
                if (unfolded) ...[
                  if (available.isNotEmpty)
                    group('Available', [for (final c in available) row(c)]),
                  if (featured.isEmpty && others.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text('No connection matches.', style: muted),
                  ],
                  const SizedBox(height: 8),
                  Text('Custom endpoint', style: groupStyle),
                  const SizedBox(height: 8),
                  _CustomEndpointCard(instanceId: instance.id),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The product and plan a featured sign-in names in place of its card's
/// name and detail ("Sign in with Codex", "Use your ChatGPT Plus/Pro
/// subscription").
typedef _SignIn = ({String product, String plan});

/// The subscription sign-ins featured at the top of the page, then every
/// other card (web `_featuredSignIns` parity: same rules).
///
/// The Claude Code and Codex subscription-bridge cards are featured.
/// Without bridge cards (no bridge host) the Hermes `openai-codex`
/// device-code card stands in for Codex and Claude is left out: its Hermes
/// sign-in needs a terminal. The other bridges and the Hermes cards a
/// featured bridge replaces (`hermesIds`: `anthropic`, `claude-code`,
/// `openai-codex`) are other providers.
(List<(ConnectionCard, _SignIn)>, List<ConnectionCard>) _featuredSignIns(
  List<ConnectionCard> cards,
) {
  ConnectionCard? bridge(CliproxyProvider provider) =>
      cards.where((c) => c.bridgeSpec?.provider == provider).firstOrNull;
  bool hermesCodex(ConnectionCard c) =>
      c.id == 'openai-codex' && c.flow == ConnectionFlow.deviceCode;
  final claude = bridge(CliproxyProvider.anthropic);
  final codexBridge = bridge(CliproxyProvider.codex);
  final codex = codexBridge ?? cards.where(hermesCodex).firstOrNull;
  final codexProduct = codexBridge == null ? 'ChatGPT / Codex' : 'Codex';
  final featured = <(ConnectionCard, _SignIn)>[
    if (claude != null)
      (claude, (product: 'Claude Code', plan: 'Claude Pro/Max')),
    if (codex != null)
      (codex, (product: codexProduct, plan: 'ChatGPT Plus/Pro')),
  ];
  final others = [
    for (final card in cards)
      if (card.id != claude?.id && card.id != codex?.id) card,
  ];
  return (featured, others);
}

final class _ConnectionCard extends ConsumerStatefulWidget {
  const _ConnectionCard({
    required this.instanceId,
    required this.card,
    required this.pendingLogin,
    required this.pendingBridgeLogin,
    this.signIn,
    super.key,
  });

  final String instanceId;
  final ConnectionCard card;
  final DeviceCodeLogin? pendingLogin;
  final BridgeLogin? pendingBridgeLogin;

  /// Set on a featured subscription sign-in: a taller row naming its
  /// product and plan, without the Advanced chip.
  final _SignIn? signIn;

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
    // A featured sign-in is a taller row that names its product once signed
    // in and invites to sign in until then; progress and errors replace its
    // plan line.
    final signIn = widget.signIn;
    final featured = signIn != null;
    final title = signIn == null
        ? card.name
        : connected
        ? signIn.product
        : 'Sign in with ${signIn.product}';
    final idle = card.state == ConnectionCardState.disconnected;
    final subtitle = signIn != null && (idle || card.detail.isEmpty)
        ? 'Use your ${signIn.plan} subscription'
        : card.detail;
    final titleType = featured ? YsType.heading : YsType.label;
    final subtitleType = featured ? YsType.small : YsType.caption;
    // The body lines up under the title.
    final bodyInset = featured
        ? YsLayout.activityTileSize + YsSpace.md + 14
        : 48.0;
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
    // The row's state dot: connected pings once as the row shows; waiting
    // and failed logins keep a still dot.
    final dot = switch (card.state) {
      ConnectionCardState.connected => palette.successColor,
      ConnectionCardState.pending => palette.primaryColor,
      ConnectionCardState.error => palette.errorColor,
      ConnectionCardState.disconnected => null,
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
          semanticLabel: '$title: $action',
          builder: (context, state) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: featured ? YsSpace.md : 8,
              ),
              child: Row(
                children: [
                  _Logo(name: card.name, featured: featured),
                  SizedBox(width: featured ? YsSpace.md : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: titleType.flutter.copyWith(
                                  color: palette.contentColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // A featured sign-in keeps its personal-use
                            // note for the body.
                            if (card.advanced && !featured) ...[
                              const SizedBox(width: 8),
                              _AdvancedChip(),
                            ],
                          ],
                        ),
                        if (subtitle.isNotEmpty && subtitle != title)
                          Text(
                            subtitle,
                            style: subtitleType.flutter.copyWith(
                              color: palette.contentMutedColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (dot != null) ...[
                    YsPing(
                      live: connected,
                      color: dot,
                      child: SizedBox.square(
                        dimension: YsLayout.statusDot,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
            padding: EdgeInsets.only(left: bodyInset, right: 14, bottom: 12),
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
            'Personal use only: using a consumer subscription outside its '
            'official clients may breach the vendor ToS and can stop working '
            'without notice.',
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
  const _Logo({required this.name, required this.featured});

  final String name;

  /// The bigger tile of a featured sign-in.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final trimmed = name.trim();
    final size = featured ? YsLayout.activityTileSize : 24.0;
    final type = featured
        ? YsType.monogram
        : const YsTextStyle(12, 16, YsWeight.semibold);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.paperClearColor,
          borderRadius: BorderRadius.circular(featured ? YsRadius.row : 6),
        ),
        child: Center(
          child: Text(
            trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
            style: type.flutter.copyWith(color: palette.contentColor),
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
  // Add is enabled by the name and URL fields: rebuild on their edits.
  late final TextEditingController _name = TextEditingController()
    ..addListener(() => setState(() {}));
  late final TextEditingController _baseUrl = TextEditingController()
    ..addListener(() => setState(() {}));
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
