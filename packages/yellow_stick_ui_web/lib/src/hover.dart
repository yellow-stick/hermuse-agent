import 'package:jaspr/jaspr.dart';

/// Tracks the pointer over a region that is not a button (an empty state,
/// an illustration) and hands it to [builder]. The listeners go on the
/// element [builder] returns; nothing wraps it.
class YsHover extends StatefulComponent {
  const YsHover({required this.builder, super.key});

  final Component Function(BuildContext context, bool hovered) builder;

  @override
  State<YsHover> createState() => _YsHoverState();
}

class _YsHoverState extends State<YsHover> {
  var _hovered = false;

  @override
  Component build(BuildContext context) => Component.wrapElement(
    events: {
      'mouseenter': (_) => setState(() => _hovered = true),
      'mouseleave': (_) => setState(() => _hovered = false),
    },
    child: component.builder(context, _hovered),
  );
}
