import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Icon of a tool row in the chat and of an Activity entry.
YsIcon toolIcon(ToolKind kind) => switch (kind) {
  ToolKind.terminal => YsIcon.terminal,
  ToolKind.web => YsIcon.webSearch,
  ToolKind.browser => YsIcon.globe,
  ToolKind.file => YsIcon.fileText,
  ToolKind.code => YsIcon.code,
  ToolKind.other => YsIcon.wrench,
};
