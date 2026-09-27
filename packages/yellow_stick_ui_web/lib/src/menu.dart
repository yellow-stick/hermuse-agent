import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'icon.dart';

/// Viewport rectangle a [YsMenu] opens from: a trigger's bounds, or the
/// pointer position of a context menu.
final class YsMenuAnchor {
  const YsMenuAnchor({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const YsMenuAnchor.point(double x, double y)
    : left = x,
      top = y,
      right = x,
      bottom = y;

  /// The current bounds of [element].
  factory YsMenuAnchor.of(web.Element element) {
    final rect = element.getBoundingClientRect();
    return YsMenuAnchor(
      left: rect.left.toDouble(),
      top: rect.top.toDouble(),
      right: rect.right.toDouble(),
      bottom: rect.bottom.toDouble(),
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// One entry of a [YsMenu].
final class YsMenuItem {
  const YsMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.checked,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelected;
  final YsIcon? icon;

  /// Non-null renders a `menuitemcheckbox` in this state (check mark when
  /// on).
  final bool? checked;

  /// Error colour (Delete).
  final bool destructive;
}

/// A popup menu (`role="menu"`) below [anchor], or above it when it does not
/// fit, kept inside the viewport.
///
/// Keyboard: the first item takes focus on open; Arrow Up/Down, Home and End
/// move between items; Enter/Space pick; Escape and Tab close. Every close
/// (pick, Escape, Tab, click outside) returns focus to the element focused
/// when the menu opened — its trigger.
class YsMenu extends StatefulComponent {
  const YsMenu({
    required this.label,
    required this.items,
    required this.anchor,
    required this.onClose,
    super.key,
  });

  /// Accessible name of the menu.
  final String label;
  final List<YsMenuItem> items;
  final YsMenuAnchor anchor;

  /// Asks the owner to remove the menu.
  final VoidCallback onClose;

  @override
  State<YsMenu> createState() => _YsMenuState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-menu-layer').styles(
      position: .fixed(top: 0.px, left: 0.px),
      width: 100.vw,
      height: 100.vh,
      raw: {'z-index': '60'},
    ),
    css('.ys-menu').styles(
      minWidth: 200.px,
      maxWidth: 280.px,
      padding: .all(4.px),
      radius: .circular(14.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(1.px),
      position: .fixed(),
      color: .variable('--content'),
      backgroundColor: .variable('--paper'),
      border: .all(color: .variable('--line'), width: ysHairline.px),
      raw: {
        'z-index': '61',
        'outline': 'none',
        'box-shadow': '0 12px 32px rgba(0, 0, 0, 0.45)',
      },
    ),
    css('.ys-menu-item', [
      css('&').styles(
        width: 100.percent,
        height: 36.px,
        padding: .symmetric(horizontal: 10.px),
        radius: .circular(YsRadius.option.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(10.px),
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        textAlign: .left,
        fontSize: 14.px,
        lineHeight: 20.px,
        raw: {
          'font-family': 'inherit',
          'white-space': 'nowrap',
          'outline': 'none',
        },
      ),
      // Hover focuses the item, so one highlight follows mouse and keys.
      css('&:focus').styles(backgroundColor: .variable('--neutral-film')),
      css('& > .ys-icon').styles(color: .variable('--content-muted')),
      css('&.ys-menu-item-destructive').styles(color: .variable('--error')),
      css('&.ys-menu-item-destructive > .ys-icon')
          .styles(color: .variable('--error')),
    ]),
    css('.ys-menu-label')
        .styles(flex: .grow(1), overflow: .hidden, textOverflow: .ellipsis),
    css('.ys-menu-check').styles(display: .inlineFlex),
  ];
}

class _YsMenuState extends State<YsMenu> {
  static const _gap = 4.0;
  static const _margin = 8.0;

  final _menu = GlobalNodeKey<web.HTMLElement>();
  web.Element? _opener;
  double? _left;
  double? _top;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _opener = web.document.activeElement;
    context.binding.addPostFrameCallback(_place);
  }

  /// Fits the measured menu in the viewport, then focuses the first item
  /// once it is visible (a hidden element cannot take focus).
  void _place() {
    final menu = _menu.currentNode;
    if (!mounted || menu == null) return;
    final anchor = component.anchor;
    final size = menu.getBoundingClientRect();
    final width = size.width.toDouble();
    final height = size.height.toDouble();
    final viewWidth = web.window.innerWidth.toDouble();
    final viewHeight = web.window.innerHeight.toDouble();
    final gap = anchor.bottom > anchor.top ? _gap : 0.0;
    var left = anchor.left;
    if (left + width > viewWidth - _margin) left = anchor.right - width;
    var top = anchor.bottom + gap;
    if (top + height > viewHeight - _margin) top = anchor.top - gap - height;
    setState(() {
      _left = left.clamp(
        _margin,
        math.max(_margin, viewWidth - _margin - width),
      );
      _top = top.clamp(
        _margin,
        math.max(_margin, viewHeight - _margin - height),
      );
    });
    context.binding.addPostFrameCallback(() {
      if (mounted) _items().firstOrNull?.focus();
    });
  }

  List<web.HTMLElement> _items() {
    final found = _menu.currentNode?.querySelectorAll('[role^="menuitem"]');
    if (found == null) return const [];
    return [
      for (var i = 0; i < found.length; i++) found.item(i)! as web.HTMLElement,
    ];
  }

  void _close() {
    final opener = _opener;
    if (opener != null && opener.isConnected) {
      (opener as web.HTMLElement).focus();
    }
    component.onClose();
  }

  void _pick(YsMenuItem item) {
    _close();
    item.onSelected();
  }

  void _onKey(web.Event event) {
    final key = (event as web.KeyboardEvent).key;
    final items = _items();
    final active = web.document.activeElement;
    final at = active == null
        ? -1
        : items.indexWhere((item) => item.isSameNode(active));
    switch (key) {
      case 'ArrowDown':
        if (items.isNotEmpty) items[(at + 1) % items.length].focus();
      case 'ArrowUp':
        if (items.isNotEmpty) {
          items[(at <= 0 ? items.length : at) - 1].focus();
        }
      case 'Home':
        items.firstOrNull?.focus();
      case 'End':
        items.lastOrNull?.focus();
      case 'Escape' || 'Tab':
        _close();
      default:
        return;
    }
    event.preventDefault();
    event.stopPropagation();
  }

  @override
  Component build(BuildContext context) {
    final anchor = component.anchor;
    return .fragment([
      div(
        classes: 'ys-menu-layer',
        events: {
          'click': (_) => _close(),
          'contextmenu': (event) {
            event.preventDefault();
            _close();
          },
        },
        [],
      ),
      div(
        key: _menu,
        classes: 'ys-menu',
        attributes: {
          'role': 'menu',
          'aria-label': component.label,
          'tabindex': '-1',
        },
        styles: Styles(
          raw: {
            'left': '${_left ?? anchor.left}px',
            'top': '${_top ?? anchor.bottom}px',
            // Measured and placed on the first frame.
            if (_left == null) 'visibility': 'hidden',
          },
        ),
        events: {'keydown': _onKey},
        [
          for (final item in component.items)
            button(
              type: .button,
              classes: item.destructive
                  ? 'ys-menu-item ys-menu-item-destructive'
                  : 'ys-menu-item',
              attributes: {
                'role': item.checked == null ? 'menuitem' : 'menuitemcheckbox',
                if (item.checked case final checked?)
                  'aria-checked': '$checked',
                'tabindex': '-1',
              },
              events: {
                'mouseenter': (event) =>
                    (event.currentTarget! as web.HTMLElement).focus(),
              },
              onClick: () => _pick(item),
              [
                if (item.icon case final icon?) YsIconView(icon, size: 18),
                span(classes: 'ys-menu-label', [.text(item.label)]),
                if (item.checked == true)
                  span(classes: 'ys-menu-check', [
                    YsIconView(YsIcon.check, size: 18),
                  ]),
              ],
            ),
        ],
      ),
    ]);
  }
}
