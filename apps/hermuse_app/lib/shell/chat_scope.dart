import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';

/// Exposes a framework-free [ChatController] as a Flutter [Listenable].
final class ChatListenable extends ChangeNotifier {
  ChatListenable(this.controller) {
    controller.addListener(_onChanged);
  }

  final ChatController controller;

  ChatState get state => controller.state;

  void _onChanged() => notifyListeners();

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }
}

/// Provides the [ChatListenable] to the widget subtree.
final class ChatScope extends InheritedNotifier<ChatListenable> {
  const ChatScope({required super.notifier, required super.child, super.key});

  static ChatListenable of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChatScope>();
    assert(scope != null, 'No ChatScope found in context');
    return scope!.notifier!;
  }

  /// Reads the controller without registering a rebuild dependency.
  static ChatController controllerOf(BuildContext context) {
    final scope =
        context.getElementForInheritedWidgetOfExactType<ChatScope>()?.widget
            as ChatScope?;
    assert(scope != null, 'No ChatScope found in context');
    return scope!.notifier!.controller;
  }

  /// Reads current state without registering a rebuild dependency.
  static ChatState stateOf(BuildContext context) => controllerOf(context).state;
}
