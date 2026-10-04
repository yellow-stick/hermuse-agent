import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:test/test.dart';

ChatState state({
  List<Message> messages = const [],
  bool busy = true,
  Set<String> approvals = const {},
}) => ChatState(
  agentName: 'Hermuse',
  threads: [
    Thread(id: 'main', title: 'Main', startedAt: '', messages: messages),
    const Thread(
      id: 'side',
      title: 'Side',
      startedAt: '',
      messages: [
        Message(
          id: 'side-question',
          author: Author.agent,
          blocks: [
            ChoiceBlock(
              prompt: 'Allow?',
              options: ['Yes'],
              customPlaceholder: '',
            ),
          ],
        ),
      ],
    ),
  ],
  activeThreadId: 'main',
  connection: ChatConnection.ready,
  busyThreads: busy ? {'main'} : {},
  pendingApprovalIds: approvals,
);

void main() {
  test(
    'new turn does not reuse the previous reply or a side-chat approval',
    () {
      final chat = state(
        approvals: {'side-question'},
        messages: const [
          Message(
            id: 'old-reply',
            author: Author.agent,
            blocks: [TextBlock('Done')],
          ),
          Message(
            id: 'new-turn',
            author: Author.user,
            blocks: [TextBlock('Next?')],
          ),
        ],
      );
      expect(
        agentAvatarAsset('hermuse', chat: chat, animate: true),
        'agents/hermuse/thinking.webp',
      );
    },
  );

  test('a running tool outranks earlier text until the turn settles', () {
    final chat = state(
      messages: const [
        Message(
          id: 'reply',
          author: Author.agent,
          blocks: [
            TextBlock('I will look it up.'),
            ToolCallBlock(toolId: 'search', name: 'web_search'),
          ],
        ),
      ],
    );
    expect(
      agentAvatarAsset('hermuse', chat: chat, animate: true),
      'agents/hermuse/searching.webp',
    );
    expect(
      agentAvatarAsset(
        'hermuse',
        chat: chat.copyWith(busyThreads: {}),
        animate: true,
      ),
      'agents/hermuse/idle.webp',
    );
  });

  test('reduced motion and new portraits never acquire original clips', () {
    final chat = state();
    expect(
      agentAvatarAsset('hermuse', chat: chat, animate: false),
      'agents/hermuse.webp',
    );
    for (final avatar in AgentAvatar.available.skip(1)) {
      expect(
        agentAvatarAsset(avatar.id, chat: chat, animate: true, paused: true),
        avatar.assetPath,
      );
    }
    expect(
      agentAvatarAsset(
        'hermuse',
        chat: chat.copyWith(connection: ChatConnection.error),
        animate: true,
      ),
      'agents/hermuse.webp',
    );
  });

  test('the generated portrait is its own avatar, outside the picker', () {
    final custom = AgentAvatar.byId('custom');
    expect(custom.id, 'custom');
    expect(custom.isCustom, isTrue);
    expect(identical(custom, AgentAvatar.custom), isTrue);
    expect(AgentAvatar.available.where((a) => a.isCustom), isEmpty);
    expect(AgentAvatar.byId('unknown').id, 'hermuse');
    expect(AgentAvatar.byId(null).id, 'hermuse');
    // Bundled stand-in; never the original's clips.
    expect(custom.assetPath, 'agents/hermuse.webp');
    expect(
      agentAvatarAsset('custom', chat: state(), animate: true),
      'agents/hermuse.webp',
    );
  });

  group('customAvatarState', () {
    const all = customAvatarStates;
    final searching = state(
      messages: const [
        Message(
          id: 'reply',
          author: Author.agent,
          blocks: [ToolCallBlock(toolId: 'search', name: 'web_search')],
        ),
      ],
    );
    final replying = state(
      messages: const [
        Message(
          id: 'reply',
          author: Author.agent,
          blocks: [TextBlock('Here it is.')],
        ),
      ],
    );
    final awaiting = state(
      busy: false,
      approvals: {'question'},
      messages: const [
        Message(
          id: 'question',
          author: Author.agent,
          blocks: [TextBlock('May I?')],
        ),
      ],
    );

    test('generated states show as such', () {
      expect(
        customAvatarState(all, chat: state(busy: false), animate: true),
        'idle',
      );
      expect(customAvatarState(all, chat: state(), animate: true), 'thinking');
      expect(customAvatarState(all, chat: replying, animate: true), 'replying');
    });

    test('tool motions fall back to working, waiting ones to idle', () {
      expect(customAvatarState(all, chat: searching, animate: true), 'working');
      expect(customAvatarState(all, chat: awaiting, animate: true), 'idle');
      expect(
        customAvatarState(
          all,
          chat: state().copyWith(connection: ChatConnection.connecting),
          animate: true,
        ),
        'idle',
      );
      expect(
        customAvatarState(all, chat: state(), animate: true, paused: true),
        'idle',
      );
      // A clip of the exact motion wins over the fallback.
      expect(
        customAvatarState(
          [...all, 'searching'],
          chat: searching,
          animate: true,
        ),
        'searching',
      );
    });

    test('missing clips, errors and reduced motion show the portrait', () {
      expect(customAvatarState(const [], chat: state(), animate: true), isNull);
      expect(
        customAvatarState(const ['idle'], chat: searching, animate: true),
        isNull,
      );
      expect(
        customAvatarState(const ['idle'], chat: replying, animate: true),
        isNull,
      );
      expect(
        customAvatarState(
          all,
          chat: state().copyWith(connection: ChatConnection.error),
          animate: true,
        ),
        isNull,
      );
      expect(customAvatarState(all, chat: state()), isNull);
      expect(customAvatarState(all, animate: true), isNull);
    });
  });
}
