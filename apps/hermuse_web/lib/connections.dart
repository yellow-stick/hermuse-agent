import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'route.dart';
import 'scope.dart';
import 'screens.dart';

/// Connections page: the model accounts of one instance (desktop
/// `ConnectionsScreen` parity).
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
/// never appear on web ([bridgeHostProvider] is null, no sidecar).
class HermuseConnections extends StatefulComponent {
  const HermuseConnections({
    required this.instance,
    required this.onBack,
    this.lead,
    super.key,
  });

  final HermesInstance instance;
  final VoidCallback onBack;

  /// Shown above the page head: the onboarding stepper when the page is the
  /// onboarding's Accounts step (desktop `ConnectionsScreen` parity).
  final Component? lead;

  @override
  State<HermuseConnections> createState() => _HermuseConnectionsState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    css('.hermuse-screen-top').styles(alignItems: .start),
    css('.hermuse-conn-sub').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-conn-retry-row').styles(display: .flex),
    css('.hermuse-conn-more').styles(
      display: .flex,
      margin: .only(top: YsSpace.xs.px),
    ),
    css('.hermuse-conn-group').styles(
      margin: .only(top: 8.px),
      fontSize: 13.px,
      lineHeight: 18.px,
      fontWeight: .w500,
      color: .variable('--content-muted'),
    ),
    // Connector list: one rounded surface, hairline dividers.
    css('.hermuse-conn-list').styles(
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      overflow: .hidden,
      backgroundColor: .variable('--neutral-ambient'),
    ),
    css('.hermuse-conn-item + .hermuse-conn-item')
        .styles(raw: {'border-top': '1.2px solid var(--line)'}),
    css('.hermuse-conn-head').styles(
      width: 100.percent,
      minHeight: 44.px,
      padding: .symmetric(vertical: 8.px, horizontal: 14.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(10.px),
      textAlign: .left,
    ),
    css('.hermuse-conn-logo').styles(
      width: 24.px,
      height: 24.px,
      radius: .circular(6.px),
      display: .flex,
      alignItems: .center,
      justifyContent: .center,
      backgroundColor: .variable('--paper-clear'),
      fontSize: 12.px,
      lineHeight: 16.px,
      fontWeight: .w600,
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-conn-title').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      raw: {'min-width': '0'},
    ),
    css('.hermuse-conn-name').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-conn-detail').styles(
      fontSize: 12.px,
      lineHeight: 16.px,
      color: .variable('--content-muted'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {'white-space': 'nowrap'},
    ),
    css('.hermuse-conn-dot').styles(
      width: YsLayout.statusDot.px,
      height: YsLayout.statusDot.px,
      radius: .circular(YsRadius.pill.px),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-conn-dot-connected')
        .styles(backgroundColor: .variable('--success')),
    css('.hermuse-conn-dot-pending')
        .styles(backgroundColor: .variable('--primary')),
    css('.hermuse-conn-dot-error')
        .styles(backgroundColor: .variable('--error')),
    css('.hermuse-conn-action').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
      color: .variable('--primary-2'),
      raw: {'flex-shrink': '0', 'white-space': 'nowrap'},
    ),
    css('.hermuse-conn-action-muted')
        .styles(color: .variable('--content-muted')),
    css('.hermuse-conn-action-error').styles(color: .variable('--primary-2')),
    css('.hermuse-conn-body').styles(
      padding: .only(left: 48.px, right: 14.px, bottom: 12.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(10.px),
    ),
    // A featured sign-in is a taller row: a bigger logo tile, the title a
    // step up; its body still lines up under the title.
    css('.hermuse-conn-featured', [
      css('.hermuse-conn-head').styles(
        padding: .symmetric(vertical: YsSpace.md.px, horizontal: 14.px),
        gap: .all(YsSpace.md.px),
      ),
      css('.hermuse-conn-logo').styles(
        width: YsLayout.activityTileSize.px,
        height: YsLayout.activityTileSize.px,
        radius: .circular(YsRadius.row.px),
        fontSize: YsType.monogram.size.px,
        lineHeight: YsType.monogram.lineHeight.px,
      ),
      css('.hermuse-conn-name').styles(
        fontSize: YsType.heading.size.px,
        lineHeight: YsType.heading.lineHeight.px,
      ),
      css('.hermuse-conn-detail').styles(
        fontSize: YsType.small.size.px,
        lineHeight: YsType.small.lineHeight.px,
      ),
      css('.hermuse-conn-body').styles(
        padding: .only(left: (YsLayout.activityTileSize + YsSpace.md + 14).px),
      ),
    ]),
    css('.hermuse-conn-device').styles(
      padding: .symmetric(vertical: 12.px, horizontal: 12.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      backgroundColor: .variable('--paper-clear'),
    ),
    css('.hermuse-conn-code').styles(
      margin: .zero,
      textAlign: .center,
      fontSize: 22.px,
      lineHeight: 28.px,
      fontWeight: .w600,
      raw: {'letter-spacing': '2px'},
    ),
    css('.hermuse-conn-link').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--primary-2'),
      raw: {'word-break': 'break-all'},
    ),
    css('.hermuse-conn-pool').styles(
      margin: .zero,
      fontSize: 12.px,
      lineHeight: 16.px,
      color: .variable('--content-subtle'),
    ),
    css('.hermuse-conn-row').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-conn-grow').styles(flex: .grow(1), raw: {'min-width': '0'}),
    css('.hermuse-conn-grow .ys-inputbox').styles(width: 100.percent),
    css('.hermuse-conn-models')
        .styles(display: .flex, flexDirection: .column, gap: .all(8.px)),
    css('.hermuse-conn-slot').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-conn-slot-label').styles(
      width: 52.px,
      fontSize: 13.px,
      lineHeight: 18.px,
      fontWeight: .w500,
      color: .variable('--content-muted'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-conn-slot-pick').styles(flex: .grow(1)),
  ];
}

class _HermuseConnectionsState extends State<HermuseConnections> {
  var _query = '';

  /// "Show other providers" unfolded the available providers and the custom
  /// endpoint form.
  var _others = false;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: connectionCardsProvider(component.instance.id),
    builder: (context, connections) => _body(context, connections),
  );

  Component _body(
    BuildContext context,
    AsyncValue<ConnectionsState> connections,
  ) {
    final state = connections.value;
    final needle = _query.trim().toLowerCase();
    bool matches(String text) => text.toLowerCase().contains(needle);
    // A featured sign-in is found by what its row shows, too.
    bool featuredMatches(ConnectionCard card, _SignIn signIn) =>
        matches(card.name) ||
        matches('Sign in with ${signIn.product}') ||
        matches(signIn.plan);
    // Bridge cards sign in through the desktop sidecar only.
    final (signIns, rest) = _featuredSignIns([
      for (final card in state?.cards ?? const <ConnectionCard>[])
        if (card.flow != ConnectionFlow.bridge) card,
    ]);
    final featured = [
      for (final (card, signIn) in signIns)
        if (featuredMatches(card, signIn)) (card, signIn),
    ];
    final others = [
      for (final card in rest)
        if (matches(card.name)) card,
    ];
    final connected = [
      for (final card in others)
        if (card.state == ConnectionCardState.connected) card,
    ];
    final available = [
      for (final card in others)
        if (card.state != ConnectionCardState.connected) card,
    ];
    // Connected providers never fold away and a search shows every match;
    // with no sign-in to feature, the other providers are the whole page.
    final foldable = needle.isEmpty && signIns.isNotEmpty;
    final unfolded = !foldable || _others;
    Component row(ConnectionCard card, [_SignIn? signIn]) => _ConnectionCard(
      key: ValueKey(card.id),
      instanceId: component.instance.id,
      card: card,
      signIn: signIn,
      pendingLogin: state?.pendingLogin,
    );
    Component list(List<Component> rows) =>
        div(classes: 'hermuse-conn-list', rows);
    // The drawing loops while the list loads and shows a pulled plug when
    // it cannot load (desktop `ConnectionsScreen` parity).
    final failed = connections.hasError && state == null;
    return div(classes: 'hermuse-screen hermuse-screen-top', [
      div(classes: 'hermuse-list-card', [
        ?component.lead,
        HermuseDialogHead(
          art: failed ? YsArt.unreachable : YsArt.accounts,
          busy: connections.isLoading,
          title: 'Model accounts',
          helper:
              'Subscriptions and API keys ${component.instance.label} can use.',
          trailing: YsButton.icon(
            icon: YsIcon.close,
            label: 'Back',
            onPressed: component.onBack,
            size: 36,
          ),
        ),
        YsInputBox(
          value: _query,
          onChanged: (v) => setState(() => _query = v),
          placeholder: 'Search connections',
          name: 'connections-search',
          label: 'Search connections',
          icon: YsIcon.search,
          autocomplete: 'off',
        ),
        if (connections.isLoading && state == null)
          HermuseRouteSkeleton(label: 'Loading connections…')
        else if (failed) ...[
          HermuseErrorNotice(
            'Could not load connections: ${connections.error}.',
          ),
          div(classes: 'hermuse-conn-retry-row', [
            YsButton.neutral(
              label: 'Try again',
              onPressed: () => context.container.invalidate(
                connectionCardsProvider(component.instance.id),
              ),
            ),
          ]),
        ] else ...[
          if (featured.isNotEmpty) ...[
            p(classes: 'hermuse-conn-group', [.text('Use your subscription')]),
            list([for (final (card, signIn) in featured) row(card, signIn)]),
          ],
          if (connected.isNotEmpty) ...[
            p(classes: 'hermuse-conn-group', [.text('Connected')]),
            list([for (final card in connected) row(card)]),
          ],
          if (foldable)
            div(classes: 'hermuse-conn-more', [
              YsButton.neutral(
                label: _others
                    ? 'Hide other providers'
                    : 'Show other providers',
                onPressed: () => setState(() => _others = !_others),
              ),
            ]),
          if (unfolded) ...[
            if (available.isNotEmpty) ...[
              p(classes: 'hermuse-conn-group', [.text('Available')]),
              list([for (final card in available) row(card)]),
            ],
            if (featured.isEmpty && others.isEmpty)
              p(classes: 'hermuse-conn-sub', [.text('No connection matches.')]),
            p(classes: 'hermuse-conn-group', [.text('Custom endpoint')]),
            _CustomEndpointCard(instanceId: component.instance.id),
          ],
        ],
      ]),
    ]);
  }
}

/// The product and plan a featured sign-in names in place of its card's
/// name and detail ("Sign in with ChatGPT / Codex", "Use your ChatGPT
/// Plus/Pro subscription").
typedef _SignIn = ({String product, String plan});

/// The subscription sign-ins featured at the top of the page, then every
/// other card (desktop `_featuredSignIns` parity: same rules).
///
/// The Claude Code and Codex subscription-bridge cards are featured.
/// Without bridge cards (the web: no sidecar) the Hermes `openai-codex`
/// device-code card stands in for Codex and Claude is left out: its Hermes
/// sign-in needs a terminal. The other bridges and the Hermes cards a
/// featured bridge replaces (`hermesIds`: `anthropic`, `claude-code`,
/// `openai-codex`) are other providers.
(List<(ConnectionCard, _SignIn)>, List<ConnectionCard>) _featuredSignIns(
  List<ConnectionCard> cards,
) {
  // Matched by name: the web app does not depend on `cliproxy_client`.
  ConnectionCard? bridge(String provider) =>
      cards.where((c) => c.bridgeSpec?.provider.name == provider).firstOrNull;
  bool hermesCodex(ConnectionCard c) =>
      c.id == 'openai-codex' && c.flow == ConnectionFlow.deviceCode;
  final claude = bridge('anthropic');
  final codexBridge = bridge('codex');
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

class _ConnectionCard extends StatefulComponent {
  const _ConnectionCard({
    required this.instanceId,
    required this.card,
    required this.pendingLogin,
    this.signIn,
    super.key,
  });

  final String instanceId;
  final ConnectionCard card;
  final DeviceCodeLogin? pendingLogin;

  /// Set on a featured subscription sign-in: a taller row naming its
  /// product and plan (desktop `_ConnectionCard` parity).
  final _SignIn? signIn;

  @override
  State<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<_ConnectionCard> {
  var _open = false;
  var _key = '';
  var _busy = false;
  String? _error;

  ConnectionCards _cards(BuildContext context) => context.container.read(
    connectionCardsProvider(component.instanceId).notifier,
  );

  @override
  Component build(BuildContext context) {
    final card = component.card;
    final pending = component.pendingLogin;
    final isPending = pending != null && pending.providerId == card.id;
    // An in-flight login keeps its row open.
    final open = _open || isPending || _error != null;
    final connected = card.state == ConnectionCardState.connected;
    // A featured sign-in is a taller row that names its product once signed
    // in and invites to sign in until then; progress and errors replace its
    // plan line.
    final signIn = component.signIn;
    final title = signIn == null
        ? card.name
        : connected
        ? signIn.product
        : 'Sign in with ${signIn.product}';
    final idle = card.state == ConnectionCardState.disconnected;
    final subtitle = signIn != null && (idle || card.detail.isEmpty)
        ? 'Use your ${signIn.plan} subscription'
        : card.detail;
    final itemClasses = signIn == null
        ? 'hermuse-conn-item'
        : 'hermuse-conn-item hermuse-conn-featured';
    final (action, actionClass) = switch ((card.state, card.flow)) {
      (ConnectionCardState.connected, _) => (
        'Manage',
        'hermuse-conn-action-muted',
      ),
      (ConnectionCardState.pending, _) => (
        'Waiting…',
        'hermuse-conn-action-muted',
      ),
      (ConnectionCardState.error, _) => ('Retry', 'hermuse-conn-action-error'),
      (_, ConnectionFlow.external) => ('Terminal', 'hermuse-conn-action-muted'),
      _ => ('Connect', ''),
    };
    // The row's state dot: connected pings once as the row shows; waiting
    // and failed logins keep a still dot.
    final dot = switch (card.state) {
      ConnectionCardState.connected => (YsTheme.success, 'connected'),
      ConnectionCardState.pending => (YsTheme.primary, 'pending'),
      ConnectionCardState.error => (YsTheme.error, 'error'),
      ConnectionCardState.disconnected => null,
    };
    return div(classes: itemClasses, [
      YsPressable(
        onPressed: () => setState(() => _open = !open),
        label: '$title: $action',
        classes: 'hermuse-conn-head',
        builder: (context, press) => .fragment([
          span(classes: 'hermuse-conn-logo', [.text(_letter(card.name))]),
          span(classes: 'hermuse-conn-title', [
            span(classes: 'hermuse-conn-name', [.text(title)]),
            if (subtitle.isNotEmpty && subtitle != title)
              span(classes: 'hermuse-conn-detail', [.text(subtitle)]),
          ]),
          if (dot case (final color, final name))
            YsPing(
              live: connected,
              color: color,
              child: span(
                classes: 'hermuse-conn-dot hermuse-conn-dot-$name',
                [],
              ),
            ),
          span(classes: 'hermuse-conn-action $actionClass'.trim(), [
            .text(action),
          ]),
        ]),
      ),
      if (open)
        div(classes: 'hermuse-conn-body', [
          if (card.flow == ConnectionFlow.deviceCode && !connected)
            _deviceBody(context, card, isPending ? pending : null),
          if (card.flow == ConnectionFlow.apiKey && !connected)
            _keyBody(context, card),
          if (card.flow == ConnectionFlow.external) _externalBody(card),
          if (card.poolEntries.isNotEmpty)
            p(classes: 'hermuse-conn-pool', [
              .text(
                card.poolEntries
                    .map(
                      (e) =>
                          '#${e.index} ${e.label.isEmpty ? e.authType : e.label}'
                          '${e.tokenPreview.isEmpty ? '' : ' ${e.tokenPreview}'}',
                    )
                    .join(' · '),
              ),
            ]),
          if (connected) ...[
            _ModelSlots(instanceId: component.instanceId, card: card),
            div(classes: 'hermuse-conn-row', [
              div(classes: 'hermuse-conn-grow', []),
              YsButton.neutral(
                label: _busy ? 'Working…' : 'Disconnect',
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        try {
                          await _cards(context).disconnect(card.id);
                        } on Object catch (e) {
                          if (mounted) setState(() => _error = '$e');
                        }
                        if (mounted) setState(() => _busy = false);
                      },
              ),
            ]),
          ],
          if (_error case final error?)
            p(classes: 'hermuse-card-error', [.text(error)]),
        ]),
    ]);
  }

  Component _deviceBody(
    BuildContext context,
    ConnectionCard card,
    DeviceCodeLogin? login,
  ) {
    if (login == null) {
      return div(classes: 'hermuse-conn-row', [
        div(classes: 'hermuse-conn-grow', []),
        YsButton.primary(
          label: _busy ? 'Starting…' : 'Connect',
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    final result = await _cards(context)
                        .startDeviceCode(card.id);
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
      ]);
    }
    return div(classes: 'hermuse-conn-device', [
      p(classes: 'hermuse-conn-code', [.text(login.userCode)]),
      a(
        classes: 'hermuse-conn-link',
        href: login.verificationUrl,
        target: .blank,
        [.text(login.verificationUrl)],
      ),
      p(classes: 'hermuse-conn-sub', [
        .text('Enter the code at the link, then wait for approval.'),
      ]),
      div(classes: 'hermuse-conn-row', [
        YsButton.neutral(
          label: 'Open link',
          onPressed: kIsWeb
              ? () => web.window.open(login.verificationUrl, '_blank')
              : null,
        ),
        div(classes: 'hermuse-conn-grow', []),
        YsButton.neutral(
          label: 'Cancel',
          onPressed: () => unawaited(_cards(context).cancelLogin()),
        ),
      ]),
    ]);
  }

  Component _keyBody(BuildContext context, ConnectionCard card) =>
      div(classes: 'hermuse-conn-row', [
        div(classes: 'hermuse-conn-grow', [
          YsInputBox(
            value: _key,
            onChanged: (v) => setState(() => _key = v),
            onSubmitted: () => unawaited(_saveKey(context, card)),
            placeholder: card.keyEnv.isEmpty
                ? 'API key'
                : 'API key (${card.keyEnv})',
            name: 'key-${card.id}',
            label: '${card.name} API key',
            obscure: true,
            autocomplete: 'off',
          ),
        ]),
        YsButton.primary(
          label: _busy ? 'Saving…' : 'Save',
          onPressed: _busy || _key.trim().isEmpty
              ? null
              : () => unawaited(_saveKey(context, card)),
        ),
      ]);

  Future<void> _saveKey(BuildContext context, ConnectionCard card) async {
    final key = _key;
    if (key.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _cards(context).saveApiKey(card.id, key);
      if (mounted) setState(() => _key = '');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Component _externalBody(ConnectionCard card) =>
      p(classes: 'hermuse-conn-sub', [
        .text(
          card.cliCommand.isNotEmpty
              ? 'Sign in from a terminal: ${card.cliCommand}'
              : 'Sign in from a terminal; Hermes picks up the credentials.',
        ),
      ]);

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

  static String _letter(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}

/// The ≤2 selected models of a connected card, with a picker per slot and
/// "Use as default" (large → main, small → auxiliary).
class _ModelSlots extends StatefulComponent {
  const _ModelSlots({required this.instanceId, required this.card});

  final String instanceId;
  final ConnectionCard card;

  @override
  State<_ModelSlots> createState() => _ModelSlotsState();
}

class _ModelSlotsState extends State<_ModelSlots> {
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: modelSelectionProvider(component.instanceId, component.card.id),
    builder: (context, selection) => _body(context, selection),
  );

  Component _body(BuildContext context, AsyncValue<ModelSelection> selection) {
    final current = selection.value;
    if (selection.isLoading && current == null) {
      return p(classes: 'hermuse-conn-pool', [.text('Loading models…')]);
    }
    if (current == null) {
      return p(classes: 'hermuse-conn-pool', [
        .text('Models unavailable: ${selection.error}'),
      ]);
    }
    final options = [for (final id in current.allModels) (id, id)];
    return div(classes: 'hermuse-conn-models', [
      div(classes: 'hermuse-conn-slot', [
        span(classes: 'hermuse-conn-slot-label', [.text('Large')]),
        div(classes: 'hermuse-conn-slot-pick', [
          YsSelect(
            value: current.large ?? '',
            options: [('', 'None'), ...options],
            onChanged: (v) => unawaited(
              _select(context, ModelTier.large, v.isEmpty ? null : v),
            ),
            label: '${component.card.name} large model',
          ),
        ]),
      ]),
      div(classes: 'hermuse-conn-slot', [
        span(classes: 'hermuse-conn-slot-label', [.text('Small')]),
        div(classes: 'hermuse-conn-slot-pick', [
          YsSelect(
            value: current.small ?? '',
            options: [('', 'None'), ...options],
            onChanged: (v) => unawaited(
              _select(context, ModelTier.small, v.isEmpty ? null : v),
            ),
            label: '${component.card.name} small model',
          ),
        ]),
      ]),
      div(classes: 'hermuse-conn-row', [
        div(classes: 'hermuse-conn-grow', []),
        YsButton.neutral(
          label: _busy ? 'Working…' : 'Use as default',
          onPressed: _busy || current.large == null
              ? null
              : () => unawaited(_makeDefault(context)),
        ),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
    ]);
  }

  Future<void> _select(
    BuildContext context,
    ModelTier tier,
    String? modelId,
  ) async {
    setState(() => _error = null);
    try {
      await context.container
          .read(
            modelSelectionProvider(
              component.instanceId,
              component.card.id,
            ).notifier,
          )
          .select(tier, modelId);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _makeDefault(BuildContext context) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.container
          .read(
            modelSelectionProvider(
              component.instanceId,
              component.card.id,
            ).notifier,
          )
          .makeDefault();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}

class _CustomEndpointCard extends StatefulComponent {
  const _CustomEndpointCard({required this.instanceId});

  final String instanceId;

  @override
  State<_CustomEndpointCard> createState() => _CustomEndpointCardState();
}

class _CustomEndpointCardState extends State<_CustomEndpointCard> {
  var _open = false;
  var _name = '';
  var _baseUrl = '';
  var _apiKey = '';
  var _model = '';
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) {
    if (!_open) {
      return div(classes: 'hermuse-conn-row', [
        div(classes: 'hermuse-conn-grow', []),
        YsButton.neutral(
          label: 'Add custom endpoint',
          onPressed: () => setState(() => _open = true),
        ),
      ]);
    }
    return div(classes: 'hermuse-conn-card', [
      div(classes: 'hermuse-conn-head', [
        div(classes: 'hermuse-conn-title', [
          span(classes: 'hermuse-conn-name', [.text('Custom endpoint')]),
          span(classes: 'hermuse-conn-detail', [
            .text('Any OpenAI-compatible API.'),
          ]),
        ]),
      ]),
      YsField(
        label: 'Name',
        child: YsInputBox(
          value: _name,
          onChanged: (v) => setState(() => _name = v),
          placeholder: 'Local model',
          name: 'endpoint-name',
          label: 'Endpoint name',
        ),
      ),
      YsField(
        label: 'Base URL',
        child: YsInputBox(
          value: _baseUrl,
          onChanged: (v) => setState(() => _baseUrl = v),
          placeholder: 'http://localhost:1234/v1',
          name: 'endpoint-url',
          label: 'Endpoint base URL',
          autocomplete: 'off',
        ),
      ),
      YsField(
        label: 'API key (optional)',
        child: YsInputBox(
          value: _apiKey,
          onChanged: (v) => setState(() => _apiKey = v),
          placeholder: 'sk-…',
          name: 'endpoint-key',
          label: 'Endpoint API key',
          obscure: true,
          autocomplete: 'off',
        ),
      ),
      YsField(
        label: 'Model (optional)',
        child: YsInputBox(
          value: _model,
          onChanged: (v) => setState(() => _model = v),
          placeholder: 'model id',
          name: 'endpoint-model',
          label: 'Endpoint model',
          autocomplete: 'off',
        ),
      ),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
      div(classes: 'hermuse-conn-row', [
        div(classes: 'hermuse-conn-grow', []),
        YsButton.neutral(
          label: 'Cancel',
          onPressed: _busy ? null : () => setState(() => _open = false),
        ),
        YsButton.primary(
          label: _busy ? 'Adding…' : 'Add',
          onPressed: _busy || _name.trim().isEmpty || _baseUrl.trim().isEmpty
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await context.container
                        .read(
                          connectionCardsProvider(component.instanceId)
                              .notifier,
                        )
                        .addCustomEndpoint(
                          name: _name.trim(),
                          baseUrl: _baseUrl.trim(),
                          apiKey: _apiKey,
                          model: _model.trim(),
                        );
                    if (mounted) {
                      setState(() {
                        _open = false;
                        _name = '';
                        _baseUrl = '';
                        _apiKey = '';
                        _model = '';
                      });
                    }
                  } on Object catch (e) {
                    if (mounted) setState(() => _error = '$e');
                  }
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ]),
    ]);
  }
}
