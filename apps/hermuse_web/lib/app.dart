import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'chat_root.dart';

/// Server-rendered app shell: static document body hosting [HermuseChatRoot].
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) =>
      div(classes: 'hermuse-app', [HermuseChatRoot()]);

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-app')
        .styles(height: 100.vh, display: .flex, flexDirection: .column),
  ];
}
