import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:riverpod/misc.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';

/// Relay-required screen: no Hermuse relay answers on this page's origin.
///
/// The web app can only reach Hermes through the same-origin relay (browsers
/// block direct cross-origin calls), so without a relay there is nothing to
/// configure — no instance form, no connection attempt.
class HermuseRelayRequired extends StatelessComponent {
  const HermuseRelayRequired({super.key});

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-screen', [
    div(classes: 'hermuse-card', [
      div(classes: 'hermuse-card-icon', [YsIconView(YsIcon.chat, size: 28)]),
      h1(classes: 'hermuse-card-title', [.text('A Hermuse relay is required')]),
      p(classes: 'hermuse-card-body', [
        .text(
          'This web app reaches your Hermes instances through a Hermuse '
          'relay on the same origin — browsers cannot talk to Hermes '
          'directly. No relay answers at this address, so there is nothing '
          'to connect to yet.',
        ),
      ]),
      p(classes: 'hermuse-card-body hermuse-card-hint', [
        .text(
          'If you run this site, serve it through the relay '
          '(HERMUSE_RELAY_STATIC_DIR) and open the relay address. '
          'Otherwise use the Hermuse desktop or mobile app instead.',
        ),
      ]),
    ]),
  ]);

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => hermuseScreenStyles;
}

/// Shared full-screen card styles (relay-required, welcome, instances…).
List<StyleRule> get hermuseScreenStyles => [
  css('.hermuse-screen', [
    css('&').styles(
      flex: .grow(1),
      height: 100.percent,
      display: .flex,
      alignItems: .center,
      justifyContent: .center,
      backgroundColor: .variable('--canvas'),
      raw: {'min-height': '0'},
    ),
    css('&.hermuse-screen-top').styles(
      alignItems: .start,
      overflow: .only(y: .auto, x: .hidden),
    ),
    css('.hermuse-card').styles(
      width: 100.percent,
      maxWidth: YsLayout.dialogWidth.px,
      margin: .symmetric(horizontal: 24.px),
      padding: .symmetric(vertical: 32.px, horizontal: 28.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      alignItems: .center,
      gap: .all(16.px),
      color: .variable('--content'),
      backgroundColor: .variable('--paper'),
    ),
    css('.hermuse-card-narrow').styles(maxWidth: YsLayout.dialogNarrow.px),
    css('.hermuse-card-icon').styles(
      width: 56.px,
      height: 56.px,
      radius: .circular(28.px),
      display: .flex,
      alignItems: .center,
      justifyContent: .center,
      color: .variable('--primary-content'),
      backgroundColor: .variable('--primary'),
    ),
    css('.hermuse-card-title').styles(
      margin: .zero,
      textAlign: .center,
      fontSize: 22.px,
      lineHeight: 28.px,
      fontWeight: .w500,
    ),
    css('.hermuse-card-body').styles(
      margin: .zero,
      textAlign: .center,
      fontSize: 16.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-card-hint').styles(fontSize: 13.px, lineHeight: 18.px),
    css('.hermuse-card-error').styles(
      margin: .zero,
      textAlign: .center,
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--primary-2'),
    ),
    css('.hermuse-card-actions').styles(
      display: .flex,
      flexDirection: .row,
      flexWrap: .wrap,
      justifyContent: .center,
      gap: .all(12.px),
      margin: .only(top: 8.px),
    ),
    // Full-width primary call to action.
    css('.hermuse-card-cta').styles(
      width: 100.percent,
      display: .flex,
      margin: .only(top: 8.px),
    ),
    css('.hermuse-card-cta > .ys-btn-filled')
        .styles(width: 100.percent, height: 40.px),
    // Secondary actions: quiet text links under the call to action.
    css('.hermuse-card-links').styles(
      display: .flex,
      flexDirection: .row,
      flexWrap: .wrap,
      justifyContent: .center,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-card-links-dot').styles(color: .variable('--content-subtle')),
    css('.hermuse-card-link', [
      css('&').styles(
        padding: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content-muted'),
        cursor: .pointer,
        border: .none,
        backgroundColor: Colors.transparent,
        raw: {'white-space': 'nowrap'},
      ),
      css('&:hover').styles(color: .variable('--content')),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
  ]),
];

/// Reads [provider] and rebuilds the subtree when it notifies.
class HermuseWatch<T> extends StatefulComponent {
  const HermuseWatch({
    required this.provider,
    required this.builder,
    super.key,
  });

  final ProviderListenable<T> provider;
  final Component Function(BuildContext context, T value) builder;

  @override
  State<HermuseWatch<T>> createState() => _HermuseWatchState<T>();
}

class _HermuseWatchState<T> extends State<HermuseWatch<T>> {
  ProviderSubscription<T>? _sub;
  T? _value;
  ProviderListenable<T>? _listened;

  ProviderContainer _container(BuildContext context) => HermuseScope.container;

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  void _resubscribe(BuildContext context) {
    if (_listened == component.provider) return;
    _sub?.close();
    _listened = component.provider;
    final sub = _container(context).listen<T>(component.provider, (_, next) {
      if (mounted) setState(() => _value = next);
    });
    _sub = sub;
    _value = sub.read();
  }

  @override
  Component build(BuildContext context) {
    _resubscribe(context);
    return component.builder(context, _value as T);
  }
}

/// A [ChatController] listener that calls `setState` (Jaspr's equivalent of
/// the Flutter `ChatListenable`).
mixin ChatListenerMixin<T extends StatefulComponent> on State<T> {
  ChatController? _listened;

  /// Keeps `setState` wired to [controller] across rebuilds.
  void syncChatListener(ChatController controller) {
    if (identical(_listened, controller)) return;
    _listened?.removeListener(_onChatChanged);
    _listened = controller;
    controller.addListener(_onChatChanged);
  }

  void _onChatChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listened?.removeListener(_onChatChanged);
    super.dispose();
  }
}
