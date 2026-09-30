import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/brand.dart';
import '../shell/screens.dart' show YsDialogError;
import '../sidebar/side_chats.dart' show sideChatLabel;

import 'message_row.dart';

/// Scrollable conversation column with floating header and composer overlay.
final class ThreadView extends StatefulWidget {
  const ThreadView({
    required this.thread,
    required this.replyTo,
    required this.selectedOffers,
    required this.controller,
    required this.chatsOpen,
    required this.onOpenChats,
    required this.panelOpen,
    required this.onOpenPanel,
    required this.horizontalPadding,
    required this.busy,
    required this.connection,
    required this.connectionError,
    required this.needsSignIn,
    this.showFloatingHeader = true,
    this.instanceId,
    super.key,
  });

  final Thread thread;
  final Message? replyTo;
  final Map<String, String> selectedOffers;
  final ChatController controller;

  /// The chats panel is open: the floating Chats / side chat pills hide.
  final bool chatsOpen;
  final VoidCallback onOpenChats;
  final bool panelOpen;
  final VoidCallback onOpenPanel;
  final double horizontalPadding;

  /// The active thread has a turn in progress: the send button becomes stop.
  final bool busy;

  /// Link state to the Hermes instance (drives the connection banner).
  final ChatConnection connection;
  final String? connectionError;

  /// The link failed with rejected credentials: the banner shows an inline
  /// sign-in form instead of Retry.
  final bool needsSignIn;

  /// Hermes instance of this thread; null hides the composer model picker.
  final String? instanceId;

  /// Whether the floating header (Chats pill, or Back to main chat + side
  /// chat title pill; profile avatar) overlays the thread.
  ///
  /// Compact shells use a top bar instead.
  final bool showFloatingHeader;

  @override
  State<ThreadView> createState() => ThreadViewState();
}

final class ThreadViewState extends State<ThreadView> {
  final _scroll = ScrollController();
  final _composer = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'Message');
  bool _atBottom = true;

  /// Space the overlay covers: composer height + 16 margin + safe area.
  double _overlayReserve =
      YsLayout.composerHeight + 16 + YsLayout.threadBottomPad;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.thread.id != oldWidget.thread.id ||
        widget.thread.messages.length != oldWidget.thread.messages.length) {
      // Reversed list: index 0 (the bottom) stays pinned automatically.
      // Only force-scroll when switching threads.
      if (widget.thread.id != oldWidget.thread.id && _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// Puts [text] in the composer, caret at the end, and focuses it without
  /// sending (Discuss / Start in chat).
  void fillComposer(String text) {
    _composer.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _composerFocus.requestFocus();
    setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    // Reversed: position 0 is the bottom of the conversation.
    final atBottom = _scroll.position.pixels <= 24;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
  }

  void _send() {
    widget.controller.send(_composer.text);
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Stack(
      children: [
        // No fill of its own: the shell paints the canvas, so the hairline
        // of the side-by-side column stays visible.
        LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth =
                (constraints.maxWidth - widget.horizontalPadding * 2).clamp(
                  0.0,
                  YsLayout.threadMaxWidth,
                );
            // Reversed so the conversation starts pinned to the bottom and
            // stays there as messages arrive.
            return ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: EdgeInsets.fromLTRB(
                widget.horizontalPadding,
                YsLayout.threadTopPad,
                widget.horizontalPadding,
                _overlayReserve,
              ),
              itemCount: widget.thread.messages.length + 1,
              itemBuilder: (context, reversedIndex) {
                final index = widget.thread.messages.length - reversedIndex;
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      widget.thread.startedAt,
                      style: YsType.caption.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final messages = widget.thread.messages;
                final message = messages[index - 1];
                final position = groupPositionAt(messages, index - 1);
                final gap = position.joinsAbove ? 8.0 : 16.0;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: YsLayout.threadMaxWidth,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: reversedIndex == 0 ? 0 : gap,
                        ),
                        child: MessageRow(
                          message: message,
                          position: position,
                          selectedOfferId: widget.selectedOffers[message.id],
                          controller: widget.controller,
                          columnWidth: columnWidth,
                          threadTitle: widget.thread.title,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (widget.showFloatingHeader && !widget.chatsOpen)
          Positioned(
            left: 12,
            top: 12,
            // Clear of the avatar on the right.
            right: 60,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ThreadHeader(
                thread: widget.thread,
                controller: widget.controller,
                onOpenChats: widget.onOpenChats,
              ),
            ),
          ),
        if (widget.showFloatingHeader)
          Positioned(
            right: 12,
            top: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.panelOpen) ...[
                  YsPressable(
                    onPressed: widget.onOpenPanel,
                    semanticLabel: 'Open panel',
                    builder: (context, state) =>
                        const YsAvatar(hermuseAvatar, size: 36),
                  ),
                ],
              ],
            ),
          ),
        Positioned(
          left: widget.horizontalPadding,
          right: widget.horizontalPadding,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: YsLayout.threadMaxWidth,
              ),
              child: _ComposerSize(
                onMetrics: (reserve) {
                  if (reserve != _overlayReserve) {
                    setState(() => _overlayReserve = reserve);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.connection != ChatConnection.ready)
                      _ConnectionBanner(
                        connection: widget.connection,
                        error: widget.connectionError,
                        needsSignIn: widget.needsSignIn,
                        instanceId: widget.instanceId,
                        controller: widget.controller,
                        onRetry: widget.controller.retry,
                      ),
                    if (widget.connection != ChatConnection.ready)
                      const SizedBox(height: 8),
                    // Above the composer whenever models are known (web
                    // `.hermuse-composer-column`), not only while replying.
                    if (widget.instanceId case final instanceId?)
                      _ModelPicker(
                        instanceId: instanceId,
                        controller: widget.controller,
                      ),
                    // Flush on the composer: the quote reads as part of it.
                    if (widget.replyTo != null)
                      _ReplyPreview(
                        replyTo: widget.replyTo!,
                        onCancel: widget.controller.cancelReply,
                      ),
                    _Composer(
                      controller: _composer,
                      focusNode: _composerFocus,
                      busy: widget.busy,
                      onSend: _send,
                      onStop: widget.controller.interrupt,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Floating thread header: the "Chats" pill in the main chat; in a
/// side chat, a round "Back to main chat" button and a pill with the side
/// chat title. Both pills open the chats panel.
final class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.thread,
    required this.controller,
    required this.onOpenChats,
  });

  final Thread thread;
  final ChatController controller;
  final VoidCallback onOpenChats;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final main = controller.state.mainThread;
    if (thread.id == main.id) {
      return YsButton.pill(
        label: 'Chats',
        icon: YsIcon.menu,
        onPressed: onOpenChats,
      );
    }
    final title = sideChatLabel(thread.title);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        YsButton.icon(
          icon: YsIcon.arrowLeft,
          onPressed: () => controller.openThread(main.id),
          semanticLabel: 'Back to main chat',
          tooltip: 'Back to main chat',
          size: 36,
          iconSize: 20,
          iconColor: palette.contentColor,
          background: palette.paperClearColor,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: YsButton.pill(
              label: title,
              icon: YsIcon.menu,
              onPressed: onOpenChats,
              semanticLabel: 'Chats: $title',
            ),
          ),
        ),
      ],
    );
  }
}

final class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.replyTo, required this.onCancel});

  final Message replyTo;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    // A tab resting on the composer's top edge (web `.hermuse-reply-preview`).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.neutralAmbientColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Row(
              children: [
                YsIconWidget(
                  YsIcon.reply,
                  size: 16,
                  color: palette.contentMutedColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Replying to ',
                          style: TextStyle(
                            color: palette.contentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(text: replyTo.plainText.replaceAll('\n', ' ')),
                      ],
                    ),
                    style: YsType.small.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                YsButton.icon(
                  icon: YsIcon.close,
                  onPressed: onCancel,
                  semanticLabel: 'Cancel reply',
                  tooltip: 'Cancel reply',
                  size: 27,
                  iconSize: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final hasText = controller.text.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(YsRadius.composer),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperClearColor,
            borderRadius: BorderRadius.circular(YsRadius.composer),
            border: Border.all(color: palette.lineColor, width: ysHairline),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: YsButton.icon(
                      icon: YsIcon.plus,
                      onPressed: () {},
                      semanticLabel: 'Attach file',
                      tooltip: 'Attach file',
                      size: 32,
                      iconSize: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: YsTextArea(
                        controller: controller,
                        focusNode: focusNode,
                        placeholder: 'Message',
                        semanticLabel: 'Message',
                        minLines: 1,
                        maxLines: 8,
                        onChanged: onChanged,
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    // The action morphs: the new glyph turns and grows in
                    // while the old one shrinks away.
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: YsMorphMotion.swap),
                      switchInCurve: YsEase.settle.curve,
                      switchOutCurve: YsEase.standard.curve,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        // Announced from its first frame, like the button
                        // it replaces.
                        alwaysIncludeSemantics: true,
                        child: RotationTransition(
                          turns: Tween(
                            begin: -YsMorphMotion.turn,
                            end: 0.0,
                          ).animate(animation),
                          child: ScaleTransition(
                            scale: Tween(
                              begin: YsMorphMotion.from,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      ),
                      child: busy
                          ? _RoundAction(
                              key: const ValueKey('stop'),
                              onPressed: onStop,
                              semanticLabel: 'Stop',
                              tooltip: 'Stop',
                              icon: YsIcon.stop,
                            )
                          : hasText
                          ? _RoundAction(
                              key: const ValueKey('send'),
                              onPressed: onSend,
                              semanticLabel: 'Send message',
                              icon: YsIcon.send,
                            )
                          : YsButton.icon(
                              key: const ValueKey('voice'),
                              icon: YsIcon.mic,
                              onPressed: () {},
                              semanticLabel: 'Voice',
                              tooltip: 'Voice',
                              size: 32,
                              iconSize: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular primary action (send / stop).
final class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.onPressed,
    required this.semanticLabel,
    required this.icon,
    this.tooltip,
    super.key,
  });

  final VoidCallback onPressed;
  final String semanticLabel;
  final YsIcon icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    Widget button = YsPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: YsMotion.fast),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: state.hovered || state.pressed
              ? palette.primary2Color
              : palette.primaryColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: YsIconWidget(
            icon,
            size: 18,
            color: palette.primaryContentColor,
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = YsTooltip(message: tooltip, child: button);
    }
    return button;
  }
}

/// Banner above the composer while the instance link is not ready. When the
/// failure is rejected credentials ([needsSignIn]), an inline sign-in form
/// replaces the Retry button; a successful sign-in retries the chat.
final class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.connection,
    required this.error,
    required this.needsSignIn,
    required this.instanceId,
    required this.controller,
    required this.onRetry,
  });

  final ChatConnection connection;
  final String? error;
  final bool needsSignIn;
  final String? instanceId;
  final ChatController controller;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final isError = connection == ChatConnection.error;
    final signInId = instanceId;
    if (isError && needsSignIn && signInId != null) {
      return _SignInBanner(instanceId: signInId, controller: controller);
    }
    final label = switch (connection) {
      ChatConnection.connecting => 'Connecting…',
      ChatConnection.reconnecting => 'Reconnecting…',
      ChatConnection.error => error ?? 'Connection failed',
      ChatConnection.ready => '',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: isError
                  ? YsIconWidget(
                      YsIcon.close,
                      size: 12,
                      color: palette.errorColor,
                    )
                  : const YsSpinner(size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: YsType.small.flutter.copyWith(
                  color: isError
                      ? palette.errorColor
                      : palette.contentMutedColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isError) ...[
              const SizedBox(width: 8),
              YsButton.neutral(
                label: 'Retry',
                onPressed: onRetry,
                textStyle: YsType.small,
                height: 28,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline credentials form shown when the instance rejected its stored
/// password (rotated password, expired session): signs in via
/// [InstanceAuth.signIn], then retries the chat controller.
final class _SignInBanner extends ConsumerStatefulWidget {
  const _SignInBanner({required this.instanceId, required this.controller});

  final String instanceId;
  final ChatController controller;

  @override
  ConsumerState<_SignInBanner> createState() => _SignInBannerState();
}

final class _SignInBannerState extends ConsumerState<_SignInBanner> {
  late final TextEditingController _username = TextEditingController();
  late final TextEditingController _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(instanceAuthProvider)
          .signIn(widget.instanceId, username: username, password: password);
      await widget.controller.retry();
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                YsIconWidget(
                  YsIcon.lock,
                  size: YsLayout.inlineIcon,
                  color: palette.errorColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sign in again — the saved password was rejected.',
                    style: YsType.small.flutter.copyWith(
                      color: palette.errorColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            YsInputBox(
              controller: _username,
              placeholder: 'Username',
              semanticLabel: 'Username',
              icon: YsIcon.user,
              onSubmitted: (_) => unawaited(_signIn()),
            ),
            const SizedBox(height: 8),
            YsInputBox(
              controller: _password,
              placeholder: 'Password',
              semanticLabel: 'Password',
              icon: YsIcon.lock,
              obscure: true,
              onSubmitted: (_) => unawaited(_signIn()),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              YsDialogError(error),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: YsButton.primary(
                label: _busy ? 'Signing in…' : 'Sign in',
                onPressed: _busy ? null : () => unawaited(_signIn()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Composer model picker: the thread's current model ([ChatController.setModel]
/// switches it session-scoped) over the available-models flat union.
final class _ModelPicker extends ConsumerWidget {
  const _ModelPicker({required this.instanceId, required this.controller});

  final String instanceId;
  final ChatController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final all =
        ref.watch(availableModelsProvider(instanceId)).value ??
        const <AvailableModel>[];
    if (all.isEmpty) return const SizedBox.shrink();
    final current = controller.state.model;
    final value = current == null ? '' : '${current.provider}/${current.model}';
    final known =
        value.isEmpty ||
        all.any(
          (entry) =>
              entry.providerId == current!.provider &&
              entry.modelId == current.model,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            'Model',
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: YsSelect(
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
                semanticLabel: 'Thread model',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports the overlay size so the list can reserve matching bottom space.
///
/// Measures the whole overlay column (reply preview + composer) plus the 16
/// bottom margin and safe-area inset, so [_ThreadViewState] can reserve the
/// exact space the overlay covers.
final class _ComposerSize extends StatefulWidget {
  const _ComposerSize({required this.onMetrics, required this.child});

  final ValueChanged<double> onMetrics;
  final Widget child;

  @override
  State<_ComposerSize> createState() => _ComposerSizeState();
}

final class _ComposerSizeState extends State<_ComposerSize> {
  Size? _lastSize;
  double _lastBottomPadding = -1;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final size = context.size;
      if (size == null) {
        return;
      }
      if (size != _lastSize || bottomPadding != _lastBottomPadding) {
        _lastSize = size;
        _lastBottomPadding = bottomPadding;
        // Composer + its 16 bottom inset + the thread's own bottom pad, so
        // the last message clears the composer like on the web.
        widget.onMetrics(
          size.height + 16 + bottomPadding + YsLayout.threadBottomPad,
        );
      }
    });
    return widget.child;
  }
}
