import 'dart:async';
import 'dart:typed_data';

import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'scope.dart';

/// Accent of the agent's browser: the working globe and the viewer's
/// primary action.
const browserBlue = Color.rgb(23, 147, 255);

/// Grey pill fill of the browser surfaces (Open browser, Stop in control).
const browserPillGrey = Color.rgb(82, 84, 86);

/// Title of a browser task: its thread's title, or a default while the
/// thread has none.
String browserTaskTitle(String threadTitle) =>
    threadTitle.isEmpty ? 'Browser session' : threadTitle;

/// Keeps the computer client of [instanceId] alive while subscribed; `read()`
/// yields it.
ProviderSubscription<Future<ComputerClient>> listenComputerClient(
  String instanceId,
) => HermuseScope.container.listen(
  computerClientProvider(instanceId).future,
  (_, _) {},
);

/// Browser glyphs missing from [YsIcon], in the same 24-unit stroke style.
enum BrowserGlyph {
  /// Lucide `globe`.
  globe(
    '<circle cx="12" cy="12" r="10"/>'
    '<path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>'
    '<path d="M2 12h20"/>',
  ),

  /// The globe opened at its lower right for a check mark: a finished task.
  globeCheck(
    '<path d="M12 22A10 10 0 1 1 22 12"/>'
    '<path d="M12 2a14.5 14.5 0 0 0 0 20"/>'
    '<path d="M12 2a14.5 14.5 0 0 1 3.9 10"/>'
    '<path d="M2 12h20"/><path d="m15 19 2 2 4-4"/>',
  ),

  /// Ring around a filled dot: the recording agent (Stop).
  record(
    '<circle cx="12" cy="12" r="9"/>'
    '<circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>',
  );

  const BrowserGlyph(this.body);

  /// Inner SVG markup, stroked with `currentColor`.
  final String body;
}

/// A [BrowserGlyph] drawn like [YsIconView] (same `ys-icon` box).
class BrowserGlyphView extends StatelessComponent {
  const BrowserGlyphView(this.glyph, {this.size = 18, super.key});

  final BrowserGlyph glyph;
  final double size;

  @override
  Component build(BuildContext context) => span(
    classes: 'ys-icon',
    styles: Styles(width: size.px, height: size.px),
    [
      RawText(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
        'viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
        '${glyph.body}</svg>',
      ),
    ],
  );
}

/// The agent's browser in a turn: its own bubble, first in the turn, with
/// the status, a thumbnail and the button opening the viewer.
///
/// While the turn runs the thumbnail is the live screen (every 2 s); once
/// it is done, the snapshot saved after its last browser call (the live
/// screen when there is none). Nothing loaded shows the dark placeholder.
class HermuseBrowserCard extends StatefulComponent {
  const HermuseBrowserCard({
    required this.block,
    required this.title,
    required this.instanceId,
    required this.onOpen,
    super.key,
  });

  final BrowserBlock block;

  /// Task title ([browserTaskTitle]), shown once the turn is done.
  final String title;
  final String instanceId;

  /// Opens the computer viewer.
  final VoidCallback onOpen;

  @override
  State<HermuseBrowserCard> createState() => _HermuseBrowserCardState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-browser-card', [
      css('&').styles(
        width: 284.px,
        maxWidth: 100.percent,
        display: .flex,
        flexDirection: .column,
        gap: .all(12.px),
      ),
      css('.hermuse-browser-card-head').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(12.px),
        raw: {'min-width': '0'},
      ),
      css('.hermuse-browser-card-tile').styles(
        width: 40.px,
        height: 40.px,
        radius: .circular(YsRadius.row.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: browserBlue,
        backgroundColor: .variable('--neutral-ambient'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-browser-card-tile-done')
          .styles(color: .variable('--success')),
      css(
        '.hermuse-browser-card-lines',
      ).styles(display: .flex, flexDirection: .column, raw: {'min-width': '0'}),
      css('.hermuse-browser-card-name').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-browser-card-status').styles(
        margin: .zero,
        overflow: .hidden,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-browser-card-thumb').styles(
        width: 100.percent,
        padding: .zero,
        radius: .circular(YsRadius.row.px),
        overflow: .hidden,
        display: .block,
        backgroundColor: .variable('--canvas'),
        cursor: .pointer,
        border: .all(style: .solid, color: .variable('--line'), width: 1.px),
        raw: {'aspect-ratio': '282 / 176'},
      ),
      css('.hermuse-browser-card-img').styles(
        width: 100.percent,
        height: 100.percent,
        display: .block,
        raw: {'object-fit': 'cover', 'pointer-events': 'none'},
      ),
      css('.hermuse-browser-card-open').styles(
        width: 100.percent,
        height: 36.px,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: Colors.white,
        backgroundColor: browserPillGrey,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        cursor: .pointer,
        border: .none,
      ),
      css('.hermuse-browser-card-open:hover')
          .styles(raw: {'filter': 'brightness(1.15)'}),
      css('.hermuse-browser-card-open:active')
          .styles(raw: {'filter': 'brightness(0.9)'}),
      css(
        '.hermuse-browser-card-thumb:focus-visible, '
        '.hermuse-browser-card-open:focus-visible',
      ).styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
  ];
}

class _HermuseBrowserCardState extends State<HermuseBrowserCard> {
  ProviderSubscription<Future<ComputerClient>>? _client;
  Timer? _poll;

  /// Bumped whenever the thumbnail's source changes: answers to an older
  /// request are dropped and its polling stops.
  var _request = 0;

  /// Object URL of the JPEG on screen, and the one it replaced (revoked
  /// when the next one lands, never while an `<img>` may still show it).
  String? _shown;
  String? _replaced;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  @override
  void didUpdateComponent(HermuseBrowserCard oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (!kIsWeb) return;
    final instanceChanged = oldComponent.instanceId != component.instanceId;
    if (instanceChanged) {
      _client?.close();
      _client = null;
    }
    if (instanceChanged ||
        oldComponent.block.running != component.block.running ||
        oldComponent.block.lastToolId != component.block.lastToolId) {
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _client?.close();
    for (final url in [?_shown, ?_replaced]) {
      web.URL.revokeObjectURL(url);
    }
    super.dispose();
  }

  void _load() {
    _poll?.cancel();
    _poll = null;
    unawaited(_refresh(++_request));
  }

  Future<void> _refresh(int request) async {
    final running = component.block.running;
    final toolId = component.block.lastToolId;
    Uint8List? jpeg;
    try {
      final client = await (_client ??= listenComputerClient(
        component.instanceId,
      )).read();
      jpeg = running
          ? await client.thumbnail()
          : await client.snapshot(toolId) ?? await client.thumbnail();
    } on Object {
      // Stopped, unreachable or no plugin: what is shown stays.
    }
    if (!mounted || request != _request) return;
    if (jpeg != null) _show(jpeg);
    if (running) {
      _poll = Timer(
        const Duration(seconds: 2),
        () => unawaited(_refresh(request)),
      );
    }
  }

  void _show(Uint8List jpeg) {
    final url = web.URL.createObjectURL(
      web.Blob([jpeg.toJS].toJS, web.BlobPropertyBag(type: 'image/jpeg')),
    );
    if (_replaced case final stale?) web.URL.revokeObjectURL(stale);
    setState(() {
      _replaced = _shown;
      _shown = url;
    });
  }

  @override
  Component build(BuildContext context) {
    final block = component.block;
    final running = block.running;
    final url = _shown;
    return div(classes: 'hermuse-browser-card', [
      div(classes: 'hermuse-browser-card-head', [
        div(
          classes: running
              ? 'hermuse-browser-card-tile'
              : 'hermuse-browser-card-tile hermuse-browser-card-tile-done',
          [
            BrowserGlyphView(
              running ? BrowserGlyph.globe : BrowserGlyph.globeCheck,
              size: 20,
            ),
          ],
        ),
        div(classes: 'hermuse-browser-card-lines', [
          p(classes: 'hermuse-browser-card-name', [.text('Browser')]),
          p(classes: 'hermuse-browser-card-status', [
            .text(
              running
                  ? (block.step.isEmpty ? 'Working in browser' : block.step)
                  : 'Completed · ${component.title}',
            ),
          ]),
        ]),
      ]),
      YsPressable(
        onPressed: component.onOpen,
        label: running ? 'Open browser session' : 'Open browser preview',
        classes: 'hermuse-browser-card-thumb',
        builder: (context, press) => url == null
            ? .fragment([])
            : img(src: url, alt: '', classes: 'hermuse-browser-card-img'),
      ),
      YsPressable(
        onPressed: component.onOpen,
        classes: 'hermuse-browser-card-open',
        builder: (context, press) =>
            span([.text(running ? 'Open browser' : 'Open preview')]),
      ),
    ]);
  }
}
