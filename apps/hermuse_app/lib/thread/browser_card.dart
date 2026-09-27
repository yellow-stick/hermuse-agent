import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../computer/browser_parts.dart';

/// Muse's "Browser" card: the agent's browser in a turn, with the live
/// screen while it works and the picture saved after its last step once
/// done; opens the computer viewer.
final class BrowserCard extends ConsumerStatefulWidget {
  const BrowserCard({
    required this.block,
    required this.title,
    required this.instanceId,
    required this.onOpen,
    super.key,
  });

  final BrowserBlock block;

  /// Task title ([browserTaskTitle]).
  final String title;
  final String instanceId;

  /// Opens the computer viewer.
  final VoidCallback onOpen;

  /// Inner width (Muse).
  static const width = 284.0;

  @override
  ConsumerState<BrowserCard> createState() => _BrowserCardState();
}

final class _BrowserCardState extends ConsumerState<BrowserCard> {
  static const _refresh = Duration(seconds: 2);

  Timer? _timer;

  /// A refresh is in flight: timer ticks skip until it lands.
  bool _refreshing = false;

  /// Bumped when the card switches source (live → saved): late answers of
  /// the previous one are dropped.
  int _generation = 0;
  Uint8List? _picture;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(BrowserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.block;
    final block = widget.block;
    if (widget.instanceId != oldWidget.instanceId ||
        block.running != before.running ||
        (!block.running && block.lastToolId != before.lastToolId)) {
      _follow();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// While the agent works, the computer's screen every 2 s; once done,
  /// the snapshot of its last browser step (the current screen when there
  /// is none).
  void _follow() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    if (widget.block.running) {
      unawaited(_show((computer) => computer.thumbnail()));
      _timer = Timer.periodic(_refresh, (_) {
        if (_refreshing) return;
        _refreshing = true;
        unawaited(
          _show((computer) => computer.thumbnail())
              .whenComplete(() => _refreshing = false),
        );
      });
    } else {
      final toolId = widget.block.lastToolId;
      unawaited(
        _show(
          (computer) async =>
              await computer.snapshot(toolId) ?? await computer.thumbnail(),
        ),
      );
    }
  }

  Future<void> _show(
    Future<Uint8List> Function(ComputerClient computer) load,
  ) async {
    final generation = _generation;
    final Uint8List picture;
    try {
      final computer = await ref.read(
        computerClientProvider(widget.instanceId).future,
      );
      picture = await load(computer);
    } on Object {
      // No picture (computer off, no snapshot, offline): the placeholder,
      // or the last picture, stays.
      return;
    }
    if (mounted && generation == _generation) {
      setState(() => _picture = picture);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the instance's computer client while the card shows.
    ref.watch(computerClientProvider(widget.instanceId));
    final palette = YsTheme.of(context);
    final block = widget.block;
    final running = block.running;
    final status = running
        ? (block.step.isEmpty ? 'Working' : block.step)
        : 'Completed · ${widget.title}';
    final picture = _picture;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BrowserCard.width),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.neutralAmbientColor,
                  borderRadius: BorderRadius.circular(YsRadius.row),
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: running
                        ? const BrowserGlyphIcon(
                            BrowserGlyph.globe,
                            color: browserBlue,
                          )
                        : BrowserGlyphIcon(
                            BrowserGlyph.globeCheck,
                            color: palette.success,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Browser',
                      style: YsType.label.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      status,
                      style: YsType.small.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            button: true,
            label: running ? 'Open browser session' : 'Open browser preview',
            child: YsPressable(
              onPressed: widget.onOpen,
              excludeSemantics: true,
              builder: (context, state) => DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.canvasColor,
                  border: Border.all(color: palette.lineColor),
                  borderRadius: BorderRadius.circular(YsRadius.row),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(YsRadius.row - 1),
                    // 282 × 176 at full width (16:10).
                    child: AspectRatio(
                      aspectRatio: 282 / 176,
                      child: picture == null
                          ? const SizedBox.expand()
                          : FrameImage(picture, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          BrowserPill(
            label: running ? 'Open browser' : 'Open preview',
            onPressed: widget.onOpen,
            foreground: palette.contentColor,
            background: Color(browserPillGrey.value),
          ),
        ],
      ),
    );
  }
}
