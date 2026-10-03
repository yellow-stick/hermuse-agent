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
}
