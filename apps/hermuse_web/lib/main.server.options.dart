// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:hermuse_web/add_instance.dart' as _add_instance;
import 'package:hermuse_web/app.dart' as _app;
import 'package:hermuse_web/browser_card.dart' as _browser_card;
import 'package:hermuse_web/chat_root.dart' as _chat_root;
import 'package:hermuse_web/computer_viewer.dart' as _computer_viewer;
import 'package:hermuse_web/connections.dart' as _connections;
import 'package:hermuse_web/feed.dart' as _feed;
import 'package:hermuse_web/goals.dart' as _goals;
import 'package:hermuse_web/ideas.dart' as _ideas;
import 'package:hermuse_web/instances.dart' as _instances;
import 'package:hermuse_web/library.dart' as _library;
import 'package:hermuse_web/markdown_view.dart' as _markdown_view;
import 'package:hermuse_web/mascot.dart' as _mascot;
import 'package:hermuse_web/message.dart' as _message;
import 'package:hermuse_web/onboarding.dart' as _onboarding;
import 'package:hermuse_web/panel.dart' as _panel;
import 'package:hermuse_web/rail.dart' as _rail;
import 'package:hermuse_web/route.dart' as _route;
import 'package:hermuse_web/scope.dart' as _scope;
import 'package:hermuse_web/screens.dart' as _screens;
import 'package:hermuse_web/sidebar.dart' as _sidebar;
import 'package:hermuse_web/thread.dart' as _thread;
import 'package:yellow_stick_ui_web/src/art.dart' as _art;
import 'package:yellow_stick_ui_web/src/avatar.dart' as _avatar;
import 'package:yellow_stick_ui_web/src/burst.dart' as _burst;
import 'package:yellow_stick_ui_web/src/button.dart' as _button;
import 'package:yellow_stick_ui_web/src/choice_card.dart' as _choice_card;
import 'package:yellow_stick_ui_web/src/dialog.dart' as _dialog;
import 'package:yellow_stick_ui_web/src/done_box.dart' as _done_box;
import 'package:yellow_stick_ui_web/src/fields.dart' as _fields;
import 'package:yellow_stick_ui_web/src/icon.dart' as _icon;
import 'package:yellow_stick_ui_web/src/menu.dart' as _menu;
import 'package:yellow_stick_ui_web/src/motion.dart' as _motion;
import 'package:yellow_stick_ui_web/src/motion_icon.dart' as _motion_icon;
import 'package:yellow_stick_ui_web/src/ping.dart' as _ping;
import 'package:yellow_stick_ui_web/src/pressable.dart' as _pressable;
import 'package:yellow_stick_ui_web/src/segmented_tabs.dart' as _segmented_tabs;
import 'package:yellow_stick_ui_web/src/skeleton.dart' as _skeleton;
import 'package:yellow_stick_ui_web/src/stepper.dart' as _stepper;
import 'package:yellow_stick_ui_web/src/text_area.dart' as _text_area;
import 'package:yellow_stick_ui_web/src/text_field.dart' as _text_field;
import 'package:yellow_stick_ui_web/src/theme.dart' as _theme;
import 'package:yellow_stick_ui_web/src/tooltip.dart' as _tooltip;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _chat_root.HermuseChatRoot: ClientTarget<_chat_root.HermuseChatRoot>(
      'chat_root',
    ),
  },
  styles: () => [
    ..._chat_root.hermuseShellStyles,
    ..._motion.ysMotionStyles,
    ..._theme.ysThemeStyles,
    ..._add_instance.HermuseAddInstance.styles,
    ..._app.App.styles,
    ..._browser_card.HermuseBrowserCard.styles,
    ..._computer_viewer.HermuseComputerViewer.styles,
    ..._connections.HermuseConnections.styles,
    ..._feed.HermuseFeed.styles,
    ..._feed.HermusePluginMissing.styles,
    ..._goals.HermuseGoals.styles,
    ..._ideas.HermuseIdeas.styles,
    ..._instances.HermuseInstances.styles,
    ..._instances.HermuseWelcome.styles,
    ..._library.HermuseLibrary.styles,
    ..._markdown_view.HermuseMarkdown.styles,
    ..._mascot.HermuseMascot.styles,
    ..._message.HermuseChoice.styles,
    ..._message.HermuseOfferRow.styles,
    ..._message.MessageRow.styles,
    ..._onboarding.HermuseOnboarding.styles,
    ..._panel.HermusePanel.styles,
    ..._rail.HermuseRail.styles,
    ..._route.HermuseRouteEmpty.styles,
    ..._route.HermuseRouteSkeleton.styles,
    ..._scope.HermuseScope.styles,
    ..._screens.HermuseRelayRequired.styles,
    ..._sidebar.HermuseSidebar.styles,
    ..._thread.HermuseThread.styles,
    ..._thread.HermuseThreadHeader.styles,
    ..._art.YsArtView.styles,
    ..._avatar.YsAvatar.styles,
    ..._burst.YsBurstView.styles,
    ..._button.YsFilledButton.styles,
    ..._button.YsIconButton.styles,
    ..._button.YsPillButton.styles,
    ..._choice_card.YsChoiceCard.styles,
    ..._dialog.YsDialog.styles,
    ..._done_box.YsDoneBox.styles,
    ..._fields.YsField.styles,
    ..._fields.YsInputBox.styles,
    ..._fields.YsSelect.styles,
    ..._fields.YsTextBox.styles,
    ..._icon.YsIconView.styles,
    ..._menu.YsMenu.styles,
    ..._motion_icon.YsMotionIconView.styles,
    ..._ping.YsPing.styles,
    ..._pressable.YsPressable.resetStyles,
    ..._segmented_tabs.YsSegmentedTabs.styles,
    ..._skeleton.YsSkeleton.styles,
    ..._stepper.YsStepper.styles,
    ..._text_area.YsTextArea.styles,
    ..._text_field.YsTextField.styles,
    ..._tooltip.YsTooltip.styles,
  ],
);
