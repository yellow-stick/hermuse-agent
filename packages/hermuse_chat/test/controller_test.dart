import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:test/test.dart';

final class _Connections implements HermesConnections {
  _Connections(this.connection);
  final HermesConnection connection;

  @override
  Future<HermesConnection> connectionFor(String instanceId) async => connection;
}

final class _Failing implements HermesConnections {
  _Failing(this.error);
  final Object error;

  @override
  Future<HermesConnection> connectionFor(String instanceId) async =>
      throw error;
}

final class _Observer implements ChatObserver {
  final created = <(ThreadRef, String?)>[];
  final settled = <ThreadRef>[];

  @override
  void sessionCreated(
    ThreadRef ref, {
    required String title,
    String? parentId,
  }) => created.add((ref, parentId));

  @override
  void sessionTitled(ThreadRef ref, String title) {}

  @override
  void messagesSettled(ThreadRef ref, List<Message> messages) =>
      settled.add(ref);

  final events = <String>[];

  @override
  void turnEnded(ThreadRef ref) => events.add('turn ${ref.sessionId}');

  @override
  void threadOpened(ThreadRef ref) => events.add('open ${ref.sessionId}');

  @override
  void sessionArchived(ThreadRef ref, {required bool archived}) =>
      events.add('${archived ? 'archive' : 'restore'} ${ref.sessionId}');

  @override
  void sessionDeleted(ThreadRef ref) => events.add('delete ${ref.sessionId}');
}

void main() {
  late FakeHermesTransport fake;
  late _Observer observer;
  var resumes = 0;

  setUp(() {
    fake = FakeHermesTransport();
    observer = _Observer();
    resumes = 0;
    fake
      ..on('session.resume', (params) {
        resumes++;
        return {
          'session_id': 'live-$resumes',
          'message_count': 3,
          'started_at':
              DateTime(2026, 9, 27, 9, 5).millisecondsSinceEpoch / 1000,
          'info': {'title': 'Trip planning'},
          'messages': [
            {'role': 'user', 'text': 'find flights', 'row_id': 1},
            {
              'role': 'assistant',
              'text': 'Searching.',
              'reasoning': 'need dates',
              'row_id': 2,
            },
            {
              'role': 'tool',
              'name': 'web_search',
              'tool_call_id': 't0',
              'context': 'flights LIS OSL',
              'row_id': 3,
            },
            {'role': 'assistant', 'text': 'Here are three.', 'row_id': 4},
          ],
        };
      })
      ..on('prompt.submit', (_) => const <String, Object?>{})
      ..on('session.interrupt', (_) => {'status': 'interrupted'})
      ..on(
        'session.create',
        (_) => {
          'session_id': 'live-new',
          'stored_session_id': 'stored-new',
          'message_count': 0,
          'messages': const [],
          'info': const <String, Object?>{},
        },
      );
  });

  Future<ChatController> open({String sessionId = 'stored-1'}) async {
    final chat = ChatController(
      connections: _Connections(HermesConnection('vps', fake)),
      ref: ThreadRef(instanceId: 'vps', sessionId: sessionId),
      observer: observer,
      clock: () => '1:00 PM',
    );
    await chat.ready;
    return chat;
  }

  test(
    'resume maps the transcript: tool rows join the assistant turn',
    () async {
      final chat = await open();
      final thread = chat.state.activeThread;
      expect(thread.title, 'Trip planning');
      expect(thread.startedAt, '9:05 AM', reason: 'session start, not now');
      expect(thread.messages.map((m) => m.author), [Author.user, Author.agent]);
      final agent = thread.messages.last.blocks;
      expect(agent[0], isA<ReasoningBlock>());
      expect((agent[1] as TextBlock).text, 'Searching.');
      final tool = agent[2] as ToolCallBlock;
      expect((tool.name, tool.running), ('web_search', false));
      // The final answer joins the same bubble, under the last row id.
      expect((agent[3] as TextBlock).text, 'Here are three.');
      expect(thread.messages.last.id, 'row-4');
      expect(fake.calls.first.params['session_id'], 'stored-1');
    },
  );

  test('a streamed turn: deltas, tool call, final text, activity', () async {
    final chat = await open();
    await chat.send('  book the cheapest  ');
    expect(chat.state.busy, isTrue);
    expect(fake.calls.last.method, 'prompt.submit');
    expect(fake.calls.last.params, {
      'session_id': 'live-1',
      'text': 'book the cheapest',
    });

    fake
      ..emitEvent('message.start', sessionId: 'live-1')
      ..emitEvent(
        'message.delta',
        sessionId: 'live-1',
        payload: {'text': 'Boo'},
      )
      ..emitEvent(
        'tool.start',
        sessionId: 'live-1',
        payload: {'tool_id': 't1', 'name': 'book', 'preview': 'Meridian'},
      )
      ..emitEvent(
        'tool.complete',
        sessionId: 'live-1',
        payload: {'tool_id': 't1', 'name': 'book', 'summary': 'PNR X1'},
      )
      ..emitEvent(
        'message.delta',
        sessionId: 'live-1',
        payload: {'text': 'ked'},
      )
      // Another session on the same socket must not leak into this chat.
      ..emitEvent('message.delta', sessionId: 'other', payload: {'text': '!!'});

    var blocks = chat.state.activeThread.messages.last.blocks;
    expect((blocks[0] as TextBlock).text, 'Boo');
    expect((blocks[1] as ToolCallBlock).summary, 'PNR X1');
    expect((blocks[2] as TextBlock).text, 'ked');

    fake.emitEvent(
      'message.complete',
      sessionId: 'live-1',
      payload: {
        'text': 'Booked: PNR X1',
        'status': 'complete',
        'persisted_turn': {
          'row_ids': [5, 6],
          'complete': true,
          'user_row_id': 5,
          'final_assistant_row_id': 6,
        },
      },
    );
    // Ids now match what a later session.resume returns.
    expect(chat.state.activeThread.messages.reversed.take(2).map((m) => m.id), [
      'row-6',
      'row-5',
    ]);
    blocks = chat.state.activeThread.messages.last.blocks;
    expect(blocks.whereType<TextBlock>().single.text, 'Booked: PNR X1');
    expect(chat.state.busy, isFalse);
    expect(chat.state.activity.single.title, 'book');
    expect(observer.settled, isNotEmpty);
  });

  test(
    'browser tools render one BrowserBlock at the top of the turn',
    () async {
      final chat = await open();
      await chat.send('titles please');
      BrowserBlock card() =>
          chat.state.activeThread.messages.last.blocks.first as BrowserBlock;

      fake
        ..emitEvent('message.start', sessionId: 'live-1')
        ..emitEvent(
          'tool.start',
          sessionId: 'live-1',
          payload: {
            'tool_id': 'b1',
            'name': 'browser_navigate',
            'args': {'url': 'https://en.wikipedia.org/wiki/Nantes'},
          },
        );
      expect(
        (card().lastToolId, card().running, card().step, card().host),
        ('b1', true, 'Opening en.wikipedia.org', 'en.wikipedia.org'),
      );

      fake.emitEvent(
        'tool.complete',
        sessionId: 'live-1',
        payload: {'tool_id': 'b1', 'name': 'browser_navigate'},
      );
      expect(card().running, isTrue, reason: 'the turn still owns the browser');

      fake
        ..emitEvent(
          'tool.start',
          sessionId: 'live-1',
          payload: {'tool_id': 'b2', 'name': 'browser_click'},
        )
        ..emitEvent(
          'message.delta',
          sessionId: 'live-1',
          payload: {'text': 'Nantes'},
        );
      expect(
        (card().lastToolId, card().step, card().host),
        ('b2', 'Clicking', 'en.wikipedia.org'),
      );

      fake.emitEvent(
        'message.complete',
        sessionId: 'live-1',
        payload: {'text': 'Nantes', 'status': 'complete'},
      );
      final turn = chat.state.activeThread.messages.last;
      expect(turn.blocks, hasLength(2));
      expect(
        (card().lastToolId, card().running, card().step),
        ('b2', false, ''),
      );
      expect((turn.blocks.last as TextBlock).text, 'Nantes');
      expect(turn.blocks.whereType<ToolCallBlock>(), isEmpty);
      expect(turn.plainText, 'Nantes');
      expect(chat.state.activity.single.title, 'browser_navigate');
    },
  );

  test('an error ends the turn browser card', () async {
    final chat = await open();
    await chat.send('open it');
    fake
      ..emitEvent('message.start', sessionId: 'live-1')
      ..emitEvent(
        'tool.start',
        sessionId: 'live-1',
        payload: {'tool_id': 'b1', 'name': 'browser_snapshot'},
      )
      ..emitEvent(
        'error',
        sessionId: 'live-1',
        payload: {'message': 'model overloaded'},
      );
    final card = chat.state.activeThread.messages
        .expand((m) => m.blocks)
        .whereType<BrowserBlock>()
        .single;
    expect((card.running, card.step), (false, ''));
    expect(chat.state.busy, isFalse);
  });

  test(
    'resumed browser tool rows fold into one finished BrowserBlock',
    () async {
      fake.on(
        'session.resume',
        (_) => {
          'session_id': 'live-1',
          'message_count': 5,
          'info': {'title': 'Nantes'},
          'messages': [
            {'role': 'user', 'text': 'look at Nantes', 'row_id': 1},
            {'role': 'assistant', 'text': 'Looking.', 'row_id': 2},
            {
              'role': 'tool',
              'name': 'browser_snapshot',
              'tool_call_id': 's1',
              'row_id': 3,
            },
            {
              'role': 'tool',
              'name': 'browser_snapshot',
              'tool_call_id': 's2',
              'row_id': 4,
            },
            {'role': 'assistant', 'text': 'A city.', 'row_id': 5},
          ],
        },
      );
      final chat = await open();
      final blocks = chat.state.activeThread.messages.last.blocks;
      final card = blocks.first as BrowserBlock;
      expect((card.lastToolId, card.running), ('s2', false));
      expect(blocks.whereType<BrowserBlock>(), hasLength(1));
      expect(blocks.whereType<ToolCallBlock>(), isEmpty);
      expect(
        [for (final b in blocks.skip(1)) (b as TextBlock).text],
        ['Looking.', 'A city.'],
      );
    },
  );

  test(
    'a turn keeps one reasoning block first; thinking status is ignored',
    () async {
      final chat = await open();
      await chat.send('think');
      fake
        ..emitEvent('message.start', sessionId: 'live-1')
        ..emitEvent(
          'thinking.delta',
          sessionId: 'live-1',
          payload: {'text': '🤔 thinking...'},
        )
        ..emitEvent(
          'reasoning.delta',
          sessionId: 'live-1',
          payload: {'text': 'Plan '},
        )
        ..emitEvent(
          'message.delta',
          sessionId: 'live-1',
          payload: {'text': 'ok'},
        )
        ..emitEvent(
          'reasoning.delta',
          sessionId: 'live-1',
          payload: {'text': 'more'},
        )
        ..emitEvent(
          'reasoning.available',
          sessionId: 'live-1',
          payload: {'text': 'ignored'},
        );
      final blocks = chat.state.activeThread.messages.last.blocks;
      expect(blocks, hasLength(2));
      expect((blocks.first as ReasoningBlock).text, 'Plan more');
      expect((blocks.last as TextBlock).text, 'ok');
    },
  );

  test(
    'an API retry shows its wait on the pending turn until content streams',
    () async {
      final chat = await open();
      await chat.send('hello');
      List<Block> turn() => chat.state.activeThread.messages.last.blocks;
      void status(String text) => fake.emitEvent(
        'thinking.delta',
        sessionId: 'live-1',
        payload: {'text': text},
      );

      fake.emitEvent('message.start', sessionId: 'live-1');
      status('(◕‿◕) pondering...');
      status('');
      expect(turn(), isEmpty, reason: 'spinner chatter is not a status');

      // agent/turn_recovery.py::compute_error_backoff after a 429.
      status('⏳ rate limited — resets in ~13m, retrying in 600s (attempt 1/3)');
      expect(
        (turn().single as WaitBlock).text,
        'Retrying in 10 min (attempt 1/3) — rate limited, resets in ~13m',
      );

      // The next attempt starts: its spinner frame retires the wait.
      status('(⌐■_■) computing...');
      expect(turn(), isEmpty);

      status('⏳ waiting on provider — retrying in 45s (attempt 2/3)');
      expect(
        (turn().single as WaitBlock).text,
        'Retrying in 45s (attempt 2/3) — waiting on provider',
      );
      status('⚠ no output from provider for 900s — reconnecting...');
      expect(
        (turn().single as WaitBlock).text,
        'No output from provider for 900s — reconnecting...',
      );

      fake.emitEvent(
        'message.delta',
        sessionId: 'live-1',
        payload: {'text': 'Hi'},
      );
      expect(turn().single, isA<TextBlock>());
      expect(chat.state.activeThread.messages.last.plainText, 'Hi');
    },
  );

  test('a turn ending during a retry wait drops the wait line', () async {
    final chat = await open();
    const retry = {
      'text': '⏳ waiting on provider — retrying in 600s (attempt 1/3)',
    };
    Iterable<WaitBlock> waits() => chat.state.activeThread.messages
        .expand((m) => m.blocks)
        .whereType<WaitBlock>();

    await chat.send('hello');
    fake
      ..emitEvent('message.start', sessionId: 'live-1')
      ..emitEvent('thinking.delta', sessionId: 'live-1', payload: retry);
    expect(waits(), hasLength(1));
    await chat.interrupt();
    fake.emitEvent(
      'message.complete',
      sessionId: 'live-1',
      payload: {
        'text':
            'Operation interrupted: retrying API call after error '
            '(retry 1/3).',
        'status': 'interrupted',
      },
    );
    expect(waits(), isEmpty);
    expect(
      (chat.state.activeThread.messages.last.blocks.last as NoticeBlock).text,
      'Stopped',
    );

    await chat.send('again');
    fake
      ..emitEvent('message.start', sessionId: 'live-1')
      ..emitEvent('thinking.delta', sessionId: 'live-1', payload: retry)
      ..emitEvent(
        'error',
        sessionId: 'live-1',
        payload: {'message': 'provider down'},
      );
    expect(waits(), isEmpty);
    expect(chat.state.busy, isFalse);
  });

  group('slash commands', () {
    setUp(() {
      fake.on(
        'commands.catalog',
        (_) => {
          'pairs': [
            ['/model', 'Switch model'],
            ['/goal', 'Set a goal'],
            ['/pr-triage', 'Triage a pull request'],
          ],
          'canon': {'/model': '/model', '/m': '/model', '/goal': '/goal'},
          'skills': {
            '/pr-triage': {'usage': 0, 'origin': 'local'},
          },
          'skill_count': 1,
          'warning': '',
        },
      );
    });

    CommandBlock lastRow(ChatController chat) =>
        chat.state.activeThread.messages.last.blocks.single as CommandBlock;

    test('a catalog command runs on the server as a notice row', () async {
      fake.on(
        'slash.exec',
        (_) => {'output': 'Switched to claude-sonnet-4-6 (anthropic)'},
      );
      final chat = await open();
      final before = chat.state.activeThread.messages.length;
      final seen = <CommandBlock>[];
      chat.addListener(() {
        if (chat.state.activeThread.messages.last.blocks.lastOrNull
            case final CommandBlock row) {
          seen.add(row);
        }
      });

      await chat.send('/model claude-sonnet-4-6');
      expect(fake.calls.skip(1).map((c) => [c.method, c.params]), [
        [
          'commands.catalog',
          {'session_id': 'live-1'},
        ],
        [
          'slash.exec',
          {'session_id': 'live-1', 'command': 'model claude-sonnet-4-6'},
        ],
      ]);
      expect(seen.first.running, isTrue, reason: 'shown before the answer');
      final messages = chat.state.activeThread.messages;
      expect(messages, hasLength(before + 1), reason: 'no user bubble');
      expect(messages.last.author, Author.agent);
      final row = lastRow(chat);
      expect(
        (row.command, row.output, row.running, row.isError),
        (
          '/model claude-sonnet-4-6',
          'Switched to claude-sonnet-4-6 (anthropic)',
          false,
          false,
        ),
      );
      expect(chat.state.busy, isFalse);

      // The switch announces the session's new model: the picker follows.
      fake.emitEvent(
        'session.info',
        sessionId: 'live-1',
        payload: {'model': 'claude-sonnet-4-6', 'provider': 'anthropic'},
      );
      expect(
        chat.state.model,
        const ChatModel(provider: 'anthropic', model: 'claude-sonnet-4-6'),
      );
    });

    test('a new chat gets its session before its first command', () async {
      fake.on('slash.exec', (_) => {'output': 'Current model: glm-5'});
      final chat = await open(sessionId: '');
      await chat.send('/model');
      expect(fake.calls.map((c) => (c.method, c.params['session_id'])), [
        ('commands.catalog', null),
        ('session.create', null),
        ('slash.exec', 'live-new'),
      ]);
      expect(chat.state.activeThreadId, 'stored-new');
      expect(lastRow(chat).output, 'Current model: glm-5');
    });

    test('text the catalog does not know goes to the agent', () async {
      final chat = await open();
      await chat.send('/shrug hello');
      expect(fake.calls.last.method, 'prompt.submit');
      expect(fake.calls.last.params['text'], '/shrug hello');
      final last = chat.state.activeThread.messages.last;
      expect((last.author, last.plainText), (Author.user, '/shrug hello'));

      // A path is prose, not a command: no catalog lookup.
      final calls = fake.calls.length;
      await chat.send('/etc/hosts is empty');
      expect(fake.calls.skip(calls).map((c) => c.method), ['prompt.submit']);

      // Without a catalog nothing is known to be a command.
      fake.on(
        'commands.catalog',
        (_) => throw const FakeRpcError(5020, 'catalog failed'),
      );
      await chat.send('/model gpt-5');
      expect(fake.calls.last.params['text'], '/model gpt-5');
    });

    test(
      'a skill refused by slash.exec runs through command.dispatch',
      () async {
        fake
          ..on(
            'slash.exec',
            (_) => throw const FakeRpcError(
              4018,
              'skill command: use command.dispatch for /pr-triage',
            ),
          )
          ..on(
            'command.dispatch',
            (_) => {
              'type': 'skill',
              'name': 'pr-triage',
              'message': '[skill instructions] triage PR 42',
              'display': '/pr-triage 42',
            },
          );
        final chat = await open();
        await chat.send('/pr-triage 42');
        expect(fake.calls.skip(1).map((c) => c.method), [
          'commands.catalog',
          'slash.exec',
          'command.dispatch',
          'prompt.submit',
        ]);
        expect(fake.calls.elementAt(3).params, {
          'name': 'pr-triage',
          'arg': '42',
          'session_id': 'live-1',
        });
        expect(
          fake.calls.last.params['text'],
          '[skill instructions] triage PR 42',
        );
        // The bubble shows the invocation, never the skill's body.
        final last = chat.state.activeThread.messages.last;
        expect((last.author, last.plainText), (Author.user, '/pr-triage 42'));
        expect(
          chat.state.activeThread.messages
              .expand((m) => m.blocks)
              .whereType<CommandBlock>(),
          isEmpty,
        );
        expect(chat.state.busy, isTrue);
      },
    );

    test('a command that starts a turn keeps its notice', () async {
      fake.on(
        'slash.exec',
        (_) => {
          'type': 'send',
          'notice': '⊙ Goal set (20-turn budget): ship it',
          'message': 'ship it',
        },
      );
      final chat = await open();
      await chat.send('/goal ship it');
      final messages = chat.state.activeThread.messages;
      final row = messages[messages.length - 2].blocks.single as CommandBlock;
      expect(row.output, '⊙ Goal set (20-turn budget): ship it');
      expect(
        (messages.last.author, messages.last.plainText),
        (Author.user, 'ship it'),
      );
      expect(fake.calls.last.params, {
        'session_id': 'live-1',
        'text': 'ship it',
      });
    });

    test('an alias runs its target with the same argument', () async {
      final commands = <Object?>[];
      fake.on('slash.exec', (params) {
        commands.add(params['command']);
        return params['command'] == 'm gpt-5'
            ? {'type': 'alias', 'target': 'model'}
            : {'output': 'Switched to gpt-5'};
      });
      final chat = await open();
      await chat.send('/m gpt-5');
      expect(commands, ['m gpt-5', 'model gpt-5']);
      expect(lastRow(chat).output, 'Switched to gpt-5');
    });

    test('a failed command shows its error without re-dispatching', () async {
      fake.on(
        'slash.exec',
        (_) => throw const FakeRpcError(5030, 'slash worker timed out'),
      );
      final chat = await open();
      await chat.send('/model gpt-5');
      expect(
        fake.calls.map((c) => c.method),
        isNot(contains('command.dispatch')),
      );
      final row = lastRow(chat);
      expect(
        (row.output, row.isError, row.running),
        ('slash worker timed out', true, false),
      );
    });
  });

  test('reply quotes the target; blank input is ignored', () async {
    final chat = await open();
    var notified = 0;
    chat.addListener(() => notified++);
    await chat.send('   ');
    expect(notified, 0);

    chat.startReply('row-1');
    await chat.send('only direct ones');
    expect(chat.state.replyToId, isNull);
    expect(chat.state.activeThread.messages.last.replyToId, 'row-1');
    expect(
      fake.calls.last.params['text'],
      '> find flights\n\nonly direct ones',
    );
  });

  test(
    'approval request becomes a choice answered on the request id',
    () async {
      final chat = await open();
      fake.emitRequest('srq-9', 'approval', {
        'session_id': 'live-1',
        'request_id': 'r1',
        'command': 'rm -rf dist',
        'allow_permanent': false,
      });
      await pumpEventQueue();
      final card = chat.state.activeThread.messages.last;
      final choice = card.blocks.single as ChoiceBlock;
      expect(choice.options, ['Allow once', 'Allow for this session', 'Deny']);
      expect(choice.prompt, contains('rm -rf dist'));

      chat.choose(card.id, 'Always allow'); // not offered: ignored
      await pumpEventQueue();
      expect(fake.replies, isNot(contains('srq-9')));

      chat.choose(card.id, 'Allow once');
      await pumpEventQueue();
      expect(fake.replies['srq-9']?['result'], {'choice': 'once'});
      expect(
        (chat.state.activeThread.messages.last.blocks.single as ChoiceBlock)
            .selected,
        'Allow once',
      );
    },
  );

  test('batch clarify answers once every question is answered', () async {
    final chat = await open();
    fake.emitRequest('srq-c', 'clarify', {
      'session_id': 'live-1',
      'questions': [
        {
          'qid': 'a',
          'question': 'Window or aisle?',
          'choices': ['Window', 'Aisle'],
        },
        {'qid': 'b', 'question': 'Meal?'},
      ],
    });
    await pumpEventQueue();
    final id = chat.state.activeThread.messages.last.id;
    chat.choose(id, 'Aisle');
    await pumpEventQueue();
    expect(fake.replies, isNot(contains('srq-c')));
    chat.choose(id, 'Vegetarian', blockIndex: 1);
    await pumpEventQueue();
    expect(fake.replies['srq-c']?['result'], {
      'answers': {'a': 'Aisle', 'b': 'Vegetarian'},
    });
  });

  test('stop interrupts the live session of the active thread', () async {
    final chat = await open();
    await chat.send('long task');
    await chat.interrupt();
    expect(fake.calls.last.method, 'session.interrupt');
    expect(fake.calls.last.params, {'session_id': 'live-1'});
  });

  test(
    'after a reconnect the open thread is resumed on its new live id',
    () async {
      final chat = await open();
      fake.setState(
        ConnectionState.reconnecting,
        const HermesConnectionLost('x'),
      );
      expect(chat.state.connection, ChatConnection.reconnecting);
      fake.setState(ConnectionState.ready);
      await pumpEventQueue();
      expect(resumes, 2);
      expect(chat.state.connection, ChatConnection.ready);
      fake.emitEvent(
        'message.delta',
        sessionId: 'live-2',
        payload: {'text': 'x'},
      );
      expect(chat.state.activeThread.messages.last.plainText, 'x');
    },
  );

  test('side chat creates its session with the parent on first send', () async {
    final chat = await open();
    chat.newSideChat();
    expect(chat.state.activeThread.messages, isEmpty);
    expect(chat.state.activeThread.startedAt, '1:00 PM');
    await chat.send('side question');
    final create = fake.calls.firstWhere((c) => c.method == 'session.create');
    expect(create.params['parent_session_id'], 'stored-1');
    expect(chat.state.activeThreadId, 'stored-new');
    expect(observer.created.single.$2, 'stored-1');
    expect(fake.calls.last.params['session_id'], 'live-new');

    chat.openThread('stored-1');
    expect(chat.state.activeThread.messages, hasLength(2));
  });

  test('a side chat is untitled until the agent titles it', () async {
    final chat = await open();
    chat.newSideChat();
    expect(chat.state.activeThread.title, isEmpty);
    await chat.send('side question');
    final create = fake.calls.firstWhere((c) => c.method == 'session.create');
    expect(create.params.containsKey('title'), isFalse);
    fake.emitEvent(
      'session.title',
      sessionId: 'live-new',
      payload: {'session_id': 'stored-new', 'title': 'Cat names'},
    );
    await pumpEventQueue();
    expect(chat.state.activeThread.title, 'Cat names');
  });

  test(
    'a side chat of a new main chat creates the main session first',
    () async {
      var n = 0;
      fake.on('session.create', (_) {
        n++;
        return {
          'session_id': 'live-c$n',
          'stored_session_id': 'stored-c$n',
          'message_count': 0,
          'messages': const [],
          'info': const <String, Object?>{},
        };
      });
      final chat = await open(sessionId: '');
      chat.newSideChat();
      await chat.send('side first');
      final creates = [
        for (final c in fake.calls)
          if (c.method == 'session.create') c.params['parent_session_id'],
      ];
      expect(creates, [null, 'stored-c1']);
      expect(chat.state.mainThread.id, 'stored-c1');
      expect(observer.created.map((c) => (c.$1.sessionId, c.$2)), [
        ('stored-c1', null),
        ('stored-c2', 'stored-c1'),
      ]);
      expect(chat.state.activeThreadId, 'stored-c2');
    },
  );

  test('opens on the side chat that was on screen last time', () async {
    final chat = ChatController(
      connections: _Connections(HermesConnection('vps', fake)),
      ref: const ThreadRef(instanceId: 'vps', sessionId: 'stored-1'),
      observer: observer,
      sideThreads: [
        const Thread(id: 'side-1', title: 'Cats', startedAt: '', messages: []),
      ],
      initialThreadId: 'side-1',
    );
    await chat.ready;
    expect(chat.state.activeThreadId, 'side-1');
    expect(fake.calls.single.params['session_id'], 'side-1');
    chat.openThread('stored-1');
    expect(observer.events, ['open stored-1']);
  });

  group('side chat actions', () {
    var mark = 0;
    List<({String method, Map<String, Object?> params})> calls() =>
        fake.calls.skip(mark).toList();

    Future<ChatController> withSide() async {
      final chat = ChatController(
        connections: _Connections(HermesConnection('vps', fake)),
        ref: const ThreadRef(instanceId: 'vps', sessionId: 'stored-1'),
        observer: observer,
        sideThreads: [
          const Thread(
            id: 'side-1',
            title: 'Cats',
            startedAt: '',
            messages: [],
          ),
        ],
      );
      await chat.ready;
      chat.openThread('side-1');
      await pumpEventQueue();
      mark = fake.calls.length;
      observer.events.clear();
      return chat;
    }

    test('rename sets the title on the live session', () async {
      fake.on('session.title', (_) => {'title': 'Kittens'});
      final chat = await withSide();
      await chat.renameThread('side-1', '  Kittens ');
      final call = calls().single;
      expect(call.method, 'session.title');
      expect(call.params, {'session_id': 'live-2', 'title': 'Kittens'});
      expect(chat.state.activeThread.title, 'Kittens');
    });

    test('archiving hides it on the server and opens the main chat', () async {
      fake.on(
        'session.set_hidden',
        (p) => {'hidden': p['hidden'], 'session_key': 'k'},
      );
      final chat = await withSide();
      await chat.archiveThread('side-1');
      expect(calls().single.params, {'session_id': 'side-1', 'hidden': true});
      expect(chat.state.sideThreads, isEmpty);
      expect(chat.state.activeThreadId, 'stored-1');
      expect(observer.events, ['archive side-1', 'open stored-1']);

      await chat.restoreThread('side-1', title: 'Cats');
      expect(calls().last.params['hidden'], isFalse);
      expect(chat.state.sideThreads.single.title, 'Cats');
      expect(observer.events.last, 'restore side-1');
    });

    test('delete closes the live session before deleting it', () async {
      fake
        ..on('session.close', (_) => {'closed': true})
        ..on('session.delete', (_) => {'deleted': 'side-1'});
      final chat = await withSide();
      await chat.deleteThread('side-1');
      expect(calls().map((c) => (c.method, c.params['session_id'])), [
        ('session.close', 'live-2'),
        ('session.delete', 'side-1'),
      ]);
      expect(chat.state.sideThreads, isEmpty);
      expect(observer.events.first, 'delete side-1');
    });

    test('a failed server call keeps the side chat', () async {
      fake.on('session.set_hidden', (_) => throw FakeRpcError(-32000, 'nope'));
      final chat = await withSide();
      await expectLater(chat.archiveThread('side-1'), throwsA(anything));
      expect(chat.state.sideThreads.single.id, 'side-1');
      expect(observer.events, isEmpty);
    });
  });

  test('isReady flips once the transcript is loaded', () async {
    final chat = ChatController(
      connections: _Connections(HermesConnection('vps', fake)),
      ref: const ThreadRef(instanceId: 'vps', sessionId: 'stored-1'),
    );
    expect(chat.isReady, isFalse);
    await chat.ready;
    expect(chat.isReady, isTrue);
    expect(chat.state.activeThread.messages, isNotEmpty);
  });

  test('a new conversation creates its session lazily', () async {
    final chat = await open(sessionId: '');
    expect(fake.calls, isEmpty);
    await chat.send('hello');
    expect(fake.calls.map((c) => c.method), [
      'session.create',
      'prompt.submit',
    ]);
    expect(observer.created.single.$1.sessionId, 'stored-new');
    expect(observer.created.single.$2, isNull);
  });

  test(
    'model switch is session-scoped; a draft applies it after create',
    () async {
      fake.on('config.set', (_) => {'key': 'model', 'value': 'ok'});
      final chat = await open(sessionId: '');
      const pick = ChatModel(provider: 'zai', model: 'glm-5.3-flash');
      await chat.setModel(pick);
      expect(fake.calls, isEmpty);
      expect(chat.state.model, pick);
      await chat.send('hi');
      expect(fake.calls.map((c) => c.method), [
        'session.create',
        'config.set',
        'prompt.submit',
      ]);
      expect(fake.calls.elementAt(1).params, {
        'key': 'model',
        'value': 'glm-5.3-flash --provider zai',
        'session_id': 'live-new',
        'scope': 'session',
        'confirm_expensive_model': false,
      });
    },
  );

  test(
    'rejected credentials ask for sign-in; other failures only retry',
    () async {
      for (final (error, signIn) in [
        (const HermesAuthFailed('no stored credentials'), true),
        (const HermesUnreachable('dns'), false),
      ]) {
        final chat = ChatController(
          connections: _Failing(error),
          ref: const ThreadRef(instanceId: 'vps', sessionId: 's'),
        );
        await chat.ready;
        expect(chat.state.connection, ChatConnection.error);
        expect(chat.state.needsSignIn, signIn);
      }
      final live = await open();
      fake.setState(ConnectionState.error, const HermesAuthFailed('401'));
      expect(live.state.needsSignIn, isTrue);
    },
  );

  test('group positions follow consecutive authors', () {
    const a = Message(id: '1', author: Author.agent, blocks: []);
    const u = Message(id: '2', author: Author.user, blocks: []);
    final m = [a, a, a, u];
    expect(groupPositionAt(m, 0), GroupPosition.first);
    expect(groupPositionAt(m, 1), GroupPosition.middle);
    expect(groupPositionAt(m, 2), GroupPosition.last);
    expect(groupPositionAt(m, 3), GroupPosition.single);
  });

  test('prices format with the currency symbol', () {
    expect(const Money(456.06, 'EUR').toString(), '€456.06');
    expect(const Money(519.5, 'USD').toString(), r'$519.50');
  });

  test('time-ago buckets', () {
    final now = DateTime(2026, 9, 27, 17);
    String ago(Duration d) => formatTimeAgo(now.subtract(d), now);
    expect(ago(const Duration(seconds: 59)), 'just now');
    expect(ago(const Duration(minutes: 3)), '3m');
    expect(ago(const Duration(minutes: 60)), '1h');
    expect(ago(const Duration(hours: 23)), '23h');
    expect(ago(const Duration(days: 1)), 'Sat');
    expect(ago(const Duration(days: 7)), 'Sep 20');
  });
}
