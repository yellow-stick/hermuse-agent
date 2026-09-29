import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'button.dart';

/// A dialog: centered card over a backdrop scrim.
///
/// Used for goal detail, confirmations and pickers. [onClose] fires from the
/// ✕ button, a click on the scrim and Escape. Modal for keyboard users:
/// focus moves into the dialog when it opens, Tab stays inside it, and
/// focus returns to the element that had it (the opener) once it closes.
class YsDialog extends StatefulComponent {
  const YsDialog({
    required this.title,
    required this.onClose,
    required this.child,
    this.actions = const [],
    this.wide = false,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Component child;

  /// Footer buttons (usually one primary + one neutral).
  final List<Component> actions;

  /// Wide (640) instead of default (480) card.
  final bool wide;

  @override
  State<YsDialog> createState() => _YsDialogState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-dialog-root', [
      css('&').styles(
        position: .absolute(top: 0.px, left: 0.px),
        width: 100.percent,
        height: 100.percent,
        display: .flex,
        alignItems: .center,
        justifyContent: .center,
        raw: {'z-index': '40'},
      ),
      css('.ys-dialog-scrim').styles(
        position: .absolute(top: 0.px, left: 0.px),
        width: 100.percent,
        height: 100.percent,
        backgroundColor: .variable('--backdrop'),
      ),
      css('.ys-dialog').styles(
        width: 100.percent,
        maxWidth: YsLayout.dialogWidth.px,
        maxHeight: 90.percent,
        margin: .symmetric(horizontal: 24.px),
        padding: .symmetric(vertical: 20.px, horizontal: 20.px),
        radius: .circular(YsRadius.bubble.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(16.px),
        position: .relative(),
        color: .variable('--content'),
        backgroundColor: .variable('--paper'),
        raw: {'overflow-y': 'auto', 'outline': 'none'},
      ),
      css('.ys-dialog-wide').styles(maxWidth: YsLayout.listWidth.px),
      css('.ys-dialog-head').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
      ),
      // The heading token, like the Flutter kit's dialog title.
      css('.ys-dialog-title').styles(
        margin: .zero,
        flex: .grow(1),
        fontSize: YsType.heading.size.px,
        lineHeight: YsType.heading.lineHeight.px,
        fontWeight: .w500,
      ),
      css('.ys-dialog-body')
          .styles(display: .flex, flexDirection: .column, gap: .all(12.px)),
      css('.ys-dialog-actions').styles(
        display: .flex,
        flexDirection: .row,
        justifyContent: .end,
        gap: .all(12.px),
      ),
    ]),
  ];
}

class _YsDialogState extends State<YsDialog> {
  static const _focusable =
      'button:not([disabled]), [href], input:not([disabled]), '
      'select:not([disabled]), textarea:not([disabled]), '
      '[tabindex]:not([tabindex="-1"])';

  final _dialog = GlobalNodeKey<web.HTMLElement>();
  web.Element? _opener;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _opener = web.document.activeElement;
    context.binding.addPostFrameCallback(() {
      if (mounted) _dialog.currentNode?.focus();
    });
  }

  @override
  void dispose() {
    final opener = _opener;
    if (opener != null && opener.isConnected) {
      (opener as web.HTMLElement).focus();
    }
    super.dispose();
  }

  void _onKey(web.Event event) {
    final keyboard = event as web.KeyboardEvent;
    if (keyboard.key == 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      component.onClose();
    } else if (keyboard.key == 'Tab') {
      _keepTabInside(keyboard);
    }
  }

  /// Wraps Tab / Shift+Tab at the first and last focusable controls.
  void _keepTabInside(web.KeyboardEvent event) {
    final dialog = _dialog.currentNode;
    if (dialog == null) return;
    final focusable = dialog.querySelectorAll(_focusable);
    if (focusable.length == 0) {
      event.preventDefault();
      return;
    }
    final first = focusable.item(0)! as web.HTMLElement;
    final last = focusable.item(focusable.length - 1)! as web.HTMLElement;
    final active = web.document.activeElement;
    final atStart =
        active == null || active.isSameNode(first) || active.isSameNode(dialog);
    if (event.shiftKey && atStart) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active != null && active.isSameNode(last)) {
      event.preventDefault();
      first.focus();
    }
  }

  @override
  Component build(BuildContext context) => div(classes: 'ys-dialog-root', [
    div(
      classes: 'ys-dialog-scrim',
      events: {'click': (_) => component.onClose()},
      [],
    ),
    div(
      key: _dialog,
      classes: component.wide ? 'ys-dialog ys-dialog-wide' : 'ys-dialog',
      attributes: {
        'role': 'dialog',
        'aria-modal': 'true',
        'aria-label': component.title,
        'tabindex': '-1',
      },
      events: {'keydown': _onKey},
      [
        div(classes: 'ys-dialog-head', [
          h2(classes: 'ys-dialog-title', [.text(component.title)]),
          YsButton.icon(
            icon: YsIcon.close,
            label: 'Close',
            onPressed: component.onClose,
            size: 32,
          ),
        ]),
        div(classes: 'ys-dialog-body', [component.child]),
        if (component.actions.isNotEmpty)
          div(classes: 'ys-dialog-actions', component.actions),
      ],
    ),
  ]);
}
