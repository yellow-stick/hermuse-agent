import 'package:flutter/widgets.dart';

/// Tracks the pointer over a region that is not a button (a feed post, an
/// empty state) and hands it to [builder].
final class YsHover extends StatefulWidget {
  const YsHover({required this.builder, super.key});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<YsHover> createState() => _YsHoverState();
}

final class _YsHoverState extends State<YsHover> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: widget.builder(context, _hovered),
  );
}
