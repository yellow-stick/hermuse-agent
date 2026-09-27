import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'browser_card.dart';
import 'message.dart';
import 'scope.dart';
import 'screens.dart';

/// Scrollable conversation column (max 768 centred): connection banner,
/// messages, composer pinned at the bottom.
class HermuseThread extends StatelessComponent {
  const HermuseThread({
    this.switching = false,
    required this.thread,
    required this.instanceId,
    required this.controller,
    required this.connection,
    required this.connectionError,
    required this.needsSignIn,
    required this.onRetry,
    required this.busy,
    required this.onInterrupt,
    required this.selectedOffers,
    required this.onToggleReaction,
    required this.onReply,
    required this.onCopy,
    required this.copiedId,
    required this.onChoose,
    required this.onSelectOffer,
    required this.customAnswer,
    required this.onCustomAnswer,
    required this.draft,
    required this.onDraft,
    required this.onSend,
    required this.replyTo,
    required this.onCancelReply,
    super.key,
  });

  final Thread thread;

  /// Instance of the open chat (drives the model picker).
  final String instanceId;

  /// Chat controller (drives the per-thread model switch).
  final ChatController controller;

  /// Link state to the Hermes instance (drives the banner).
  final ChatConnection connection;
  final String? connectionError;

  /// True when the failure is auth (banner shows sign-in, not Retry).
  final bool needsSignIn;
  final VoidCallback onRetry;

  /// Another conversation is loading: this one stays visible, dimmed and
  /// inert, until it replaces it.
  final bool switching;

  /// True while the agent turn runs (shows the stop button).
  final bool busy;
  final VoidCallback onInterrupt;

  final Map<String, String> selectedOffers;
  final ValueChanged<String> onToggleReaction;
  final ValueChanged<String> onReply;
  final ValueChanged<String> onCopy;
  final String? copiedId;
  final void Function(String messageId, String answer, int blockIndex) onChoose;
  final void Function(String messageId, String offerId) onSelectOffer;
  final String customAnswer;
  final ValueChanged<String> onCustomAnswer;
  final String draft;
  final ValueChanged<String> onDraft;
  final VoidCallback onSend;
  final Message? replyTo;
  final VoidCallback onCancelReply;

  @override
  Component build(BuildContext context) {
    final replyTo = this.replyTo;
    return main_(
      classes: switching
          ? 'hermuse-thread hermuse-thread-switching'
          : 'hermuse-thread',
      attributes: {if (switching) 'aria-busy': 'true'},
      [
        if (connection != ChatConnection.ready) _banner(),
        div(
          classes: 'hermuse-thread-scroll',
          attributes: {'role': 'log', 'aria-label': 'Conversation'},
          [
            div(classes: 'hermuse-thread-column', [
              p(classes: 'hermuse-timestamp', [.text(thread.startedAt)]),
              for (var i = 0; i < thread.messages.length; i++)
                div(
                  classes: 'hermuse-msg-slot',
                  styles: Styles(
                    margin: i == 0
                        ? Margin.only(top: 16.px)
                        : thread.messages[i].author ==
                              thread.messages[i - 1].author
                        ? Margin.only(top: 8.px)
                        : Margin.only(top: 16.px),
                  ),
                  [
                    MessageRow(
                      message: thread.messages[i],
                      position: groupPositionAt(thread.messages, i),
                      selectedOffer: selectedOffers[thread.messages[i].id],
                      onToggleReaction: () =>
                          onToggleReaction(thread.messages[i].id),
                      onReply: () => onReply(thread.messages[i].id),
                      onCopy: () => onCopy(thread.messages[i].id),
                      copied: copiedId == thread.messages[i].id,
                      onChoose: (answer, blockIndex) =>
                          onChoose(thread.messages[i].id, answer, blockIndex),
                      onSelectOffer: (offerId) =>
                          onSelectOffer(thread.messages[i].id, offerId),
                      customAnswer: customAnswer,
                      onCustomAnswer: onCustomAnswer,
                      instanceId: instanceId,
                      taskTitle: browserTaskTitle(thread.title),
                      onOpenComputer: controller.openComputer,
                    ),
                  ],
                ),
            ]),
          ],
        ),
        div(classes: 'hermuse-composer-dock', [
          div(classes: 'hermuse-composer-column', [
            _ModelPicker(instanceId: instanceId, controller: controller),
            if (replyTo != null)
              div(classes: 'hermuse-reply-preview', [
                YsIconView(YsIcon.reply, size: 16),
                span(classes: 'hermuse-reply-text', [
                  span(classes: 'hermuse-reply-label', [.text('Replying to ')]),
                  .text(replyTo.plainText),
                ]),
                YsButton.icon(
                  icon: YsIcon.close,
                  label: 'Cancel reply',
                  onPressed: onCancelReply,
                  size: 27,
                ),
              ]),
            div(classes: 'hermuse-composer', [
              div(classes: 'hermuse-composer-attach', [
                YsTooltip(
                  label: 'Attach file',
                  child: YsButton.icon(
                    icon: YsIcon.plus,
                    label: 'Attach file',
                    onPressed: null,
                    size: 32,
                  ),
                ),
              ]),
              div(classes: 'hermuse-composer-input', [
                YsTextArea(
                  value: draft,
                  onChanged: onDraft,
                  onSubmitted: onSend,
                  placeholder: 'Message',
                  name: 'message',
                ),
              ]),
              div(classes: 'hermuse-composer-trailing', [
                if (busy)
                  YsPressable(
                    onPressed: onInterrupt,
                    label: 'Stop',
                    classes: 'hermuse-stop',
                    builder: (context, press) =>
                        YsIconView(YsIcon.close, size: 18),
                  )
                else if (draft.trim().isEmpty)
                  YsTooltip(
                    label: 'Voice',
                    child: YsButton.icon(
                      icon: YsIcon.mic,
                      label: 'Voice',
                      onPressed: null,
                      size: 32,
                    ),
                  )
                else
                  YsPressable(
                    onPressed: onSend,
                    label: 'Send',
                    classes: 'hermuse-send',
                    builder: (context, press) =>
                        YsIconView(YsIcon.send, size: 18),
                  ),
              ]),
            ]),
          ]),
        ]),
      ],
    );
  }

  Component _banner() {
    if (connection == ChatConnection.error && needsSignIn) {
      return _SignInBanner(
        instanceId: instanceId,
        error: connectionError,
        onSignedIn: onRetry,
      );
    }
    final (icon, text) = switch (connection) {
      ChatConnection.connecting => (YsIcon.upcoming, 'Connecting…'),
      ChatConnection.reconnecting => (
        YsIcon.upcoming,
        connectionError == null
            ? 'Reconnecting…'
            : 'Reconnecting… ($connectionError)',
      ),
      ChatConnection.error => (
        YsIcon.close,
        connectionError ?? 'Connection failed',
      ),
      ChatConnection.ready => (YsIcon.check, ''),
    };
    return div(classes: 'hermuse-conn-banner', [
      YsIconView(icon, size: 16),
      span(classes: 'hermuse-conn-text', [.text(text)]),
      if (connection == ChatConnection.error)
        YsPressable(
          onPressed: onRetry,
          label: 'Retry connection',
          classes: 'hermuse-conn-retry',
          builder: (context, press) => span([.text('Retry')]),
        ),
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-thread', [
      css('&').styles(
        flex: .grow(1),
        display: .flex,
        flexDirection: .column,
        position: .relative(),
        raw: {'min-width': '0', 'min-height': '0'},
      ),
      css('&.hermuse-thread-switching').styles(
        opacity: 0.55,
        raw: {'pointer-events': 'none', 'transition': 'opacity 120ms ease'},
      ),
      css('.hermuse-thread-scroll').styles(
        flex: .grow(1),
        overflow: .only(y: .auto, x: .hidden),
        raw: {'min-height': '0'},
      ),
      css('.hermuse-thread-column').styles(
        maxWidth: YsLayout.threadMaxWidth.px,
        margin: .symmetric(horizontal: .auto),
        padding: .only(
          top: YsLayout.threadTopPad.px,
          left: YsLayout.threadGutter.px,
          right: YsLayout.threadGutter.px,
          bottom: YsLayout.threadBottomPad.px,
        ),
        display: .flex,
        flexDirection: .column,
      ),
      css('.hermuse-timestamp').styles(
        margin: .zero,
        textAlign: .center,
        fontSize: 12.px,
        lineHeight: 16.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-msg-slot').styles(display: .flex, flexDirection: .column),
      // Connection banner pinned under the floating header.
      css('.hermuse-conn-banner').styles(
        position: .absolute(top: 56.px, left: 0.px, right: 0.px),
        maxWidth: YsLayout.threadMaxWidth.px,
        margin: .symmetric(horizontal: .auto),
        padding: .symmetric(vertical: 8.px, horizontal: 16.px),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        color: .variable('--content-muted'),
        backgroundColor: .variable('--paper-clear'),
        fontSize: 13.px,
        lineHeight: 18.px,
        raw: {'z-index': '5', 'margin-left': '16px', 'margin-right': '16px'},
      ),
      css('.hermuse-conn-text').styles(
        flex: .grow(1),
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-conn-retry').styles(
        padding: .symmetric(vertical: 4.px, horizontal: 12.px),
        radius: .circular(YsRadius.pill.px),
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
        cursor: .pointer,
        border: .none,
        fontSize: 13.px,
        fontWeight: .w600,
      ),
      // Composer docked under the scroll area (in flow, 16 below): an
      // overlaid composer hid the last message, worst on phones.
      css('.hermuse-composer-dock').styles(
        padding: .only(bottom: 16.px),
        display: .flex,
        justifyContent: .center,
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-composer-column').styles(
        width: 100.percent,
        maxWidth: YsLayout.threadMaxWidth.px,
        margin: .symmetric(horizontal: 16.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(8.px),
      ),
      // A tab resting on the composer's top edge, so the quote reads as
      // part of the message box.
      css('.hermuse-reply-preview').styles(
        padding: .only(left: 14.px, right: 8.px, top: 6.px, bottom: 6.px),
        // Cancels the column gap: the tab sits flush on the composer.
        margin: .only(left: 24.px, right: 24.px, bottom: (-8).px),
        radius: .only(topLeft: .circular(14.px), topRight: .circular(14.px)),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        color: .variable('--content-muted'),
        backgroundColor: .variable('--neutral-ambient'),
        fontSize: 13.px,
        lineHeight: 18.px,
      ),
      css('.hermuse-reply-label')
          .styles(color: .variable('--content'), fontWeight: .w500),
      css('.hermuse-reply-text').styles(
        flex: .grow(1),
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-composer').styles(
        minHeight: YsLayout.composerHeight.px,
        radius: .circular(YsRadius.composer.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        backgroundColor: .variable('--paper-clear'),
        border: .all(
          style: .solid,
          color: .variable('--line'),
          width: ysHairline.px,
        ),
        raw: {'backdrop-filter': 'blur(12px)'},
      ),
      css('.hermuse-composer-attach').styles(
        padding: .only(left: 8.px),
        color: .variable('--content-muted'),
      ),
      css('.hermuse-composer-input').styles(
        flex: .grow(1),
        padding: .symmetric(vertical: 17.px, horizontal: 8.px),
      ),
      css('.hermuse-composer-trailing').styles(
        padding: .only(right: 8.px),
        color: .variable('--content-muted'),
      ),
      css('.hermuse-send').styles(
        width: 32.px,
        height: 32.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
        cursor: .pointer,
        border: .none,
      ),
      css('.hermuse-send:hover')
          .styles(backgroundColor: .variable('--primary-2')),
      css('.hermuse-send:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
      // Stop button: neutral disc while the turn runs.
      css('.hermuse-stop').styles(
        width: 32.px,
        height: 32.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-ambient'),
        cursor: .pointer,
        border: .none,
      ),
      css('.hermuse-stop:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-stop:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
      // Per-turn model picker above the composer.
      css('.hermuse-modelpick').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
      ),
      css('.hermuse-modelpick-label').styles(
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-modelpick-select').styles(flex: .grow(1)),
      css('.hermuse-modelpick-select .ys-select').styles(height: 36.px),
      // Inline sign-in form (replaces Retry when credentials are stale).
      css('.hermuse-signin').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(8.px),
        flex: .grow(1),
      ),
      css('.hermuse-signin-grow').styles(flex: .grow(1)),
      css('.hermuse-signin-row').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
      ),
      css('.hermuse-signin-fields').styles(
        display: .flex,
        flexDirection: .row,
        gap: .all(8.px),
        flex: .grow(1),
      ),
      css('.hermuse-signin-fields .ys-inputbox')
          .styles(height: 36.px, fontSize: 14.px, lineHeight: 20.px),
      css('.hermuse-signin-error').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--primary-2'),
      ),
    ]),
  ];
}

/// Display title of a side chat: the agent names it after the first
/// message; until then (empty title) it is "New side chat".
String sideChatTitle(String title) => title.isEmpty ? 'New side chat' : title;

/// Floating thread header: the "Chats" pill over the main chat,
/// "Back to main chat" + a pill titled with the side chat over a side chat.
/// Both pills open the chats panel; nothing shows while it is open.
class HermuseThreadHeader extends StatelessComponent {
  const HermuseThreadHeader({
    required this.state,
    required this.panelOpen,
    required this.onOpenPanel,
    required this.onBackToMain,
    super.key,
  });

  final ChatState state;
  final bool panelOpen;
  final VoidCallback onOpenPanel;
  final VoidCallback onBackToMain;

  @override
  Component build(BuildContext context) {
    if (panelOpen) return .fragment([]);
    final thread = state.activeThread;
    final side = thread.id != state.mainThread.id;
    return div(classes: 'hermuse-floating-left hermuse-thread-head', [
      if (side)
        YsTooltip(
          side: YsTooltipSide.below,
          label: 'Back to main chat',
          child: YsPressable(
            onPressed: onBackToMain,
            label: 'Back to main chat',
            classes: 'hermuse-thread-back',
            builder: (context, press) => YsIconView(YsIcon.arrowLeft, size: 18),
          ),
        ),
      YsButton.pill(
        icon: YsIcon.menu,
        label: side ? sideChatTitle(thread.title) : 'Chats',
        tooltip: 'Open chat and side chats',
        onPressed: onOpenPanel,
      ),
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-thread-head', [
      css('&').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        raw: {'max-width': 'calc(100% - 24px)'},
      ),
      css('.ys-btn-pill').styles(raw: {'min-width': '0', 'max-width': '320px'}),
      css('.ys-btn-pill-label').styles(
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap', 'min-width': '0'},
      ),
      css('.hermuse-thread-back').styles(
        width: YsLayout.pillHeight.px,
        height: YsLayout.pillHeight.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content'),
        backgroundColor: .variable('--paper-clear'),
        cursor: .pointer,
        border: .none,
        raw: {'backdrop-filter': 'blur(12px)', 'flex-shrink': '0'},
      ),
      css('.hermuse-thread-back:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-thread-back:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
  ];
}

/// Inline sign-in form shown when the connection failed with auth: proves
/// the new credentials via [InstanceAuth.signIn], then retries the chat.
class _SignInBanner extends StatefulComponent {
  const _SignInBanner({
    required this.instanceId,
    required this.error,
    required this.onSignedIn,
  });

  final String instanceId;
  final String? error;
  final VoidCallback onSignedIn;

  @override
  State<_SignInBanner> createState() => _SignInBannerState();
}

class _SignInBannerState extends State<_SignInBanner> {
  var _username = '';
  var _password = '';
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-conn-banner', [
    YsIconView(YsIcon.close, size: 16),
    div(classes: 'hermuse-signin', [
      span(classes: 'hermuse-conn-text', [
        .text(component.error ?? 'Signed out — sign in again to reconnect.'),
      ]),
      div(classes: 'hermuse-signin-row', [
        div(classes: 'hermuse-signin-fields', [
          div(classes: 'hermuse-signin-grow', [
            YsInputBox(
              value: _username,
              onChanged: (v) => setState(() => _username = v),
              onSubmitted: _submit,
              placeholder: 'Username',
              name: 'signin-username',
              label: 'Username',
              autocomplete: 'username',
            ),
          ]),
          div(classes: 'hermuse-signin-grow', [
            YsInputBox(
              value: _password,
              onChanged: (v) => setState(() => _password = v),
              onSubmitted: _submit,
              placeholder: 'Password',
              name: 'signin-password',
              label: 'Password',
              obscure: true,
              autocomplete: 'current-password',
            ),
          ]),
        ]),
        YsPressable(
          onPressed: _busy || _username.isEmpty || _password.isEmpty
              ? null
              : _submit,
          label: 'Sign in',
          classes: 'hermuse-conn-retry',
          builder: (context, press) => span([.text(_busy ? '…' : 'Sign in')]),
        ),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-signin-error', [.text(error)]),
    ]),
  ]);

  Future<void> _submit() async {
    if (_busy || _username.isEmpty || _password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await HermuseScope.container
          .read(instanceAuthProvider)
          .signIn(
            component.instanceId,
            username: _username,
            password: _password,
          );
      if (mounted) {
        setState(() {
          _username = '';
          _password = '';
        });
        component.onSignedIn();
      }
    } on HermesAuthFailed {
      if (mounted) setState(() => _error = 'Wrong username or password.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Composer model picker: the thread's current model ([ChatController.setModel]
/// switches it session-scoped) over the available-models flat union.
class _ModelPicker extends StatelessComponent {
  const _ModelPicker({required this.instanceId, required this.controller});

  final String instanceId;
  final ChatController controller;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: availableModelsProvider(instanceId),
    builder: (context, models) {
      final all = models.value ?? const <AvailableModel>[];
      if (all.isEmpty) return .fragment([]);
      final current = controller.state.model;
      final value = current == null
          ? ''
          : '${current.provider}/${current.model}';
      final known =
          value.isEmpty ||
          all.any(
            (entry) =>
                entry.providerId == current!.provider &&
                entry.modelId == current.model,
          );
      return div(classes: 'hermuse-modelpick', [
        span(classes: 'hermuse-modelpick-label', [.text('Model')]),
        div(classes: 'hermuse-modelpick-select', [
          YsSelect(
            value: known ? value : '',
            options: [
              ('', 'Instance default'),
              for (final model in all)
                (
                  '${model.providerId}/${model.modelId}',
                  '${model.providerName} · ${model.modelId}',
                ),
            ],
            onChanged: (v) {
              if (v.isEmpty) return;
              final slash = v.indexOf('/');
              unawaited(
                controller.setModel(
                  ChatModel(
                    provider: v.substring(0, slash),
                    model: v.substring(slash + 1),
                  ),
                ),
              );
            },
            label: 'Thread model',
          ),
        ]),
      ]);
    },
  );
}
