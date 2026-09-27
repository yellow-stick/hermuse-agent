import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Top-level surfaces of the shell (rail + phone bottom bar).
enum HermuseDestination {
  chat(YsIcon.chat, 'Chat'),
  feed(YsIcon.feed, 'Feed'),
  ideas(YsIcon.ideas, 'Ideas'),
  goals(YsIcon.goals, 'Goals'),
  library(YsIcon.library, 'Library');

  const HermuseDestination(this.icon, this.label);
  final YsIcon icon;
  final String label;
}
