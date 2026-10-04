import 'controller.dart';
import 'models.dart';

/// Bundled portraits; choosing one does not create a server profile.
///
/// [custom] stands for a portrait the Hermuse plugin generated for one
/// profile: it is not in [available] and its images are loaded from the
/// plugin (`/avatar/portrait`, `/avatar/states/<state>`), not bundled.
final class AgentAvatar {
  const AgentAvatar({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultPrompt,
  });

  /// `ui_meta.hermuse.avatar_id` of a generated portrait.
  static const customId = 'custom';

  /// The generated portrait served by the plugin for the agent's profile.
  static const custom = AgentAvatar(
    id: customId,
    name: 'Generated',
    description: 'Portrait generated from a description',
    defaultPrompt:
        'You are a thoughtful personal assistant. Help the user turn '
        'questions and intentions into useful answers and actions.',
  );

  final String id;
  final String name;
  final String description;
  final String defaultPrompt;

  /// Whether this is the generated portrait ([custom]).
  bool get isCustom => id == customId;

  /// The bundled image. [custom] has none: it names the original portrait
  /// as the stand-in for when the generated one cannot be shown.
  String get assetPath =>
      isCustom ? available.first.assetPath : 'agents/$id.webp';

  static const available = <AgentAvatar>[
    AgentAvatar(
      id: 'hermuse',
      name: 'Hermuse',
      description: 'Original Hermuse avatar',
      defaultPrompt:
          'You are Hermuse, a thoughtful personal assistant. Help the '
          'user turn questions and intentions into useful answers and actions.',
    ),
    AgentAvatar(
      id: 'noah',
      name: 'Noah',
      description: 'Curly-haired human',
      defaultPrompt:
          'You are Noah, a personal assistant focused on planning. '
          'Help the user clarify priorities and turn goals into practical steps.',
    ),
    AgentAvatar(
      id: 'aya',
      name: 'Aya',
      description: 'Human with an afro',
      defaultPrompt:
          'You are Aya, a personal research assistant. Distinguish '
          'evidence from assumptions, compare sources and explain uncertainty.',
    ),
    AgentAvatar(
      id: 'oscar',
      name: 'Oscar',
      description: 'Silver-haired human',
      defaultPrompt:
          'You are Oscar, a personal engineering assistant. Help '
          'diagnose problems and design clear, maintainable technical solutions.',
    ),
    AgentAvatar(
      id: 'iris',
      name: 'Iris',
      description: 'Auburn-haired human',
      defaultPrompt:
          'You are Iris, a personal writing assistant. Help the user '
          'express ideas clearly while preserving their voice and intent.',
    ),
    AgentAvatar(
      id: 'rusty',
      name: 'Rusty',
      description: 'Fox',
      defaultPrompt:
          'You are Rusty, a creative personal assistant. Explore '
          'different ideas with the user and make useful possibilities concrete.',
    ),
    AgentAvatar(
      id: 'bao',
      name: 'Bao',
      description: 'Panda',
      defaultPrompt:
          'You are Bao, an organized personal assistant. Help the '
          'user manage projects, follow commitments and keep track of next steps.',
    ),
    AgentAvatar(
      id: 'olive',
      name: 'Olive',
      description: 'Owl',
      defaultPrompt:
          'You are Olive, a personal reading assistant. Explain and '
          'summarize documents faithfully, retaining context and important details.',
    ),
    AgentAvatar(
      id: 'mint',
      name: 'Mint',
      description: 'Mint-colored alien',
      defaultPrompt:
          'You are Mint, an analytical personal assistant. Help the '
          'user reason through information, check assumptions and compare options.',
    ),
    AgentAvatar(
      id: 'nova',
      name: 'Nova',
      description: 'Violet alien',
      defaultPrompt:
          'You are Nova, a curious personal assistant. Explore new '
          'subjects with the user and make unfamiliar concepts understandable.',
    ),
  ];

  /// The avatar named [id]: [custom] for [customId], else a bundled one;
  /// the original portrait for an unknown or missing id.
  static AgentAvatar byId(String? id) {
    if (id == customId) return custom;
    for (final avatar in available) {
      if (avatar.id == id) return avatar;
    }
    return available.first;
  }
}

/// The same state-to-motion mapping on native and web. Callers opt in only
/// for the original agent, and opt out when reduced motion is requested.
String agentAvatarAsset(
  String avatarId, {
  ChatState? chat,
  bool animate = false,
  bool paused = false,
}) {
  final avatar = AgentAvatar.byId(avatarId);
  if (!animate || avatar.id != 'hermuse' || chat == null) {
    return avatar.assetPath;
  }
  final motion = _motion(chat, paused: paused);
  return motion == null ? avatar.assetPath : 'agents/hermuse/$motion.webp';
}

/// Animation states a generated avatar can have, in generation order
/// (`POST /avatar/animate` defaults to all of them).
const customAvatarStates = ['idle', 'thinking', 'replying', 'working'];

/// Motions without a generated clip of their own, shown with another one.
const _customFallback = {
  'searching': 'working',
  'reading': 'working',
  'coding': 'working',
  'browsing': 'working',
  'magic-action': 'working',
  'awaiting-user': 'idle',
  'connecting': 'idle',
  'paused': 'idle',
};

/// The state clip a generated ([AgentAvatar.custom]) avatar shows for
/// [chat], among the [states] the agent has a clip for; null means the
/// static portrait.
///
/// Same motion as [agentAvatarAsset]: tool motions fall back to `working`,
/// waiting motions to `idle`, and a motion without a clip (or an error,
/// reduced motion via `animate: false`) to the portrait.
String? customAvatarState(
  Iterable<String> states, {
  ChatState? chat,
  bool animate = false,
  bool paused = false,
}) {
  if (!animate || chat == null) return null;
  final motion = _motion(chat, paused: paused);
  if (motion == null) return null;
  final available = states.toSet();
  if (available.contains(motion)) return motion;
  final fallback = _customFallback[motion];
  return fallback != null && available.contains(fallback) ? fallback : null;
}

String? _motion(ChatState chat, {required bool paused}) {
  switch (chat.connection) {
    case ChatConnection.connecting:
    case ChatConnection.reconnecting:
      return 'connecting';
    case ChatConnection.error:
      // No error clip has been generated. Never substitute a success gesture.
      return null;
    case ChatConnection.ready:
      break;
  }
  if (paused) return 'paused';
  final messages = chat.activeThread.messages;
  for (final message in messages) {
    if (chat.pendingApprovalIds.contains(message.id)) return 'awaiting-user';
  }
  if (!chat.busy) return 'idle';
  if (messages.isEmpty || messages.last.author != Author.agent) {
    return 'thinking';
  }
  final blocks = messages.last.blocks;
  for (final block in blocks.reversed) {
    switch (block) {
      case BrowserBlock(running: true):
        return 'browsing';
      case ToolCallBlock(running: true, :final name):
        return _toolMotion(name);
      case CommandBlock(running: true):
        return 'magic-action';
      case ChoiceBlock(selected: null):
        return 'awaiting-user';
      default:
        break;
    }
  }
  if (blocks.isEmpty) return 'thinking';
  return switch (blocks.last) {
    TextBlock(:final text) when text.isNotEmpty => 'replying',
    BulletsBlock() || FlightResultsBlock() => 'replying',
    _ => 'thinking',
  };
}

String _toolMotion(String name) {
  if (isBrowserTool(name)) return 'browsing';
  if (name == 'web_search' || name == 'search') return 'searching';
  if (name == 'web_extract' ||
      name == 'read_file' ||
      name == 'read_document' ||
      name == 'pdf_read') {
    return 'reading';
  }
  if (name == 'terminal' ||
      name == 'execute_code' ||
      name == 'write_file' ||
      name == 'patch') {
    return 'coding';
  }
  return 'magic-action';
}
