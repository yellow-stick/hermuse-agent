# hermuse_chat

The Hermuse chat domain in plain Dart: message and flight models, the immutable
[ChatState], and [ChatController] which applies every user action. The Flutter
app (`apps/hermuse_app`) and the Jaspr app (`apps/hermuse_web`) render the same state
and call the same controller, so behaviour cannot drift between them.

No networking: sending a message appends it to the thread. An agent backend
plugs in behind the controller.
