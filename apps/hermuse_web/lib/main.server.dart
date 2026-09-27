/// The entrypoint for the **server** environment.
///
/// Pre-renders the Hermuse chat page (title 'Hermuse', theme styles, conversation
/// HTML) to static output.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

// Imports the [App] component.
import 'app.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      title: 'Hermuse',
      lang: 'en',
      meta: {
        'theme-color': '#181819',
        'description': 'Hermuse — your personal agent',
        'color-scheme': 'dark',
        // Installed on iOS: standalone window, opaque status bar (the layout
        // does not handle safe-area insets, so content stays below it).
        'apple-mobile-web-app-capable': 'yes',
        'apple-mobile-web-app-status-bar-style': 'black',
        'apple-mobile-web-app-title': 'Hermuse',
        'mobile-web-app-capable': 'yes',
      },
      styles: ysThemeStyles,
      head: [
        link(rel: 'manifest', href: '/manifest.webmanifest'),
        link(rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml'),
        link(rel: 'icon', href: '/icons/favicon-48.png', type: 'image/png'),
        link(rel: 'apple-touch-icon', href: '/icons/apple-touch-icon.png'),
        script(content: _registerServiceWorker),
      ],
      body: const App(),
    ),
  );
}

/// Registers `web/sw.js` after load so it never competes with first paint.
const _registerServiceWorker = '''
if ('serviceWorker' in navigator) {
  addEventListener('load', () => navigator.serviceWorker.register('/sw.js'));
}
''';
