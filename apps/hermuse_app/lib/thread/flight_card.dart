import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

export 'message_row.dart' show MessageRow;

/// Flight results card: title + pressable offer rows.
final class FlightCard extends StatelessWidget {
  const FlightCard({
    required this.message,
    required this.position,
    required this.selectedOfferId,
    required this.controller,
    required this.maxWidth,
    super.key,
  });

  final Message message;
  final GroupPosition position;
  final String? selectedOfferId;
  final ChatController controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => _FlightCard(
    message: message,
    position: position,
    selectedOfferId: selectedOfferId,
    controller: controller,
    maxWidth: maxWidth,
  );
}

final class _FlightCard extends StatelessWidget {
  const _FlightCard({
    required this.message,
    required this.position,
    required this.selectedOfferId,
    required this.controller,
    required this.maxWidth,
  });

  final Message message;
  final GroupPosition position;
  final String? selectedOfferId;
  final ChatController controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final block = message.blocks.whereType<FlightResultsBlock>().first;
    const all = Radius.circular(YsRadius.bubble);
    const tail = Radius.circular(YsRadius.bubbleTail);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: maxWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperColor,
              borderRadius: BorderRadius.only(
                topLeft: position.joinsAbove ? tail : all,
                topRight: all,
                bottomLeft: position.joinsBelow ? tail : all,
                bottomRight: all,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    block.title,
                    style: YsType.label.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < block.offers.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _OfferRow(
                      messageId: message.id,
                      offer: block.offers[i],
                      selected: selectedOfferId == block.offers[i].id,
                      controller: controller,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.messageId,
    required this.offer,
    required this.selected,
    required this.controller,
  });

  final String messageId;
  final FlightOffer offer;
  final bool selected;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: () => controller.selectOffer(messageId, offer.id),
      semanticLabel: offer.headline,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: YsMotion.fast),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected
              ? palette.primaryMutedColor
              : state.hovered
              ? palette.neutralFilmColor
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(YsRadius.row),
          border: selected
              ? Border.all(color: palette.primaryColor, width: ysHairline)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LogoDiscs(marks: offer.marks),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    offer.headline,
                    style: YsType.label.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < offer.legs.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    _LegLine(leg: offer.legs[i]),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    offer.totalDuration,
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentSubtleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _LogoDiscs extends StatelessWidget {
  const _LogoDiscs({required this.marks});

  final List<AirlineMark> marks;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    if (marks.length == 1) {
      return _LogoDisc(mark: marks.first, size: 40, palette: palette);
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: _LogoDisc(mark: marks[0], size: 29, palette: palette),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: palette.paperColor, width: 2),
              ),
              child: _LogoDisc(mark: marks[1], size: 29, palette: palette),
            ),
          ),
        ],
      ),
    );
  }
}

final class _LogoDisc extends StatelessWidget {
  const _LogoDisc({
    required this.mark,
    required this.size,
    required this.palette,
  });

  final AirlineMark mark;
  final double size;
  final YsPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: mark.onLight
          ? palette.logoSurfaceColor
          : palette.neutralAmbientColor,
      shape: BoxShape.circle,
      border: mark.onLight
          ? Border.all(color: palette.lineColor, width: ysHairline)
          : null,
    ),
    alignment: Alignment.center,
    child: Text(
      mark.monogram,
      style: YsType.monogram.flutter.copyWith(
        color: mark.onLight ? Color(mark.foreground) : palette.contentColor,
      ),
    ),
  );
}

final class _LegLine extends StatelessWidget {
  const _LegLine({required this.leg});

  final FlightLeg leg;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            leg.departs,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: ysHairline,
            child: ColoredBox(color: palette.lineColor),
          ),
        ),
        const SizedBox(width: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.neutralAmbientColor,
            borderRadius: BorderRadius.circular(YsRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              leg.duration,
              style: YsType.micro.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: ysHairline,
            child: ColoredBox(color: palette.lineColor),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          leg.arrives,
          style: YsType.small.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
