import 'dart:math' as math;

import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_icon_widget.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';

/// One entry of a [YsMenuAnchor] menu.
final class YsMenuItem {
  const YsMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.checked,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final YsIcon? icon;

  /// State of a checkbox item (check mark when true); null for a plain item.
  final bool? checked;

  /// Destructive action (Delete): drawn in the error colour.
  final bool destructive;

  /// False for an informational entry (an exact date): muted, not pickable.
  final bool enabled;
}

/// Opens and closes the menu of a [YsMenuAnchor].
abstract interface class YsMenuController {
  bool get isOpen;

  /// Opens the menu below [anchor]'s box (the [YsMenuAnchor] child by
  /// default), or at the global [position] for a context menu.
  void open({BuildContext? anchor, Offset? position});

  void close();
}

/// Raised popover surface of menus: paper, hairline border, drop shadow.
final class YsMenuSurface extends StatelessWidget {
  const YsMenuSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
        border: Border.all(color: palette.lineColor, width: ysHairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YsRadius.row),
        child: child,
      ),
    );
  }
}

/// Action menu ("…" and right-click menus) anchored to the widget
/// [builder] returns.
///
/// The menu opens in the nearest [Overlay] over a transparent scrim, below
/// its anchor (above it when there is no room below) and kept inside the
/// overlay. Up/Down/Home/End move between items, Enter/Space pick one,
/// Escape or a click outside closes it; focus then returns where it was.
final class YsMenuAnchor extends StatefulWidget {
  const YsMenuAnchor({
    required this.semanticLabel,
    required this.items,
    required this.builder,
    this.onOpenChanged,
    super.key,
  });

  /// Names the menu for assistive technologies.
  final String semanticLabel;
  final List<YsMenuItem> items;
  final Widget Function(BuildContext context, YsMenuController menu) builder;

  /// Called when the menu opens or closes (e.g. to keep its row active).
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<YsMenuAnchor> createState() => _YsMenuAnchorState();
}

final class _YsMenuAnchorState extends State<YsMenuAnchor>
    implements YsMenuController {
  final _portal = OverlayPortalController();

  /// Anchor box in overlay coordinates.
  Rect _anchor = Rect.zero;
  FocusNode? _returnFocus;

  @override
  bool get isOpen => _portal.isShowing;

  @override
  void open({BuildContext? anchor, Offset? position}) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Rect rect;
    if (position != null) {
      rect = overlay.globalToLocal(position) & Size.zero;
    } else {
      final box = (anchor ?? context).findRenderObject()! as RenderBox;
      rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    }
    if (_portal.isShowing) {
      setState(() => _anchor = rect);
      return;
    }
    _anchor = rect;
    _returnFocus = FocusManager.instance.primaryFocus;
    _portal.show();
    widget.onOpenChanged?.call(true);
  }

  @override
  void close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    widget.onOpenChanged?.call(false);
    _restoreFocus();
  }

  void _restoreFocus() {
    final back = _returnFocus;
    _returnFocus = null;
    if (back != null && (back.context?.mounted ?? false)) back.requestFocus();
  }

  @override
  void dispose() {
    // The anchor went away with its menu open (its row was removed): hand
    // focus back once the tree settles.
    if (_returnFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreFocus());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => _MenuLayer(
      anchor: _anchor,
      semanticLabel: widget.semanticLabel,
      items: widget.items,
      onClose: close,
    ),
    child: widget.builder(context, this),
  );
}

/// Scrim + positioned menu, focused while open.
final class _MenuLayer extends StatefulWidget {
  const _MenuLayer({
    required this.anchor,
    required this.semanticLabel,
    required this.items,
    required this.onClose,
  });

  final Rect anchor;
  final String semanticLabel;
  final List<YsMenuItem> items;
  final VoidCallback onClose;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

final class _MenuLayerState extends State<_MenuLayer> {
  late final _scope = FocusScopeNode(debugLabel: 'YsMenu', onKeyEvent: _onKey);
  late List<FocusNode> _items = _nodes();

  List<FocusNode> _nodes() => [
    for (final item in widget.items) FocusNode(debugLabel: item.label),
  ];

  @override
  void initState() {
    super.initState();
    // Park focus on the menu: keys reach it, no item looks selected until an
    // arrow key moves into the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scope.requestFocus();
    });
  }

  @override
  void didUpdateWidget(_MenuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final node in _items) {
        node.dispose();
      }
      _items = _nodes();
    }
  }

  @override
  void dispose() {
    for (final node in _items) {
      node.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    final count = _items.length;
    final current = _items.indexWhere((n) => n.hasPrimaryFocus);
    final int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = current < 0 ? 0 : (current + 1) % count;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = current < 0 ? count - 1 : (current - 1 + count) % count;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = count - 1;
    } else {
      return KeyEventResult.ignored;
    }
    _items[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            onSecondaryTap: widget.onClose,
          ),
        ),
        CustomSingleChildLayout(
          delegate: _MenuPosition(widget.anchor),
          child: FocusScope(
            node: _scope,
            child: Semantics(
              role: SemanticsRole.menu,
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: widget.semanticLabel,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
                child: YsMenuSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, item) in widget.items.indexed)
                            _MenuItemRow(
                              item: item,
                              focusNode: _items[i],
                              onPicked: () {
                                widget.onClose();
                                item.onSelected();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

final class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({
    required this.item,
    required this.focusNode,
    required this.onPicked,
  });

  final YsMenuItem item;
  final FocusNode focusNode;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final color = !item.enabled
        ? palette.contentMutedColor
        : item.destructive
        ? palette.errorColor
        : palette.contentColor;
    final icon = item.icon;
    final checked = item.checked;
    return Semantics(
      container: true,
      role: checked == null
          ? SemanticsRole.menuItem
          : SemanticsRole.menuItemCheckbox,
      button: true,
      enabled: item.enabled,
      checked: checked,
      child: YsPressable(
        onPressed: item.enabled ? onPicked : null,
        focusNode: focusNode,
        excludeSemantics: true,
        builder: (context, state) => AnimatedContainer(
          duration: const Duration(milliseconds: YsMotion.fast),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: state.hovered || state.focused || state.pressed
                ? palette.neutralFilmColor
                : palette.neutralFilmColor.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(YsRadius.row - 4),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                YsIconWidget(icon, size: 16, color: color),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: const YsTextStyle(
                    14,
                    20,
                  ).flutter.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              if (checked != null) ...[
                const SizedBox(width: 12),
                SizedBox.square(
                  dimension: 16,
                  child: checked
                      ? YsIconWidget(
                          YsIcon.check,
                          size: 16,
                          color: palette.primaryInkColor,
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Below the anchor (above when it does not fit), left edges aligned, kept
/// [_margin] inside the overlay.
final class _MenuPosition extends SingleChildLayoutDelegate {
  const _MenuPosition(this.anchor);

  final Rect anchor;

  static const _margin = 8.0;
  static const _gap = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = size.width - _margin - childSize.width;
    final x = math.max(_margin, math.min(anchor.left, maxX));
    var y = anchor.bottom + _gap;
    if (y + childSize.height > size.height - _margin) {
      final above = anchor.top - _gap - childSize.height;
      y = above >= _margin
          ? above
          : math.max(_margin, size.height - _margin - childSize.height);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuPosition oldDelegate) =>
      anchor != oldDelegate.anchor;
}
