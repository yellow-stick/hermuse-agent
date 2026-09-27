import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Paper card of the product pages: r22, 20 padding, 12 gaps (web parity).
final class ProductCard extends StatelessWidget {
  const ProductCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.bubble),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// h36 pill toggle (Love / Discuss / nav pills): primary when [on].
final class ProductPill extends StatelessWidget {
  const ProductPill({
    required this.label,
    required this.on,
    required this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final bool on;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      builder: (context, state) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? palette.primaryColor : palette.neutralAmbientColor,
          borderRadius: BorderRadius.circular(YsRadius.pill),
        ),
        child: Text(
          label,
          style: YsType.label.flutter.copyWith(
            color: on ? palette.primaryContentColor : palette.contentColor,
          ),
        ),
      ),
    );
  }
}

/// Text field + action button on one row (feedback, goal notes).
final class ProductInputRow extends StatelessWidget {
  const ProductInputRow({
    required this.controller,
    required this.placeholder,
    required this.action,
    required this.busy,
    required this.onSubmit,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String action;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Row(
      children: [
        Expanded(
          child: YsInputBox(
            controller: controller,
            placeholder: placeholder,
            semanticLabel: placeholder,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        YsButton.primary(
          label: busy ? '…' : action,
          onPressed: busy || controller.text.trim().isEmpty ? null : onSubmit,
        ),
      ],
    ),
  );
}
