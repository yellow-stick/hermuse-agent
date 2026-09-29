/// Stroke icons, 24x24 viewBox.
///
/// Paths adapted from Lucide (https://lucide.dev, ISC License). Only `path`,
/// `rect` and `circle` are used so every renderer (flutter_svg, the DOM) draws
/// them identically.
enum YsIcon {
  chat('<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>'),
  search('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>'),
  feed(
    '<path d="M2 6h4"/><path d="M2 10h4"/><path d="M2 14h4"/><path d="M2 18h4"/>'
    '<rect width="16" height="20" x="4" y="2" rx="2"/><path d="M9.5 8h5"/>'
    '<path d="M9.5 12H16"/><path d="M9.5 16H14"/>',
  ),
  ideas(
    '<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 '
    '.2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>',
  ),
  goals(
    '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="m9 12 2 2 4-4"/>',
  ),
  library(
    '<path d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 '
    '8.9a.7.7 0 0 1-.572 1.1Z"/><rect x="3" y="14" width="7" height="7" rx="1"/>'
    '<circle cx="17.5" cy="17.5" r="3.5"/>',
  ),
  download(
    '<path d="M12 15V3"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>'
    '<path d="m7 10 5 5 5-5"/>',
  ),
  menu('<path d="M4 9h16"/><path d="M4 15h16"/>'),
  more(
    '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/>'
    '<circle cx="19" cy="12" r="1"/>',
  ),
  sideChat(
    '<path d="M14 9a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2z"/>'
    '<path d="M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1"/>',
  ),
  gift(
    '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13"/>'
    '<path d="M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7"/><path d="M7.5 8a2.5 '
    '2.5 0 0 1 0-5A4.8 8 0 0 1 12 8a4.8 8 0 0 1 4.5-5 2.5 2.5 0 0 1 0 5"/>',
  ),
  smile(
    '<circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/>'
    '<path d="M9 9h.01"/><path d="M15 9h.01"/>',
  ),
  reply('<path d="M9 17 4 12 9 7"/><path d="M20 18v-2a4 4 0 0 0-4-4H4"/>'),
  copy(
    '<rect width="14" height="14" x="8" y="8" rx="2"/>'
    '<path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  ),
  check('<path d="M20 6 9 17l-5-5"/>'),
  plus('<path d="M5 12h14"/><path d="M12 5v14"/>'),
  mic(
    '<path d="M12 19v3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/>'
    '<rect x="9" y="2" width="6" height="13" rx="3"/>',
  ),
  send('<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>'),
  stop(
    '<rect width="10" height="10" x="7" y="7" rx="2" fill="currentColor" stroke="none"/>',
  ),
  chevronDown('<path d="m6 9 6 6 6-6"/>'),
  chevronRight('<path d="m9 18 6-6-6-6"/>'),
  close('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'),
  pencil(
    '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l'
    '-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/>'
    '<path d="m15 5 4 4"/>',
  ),
  activity(
    '<path d="M3 5h.01"/><path d="M3 12h.01"/><path d="M3 19h.01"/>'
    '<path d="M8 5h13"/><path d="M8 12h13"/><path d="M8 19h13"/>',
  ),
  approvals(
    '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 '
    '13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 '
    '17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
  ),
  upcoming(
    '<path d="M12 2a10 10 0 1 0 10 10"/><path d="M12 6v6l3 2"/>'
    '<path d="M16 3.3a10 10 0 0 1 4.7 4.7"/>',
  ),
  identity(
    '<path d="M12 10a2 2 0 0 0-2 2c0 1.02-.1 2.51-.26 4"/><path d="M14 13.12c0 '
    '2.38 0 6.38-1 8.88"/><path d="M17.29 21.02c.12-.6.43-2.3.5-3.02"/>'
    '<path d="M2 12a10 10 0 0 1 18-6"/><path d="M2 16h.01"/><path d="M21.8 16c.2-2 '
    '.131-5.354 0-6"/><path d="M5 19.5C5.5 18 6 15 6 12a6 6 0 0 1 .34-2"/>'
    '<path d="M8.65 22c.21-.66.45-1.32.57-2"/><path d="M9 6.8a6 6 0 0 1 9 5.2v2"/>',
  ),
  webSearch(
    '<path d="M21 12a9 9 0 1 0-9 9"/><path d="M3.6 9h16.8"/><path d="M3.6 15H11"/>'
    '<path d="M11.5 3a17 17 0 0 0 0 18"/><path d="M12.5 3a17 17 0 0 1 3 8"/>'
    '<circle cx="18" cy="18" r="3"/><path d="m20.2 20.2 1.8 1.8"/>',
  ),
  checkCircle('<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>'),
  arrowLeft('<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>'),
  chevronLeft('<path d="m15 18-6-6 6-6"/>'),
  pin(
    '<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 '
    '0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78'
    '-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 '
    '0 1 1 1z"/>',
  ),
  archive(
    '<rect width="20" height="5" x="2" y="3" rx="1"/>'
    '<path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
  ),
  trash(
    '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>'
    '<path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>',
  ),
  panelLeft(
    '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/>',
  ),
  maximize(
    '<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="m3 21 7-7"/>'
    '<path d="M9 21H3v-6"/>',
  ),
  minus('<path d="M5 12h14"/>'),

  /// System packages.
  package(
    '<path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l'
    '-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/>'
    '<path d="M12 22V12"/><path d="M3.29 7 12 12l8.71-5"/>'
    '<path d="m7.5 4.27 9 5.15"/>',
  ),

  /// The system keyring.
  keyRound(
    '<path d="M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 1-1'
    'v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 1.414-'
    '.586l.814-.814a6.5 6.5 0 1 0-4-4z"/>'
    '<circle cx="16.5" cy="7.5" r=".5" fill="currentColor"/>',
  ),

  /// Docker.
  container(
    '<path d="M22 7.7c0-.6-.4-1.2-.8-1.5l-6.3-3.9a1.72 1.72 0 0 0-1.7 0l-10.3 '
    '6c-.5.2-.9.8-.9 1.4v6.6c0 .5.4 1.2.8 1.5l6.3 3.9a1.72 1.72 0 0 0 1.7 0l'
    '10.3-6c.5-.3.9-1 .9-1.5Z"/><path d="M10 21.9V14L2.1 9.1"/>'
    '<path d="m10 14 11.9-6.9"/><path d="M14 19.8v-8.1"/>'
    '<path d="M18 17.5V9.4"/>',
  ),

  /// Hermes Agent, the agent runtime.
  bot(
    '<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/>'
    '<path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/>'
    '<path d="M9 13v2"/>',
  ),

  /// A plugin.
  puzzle(
    '<path d="M15.39 4.39a1 1 0 0 0 1.68-.474 2.5 2.5 0 1 1 3.014 3.015 1 1 0 0 '
    '0-.474 1.68l1.683 1.682a2.414 2.414 0 0 1 0 3.414L19.61 15.39a1 1 0 0 1-'
    '1.68-.474 2.5 2.5 0 1 0-3.014 3.015 1 1 0 0 1 .474 1.68l-1.683 1.682a'
    '2.414 2.414 0 0 1-3.414 0L8.61 19.61a1 1 0 0 0-1.68.474 2.5 2.5 0 1 1-'
    '3.014-3.015 1 1 0 0 0 .474-1.68l-1.683-1.682a2.414 2.414 0 0 1 0-3.414'
    'L4.39 8.61a1 1 0 0 1 1.68.474 2.5 2.5 0 1 0 3.014-3.015 1 1 0 0 1-.474-'
    '1.68l1.683-1.682a2.414 2.414 0 0 1 3.414 0z"/>',
  ),

  /// The subscription bridge.
  link(
    '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>'
    '<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  ),

  /// The agent's computer.
  monitor(
    '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8"/>'
    '<path d="M12 17v4"/>',
  );

  const YsIcon(this.body);

  /// Inner SVG markup, stroked with `currentColor`.
  final String body;

  /// Complete SVG document. [color] is any CSS colour; the default
  /// `currentColor` lets the DOM inherit the text colour.
  String svg({String color = 'currentColor', double strokeWidth = 1.75}) =>
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
      'viewBox="0 0 24 24" fill="none" stroke="$color" '
      'stroke-width="$strokeWidth" stroke-linecap="round" '
      'stroke-linejoin="round">$body</svg>';
}

/// Filled status glyph: green disc with a lightning bolt ("Connected").
String ysConnectedSvg(String color) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" '
    'viewBox="0 0 16 16"><circle cx="8" cy="8" r="8" fill="$color"/>'
    '<path d="M8.9 3.2 4.8 8.9h2.6l-.5 3.9 4.3-5.9H8.5z" fill="#0b1f0f"/></svg>';
