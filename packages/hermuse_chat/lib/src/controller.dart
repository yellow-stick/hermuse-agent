import 'dart:async';

import 'package:hermes_client/hermes_client.dart';

import 'models.dart';
import 'tools.dart';

/// Identifies a profile's conversation on a registered Hermes instance.
/// The session id is empty until the first message creates the session.
final class ThreadRef {
  const ThreadRef({
    required this.instanceId,
    required this.sessionId,
    this.profile = 'default',
  });

  final String instanceId;
  final String sessionId;
  final String profile;

  bool get isNew => sessionId.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ThreadRef &&
      other.instanceId == instanceId &&
      other.profile == profile &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(instanceId, profile, sessionId);

  @override
  String toString() => 'ThreadRef($instanceId, $profile, $sessionId)';
}

/// Persistence hooks of a [ChatController] (session index, transcript cache).
abstract interface class ChatObserver {
  /// A session was created on the server; [parentId] is set for side chats.
  void sessionCreated(ThreadRef ref, {required String title, String? parentId});

  void sessionTitled(ThreadRef ref, String title);

  /// A turn finished or a transcript was loaded.
  void messagesSettled(ThreadRef ref, List<Message> messages);

  /// A turn of [ref] ended (orders side chats by activity).
  void turnEnded(ThreadRef ref);

  /// [ref] became the thread on screen (restored on the next launch).
  void threadOpened(ThreadRef ref);

  /// A side chat was archived (hidden on the server) or restored.
  void sessionArchived(ThreadRef ref, {required bool archived});

  /// A side chat was deleted on the server.
  void sessionDeleted(ThreadRef ref);

  /// The agent finished a tool in [ref] (the profile panel's Activity).
  void toolCompleted(ThreadRef ref, ActivityItem item);
}

/// Immutable snapshot of the chat.
final class ChatState {
  const ChatState({
    required this.agentName,
    required this.threads,
    required this.activeThreadId,
    this.pendingApprovalIds = const {},
    this.selectedOffers = const {},
    this.replyToId,
    this.connection = ChatConnection.connecting,
    this.connectionError,
    this.busyThreads = const {},
    this.models = const {},
    this.needsSignIn = false,
    this.computerOpen = false,
  });

  final String agentName;

  /// The main thread first, then side chats in creation order.
  final List<Thread> threads;
  final String activeThreadId;

  /// Approval requests (their message ids) Hermes still waits on.
  final Set<String> pendingApprovalIds;

  /// Picked flight offer per flight-results message id.
  final Map<String, String> selectedOffers;

  /// Message the next sent message replies to.
  final String? replyToId;
  final ChatConnection connection;

  /// Human-readable cause when [connection] is `reconnecting` or `error`.
  final String? connectionError;

  /// Threads with an agent turn in progress.
  final Set<String> busyThreads;

  /// Model in use per thread (`provider/model` label from Hermes).
  final Map<String, ChatModel> models;

  /// The instance rejected or lacks stored credentials: show a sign-in form
  /// (then retry) instead of a plain Retry.
  final bool needsSignIn;

  /// The agent's computer viewer replaces the chat area.
  final bool computerOpen;

  /// Model of the active thread, when known.
  ChatModel? get model => models[activeThreadId];

  Thread get mainThread => threads.first;

  Thread get activeThread => threads.firstWhere((t) => t.id == activeThreadId);

  Iterable<Thread> get sideThreads => threads.skip(1);

  /// The active thread has a turn in progress (show the stop button).
  bool get busy => busyThreads.contains(activeThreadId);

  Message? get replyTo => replyToId == null
      ? null
      : activeThread.messages.where((m) => m.id == replyToId).firstOrNull;

  /// Unanswered approval requests, main chat first.
  List<ApprovalRequest> get approvals => [
    if (pendingApprovalIds.isNotEmpty)
      for (final thread in threads)
        for (final message in thread.messages)
          if (pendingApprovalIds.contains(message.id))
            for (final block in message.blocks.whereType<ChoiceBlock>())
              if (block.selected == null)
                ApprovalRequest(
                  threadId: thread.id,
                  threadTitle: thread.title,
                  messageId: message.id,
                  prompt: block.prompt,
                ),
  ];

  ChatState copyWith({
    String? agentName,
    List<Thread>? threads,
    String? activeThreadId,
    Set<String>? pendingApprovalIds,
    Map<String, String>? selectedOffers,
    String? Function()? replyToId,
    ChatConnection? connection,
    String? Function()? connectionError,
    Set<String>? busyThreads,
    Map<String, ChatModel>? models,
    bool? needsSignIn,
    bool? computerOpen,
  }) => ChatState(
    agentName: agentName ?? this.agentName,
    threads: threads ?? this.threads,
    activeThreadId: activeThreadId ?? this.activeThreadId,
    pendingApprovalIds: pendingApprovalIds ?? this.pendingApprovalIds,
    selectedOffers: selectedOffers ?? this.selectedOffers,
    replyToId: replyToId != null ? replyToId() : this.replyToId,
    connection: connection ?? this.connection,
    connectionError: connectionError != null
        ? connectionError()
        : this.connectionError,
    busyThreads: busyThreads ?? this.busyThreads,
    models: models ?? this.models,
    needsSignIn: needsSignIn ?? this.needsSignIn,
    computerOpen: computerOpen ?? this.computerOpen,
  );
}

/// A model as Hermes names it: provider id + model id.
final class ChatModel {
  const ChatModel({required this.provider, required this.model});
  final String provider;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is ChatModel && other.provider == provider && other.model == model;

  @override
  int get hashCode => Object.hash(provider, model);
}

/// Drives one conversation (main thread + side chats) of a Hermes instance
/// and notifies listeners on every change.
///
/// Framework-free on purpose: Flutter wraps it in a `Listenable`, Jaspr calls
/// `setState` from a listener.
final class ChatController {
  ChatController({
    required this._connections,
    required ThreadRef ref,
    this._observer,
    String agentName = 'Hermes',
    List<Thread> sideThreads = const [],
    String? initialThreadId,
    String Function()? clock,
    DateTime Function()? now,
  }) : _instanceId = ref.instanceId,
       _profile = ref.profile,
       _clock = clock ?? _wallClock,
       _now = now ?? DateTime.now {
    final mainId = ref.isNew ? _draftId() : ref.sessionId;
    _state = ChatState(
      agentName: agentName,
      threads: [
        Thread(id: mainId, title: 'Chat', startedAt: _clock(), messages: []),
        ...sideThreads,
      ],
      activeThreadId: sideThreads.any((t) => t.id == initialThreadId)
          ? initialThreadId!
          : mainId,
    );
    for (final t in sideThreads) {
      _parents[t.id] = mainId;
    }
    ready = _open().whenComplete(() => _isReady = true);
  }

  static const _approvalLabels = {
    ApprovalChoice.once: 'Allow once',
    ApprovalChoice.session: 'Allow for this session',
    ApprovalChoice.always: 'Always allow',
    ApprovalChoice.deny: 'Deny',
  };

  final HermesConnections _connections;
  final String _instanceId;
  final String _profile;
  final ChatObserver? _observer;
  final String Function() _clock;
  final DateTime Function() _now;
  late ChatState _state;
  final _listeners = <void Function()>[];
  var _seq = 0;
  bool _disposed = false;

  HermesConnection? _connection;
  StreamSubscription<HermesEvent>? _eventsSub;
  StreamSubscription<ConnectionState>? _stateSub;

  /// Slash commands Hermes refused because the thread's session was still
  /// running a turn, by thread: they run again once it settles ([_settled]).
  final Map<String, List<({String rowId, String command})>> _held = {};

  /// Idle reports (`session.info` with `running: false`) seen per thread.
  final Map<String, int> _settles = {};

  /// Stored thread id → live session id, and back.
  final Map<String, String> _live = {};
  final Map<String, String> _threadOfLive = {};

  /// Side thread id → main (parent) thread id.
  final Map<String, String> _parents = {};

  /// Threads whose transcript was fetched.
  final Set<String> _loaded = {};

  /// Thread id → id of the agent message of the running turn.
  final Map<String, String> _turn = {};

  /// Choice message id → unanswered server request.
  final Map<String, _PendingRequest> _pending = {};

  /// Model picked for a draft thread, applied right after its session exists.
  final Map<String, ChatModel> _pendingModels = {};

  /// One tear-off so `HermesConnection.unregister` can match it.
  late final ServerRequestHandler _handler = _onRequest;

  /// Completes once the first connection attempt (and resume) settled.
  late final Future<void> ready;
  bool _isReady = false;

  /// [ready] has completed: the transcript (or the connection error) is in
  /// [state]. Shells keep showing the previous chat until then.
  bool get isReady => _isReady;

  /// Instance this chat talks to.
  String get instanceId => _instanceId;

  /// Hermes profile whose sessions and approvals this controller owns.
  String get profile => _profile;

  /// The current stored main session (empty while it remains a draft).
  ThreadRef get ref =>
      _refOf(_isDraft(_state.mainThread.id) ? '' : _state.mainThread.id);

  /// Updates display metadata without rebuilding an in-flight conversation.
  void setAgentName(String name) {
    if (_state.agentName != name) _emit(_state.copyWith(agentName: name));
  }

  ChatState get state => _state;

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  ThreadRef _refOf(String threadId) => ThreadRef(
    instanceId: _instanceId,
    profile: _profile,
    sessionId: threadId,
  );

  bool _isDraft(String threadId) => threadId.startsWith('draft-');
  String _draftId() => 'draft-${_seq++}';

  void _emit(ChatState next) {
    if (_disposed) return;
    _state = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  // ------------------------------------------------------------ connection

  Future<void> _open() async {
    _emit(
      _state.copyWith(
        connection: ChatConnection.connecting,
        connectionError: () => null,
        needsSignIn: false,
      ),
    );
    final HermesConnection connection;
    try {
      connection = await _connections.connectionFor(
        _instanceId,
        profile: _profile,
      );
    } on Object catch (e) {
      _emit(
        _state.copyWith(
          connection: ChatConnection.error,
          connectionError: () => _describe(e),
          needsSignIn: e is HermesAuthFailed,
        ),
      );
      return;
    }
    if (_disposed) return;
    _connection = connection;
    final transport = connection.transport;
    _eventsSub = transport.events.listen(_onEvent);
    _stateSub = transport.state.listen(_onConnectionState);
    _onConnectionState(transport.currentState);
    final active = _state.activeThreadId;
    if (!_isDraft(active)) await _resume(active);
  }

  /// Retries after a terminal connection error.
  Future<void> retry() async {
    if (_state.connection != ChatConnection.error) return;
    await _eventsSub?.cancel();
    await _stateSub?.cancel();
    for (final live in _live.values) {
      _connection?.unregister(live, _handler);
    }
    _connection = null;
    _live.clear();
    _threadOfLive.clear();
    _loaded.clear();
    await _open();
  }

  void _onConnectionState(ConnectionState next) {
    final transport = _connection?.transport;
    final mapped = switch (next) {
      ConnectionState.ready => ChatConnection.ready,
      ConnectionState.connecting => ChatConnection.connecting,
      ConnectionState.reconnecting => ChatConnection.reconnecting,
      ConnectionState.disconnected ||
      ConnectionState.error => ChatConnection.error,
    };
    final wasDown = _state.connection == ChatConnection.reconnecting;
    if (mapped != ChatConnection.ready) _detachRequests();
    _emit(
      _state.copyWith(
        connection: mapped,
        connectionError: () => mapped == ChatConnection.ready
            ? null
            : _describe(transport?.lastError),
        needsSignIn:
            mapped == ChatConnection.error &&
            transport?.lastError is HermesAuthFailed,
      ),
    );
    if (mapped == ChatConnection.ready && wasDown) {
      // Live session ids do not survive a new socket: resume what was open.
      final loaded = _loaded.toList();
      for (final live in _live.values) {
        _connection?.unregister(live, _handler);
      }
      _live.clear();
      _threadOfLive.clear();
      _loaded.clear();
      for (final threadId in loaded) {
        unawaited(_resume(threadId));
      }
    }
  }

  static String? _describe(Object? error) => switch (error) {
    null => null,
    HermesException(:final message) => message,
    _ => '$error',
  };

  void _bindLive(String threadId, String liveId) {
    final previous = _live[threadId];
    if (previous != null) {
      _threadOfLive.remove(previous);
      _connection?.unregister(previous, _handler);
    }
    _live[threadId] = liveId;
    _threadOfLive[liveId] = threadId;
    _connection?.register(liveId, _handler);
  }

  Future<void> _resume(String threadId) async {
    final transport = _connection?.transport;
    if (transport == null) return;
    final SessionResumeResult result;
    try {
      result = await transport.call(
        HermesMethods.sessionResume,
        SessionResumeParams(sessionId: threadId),
      );
    } on Object catch (e) {
      _appendNotice(threadId, 'Could not load this chat: ${_describe(e)}');
      return;
    }
    if (_disposed) return;
    _bindLive(threadId, result.sessionId);
    _loaded.add(threadId);
    final history = _fromTranscript(threadId, result.messages);
    final title = result.info.title;
    _emit(
      _state.copyWith(
        threads: [
          for (final t in _state.threads)
            if (t.id == threadId)
              Thread(
                id: t.id,
                title: title.isEmpty ? t.title : title,
                startedAt: _startedAt(result) ?? t.startedAt,
                // Unanswered request cards are not part of the transcript.
                messages: [
                  ...history,
                  ...t.messages.where((m) => _pending.containsKey(m.id)),
                ],
              )
            else
              t,
        ],
        models: result.info.model.isEmpty
            ? null
            : {
                ..._state.models,
                threadId: ChatModel(
                  provider: result.info.provider,
                  model: result.info.model,
                ),
              },
        busyThreads: result.running == true
            ? {..._state.busyThreads, threadId}
            : ({..._state.busyThreads}..remove(threadId)),
      ),
    );
    _observer?.messagesSettled(_refOf(threadId), history);
    if (title.isNotEmpty) _observer?.sessionTitled(_refOf(threadId), title);
    for (final request in result.openRequests ?? const <OpenRequestEntry>[]) {
      transport.redeliverServerRequest(
        request.id,
        request.method,
        request.params,
      );
    }
    if (result.running != true) _settled(threadId);
  }

  /// Display time of the session's first message (`started_at`, else the
  /// first transcript timestamp), in epoch seconds from the server.
  static String? _startedAt(SessionResumeResult result) {
    final seconds =
        result.startedAt ??
        result.messages.map((m) => m.timestamp).whereType<double>().firstOrNull;
    if (seconds == null || seconds <= 0) return null;
    return formatChatTime(
      DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()),
    );
  }

  List<Message> _fromTranscript(
    String threadId,
    List<TranscriptMessage> transcript,
  ) {
    final out = <Message>[];
    for (final (index, m) in transcript.indexed) {
      final id = 'row-${m.rowId ?? '$threadId-$index'}';
      final text = m.text ?? (m.content is String ? m.content as String : '');
      switch (m.role) {
        case 'user':
          out.add(
            Message(id: id, author: Author.user, blocks: [TextBlock(text)]),
          );
        case 'assistant':
          final reasoning = m.reasoning ?? '';
          final blocks = [
            if (reasoning.isNotEmpty) ReasoningBlock(reasoning),
            if (text.isNotEmpty) TextBlock(text),
          ];
          // One agent turn is one bubble, as when it streamed live: the
          // tool-calling rows and the final answer merge; the message takes
          // the last row id (the turn's `final_assistant_row_id`).
          if (out.lastOrNull case final last?
              when last.author == Author.agent) {
            final hasReasoning = last.blocks.any((b) => b is ReasoningBlock);
            out[out.length - 1] = Message(
              id: id,
              author: Author.agent,
              blocks: [
                if (!hasReasoning && reasoning.isNotEmpty)
                  ReasoningBlock(reasoning),
                ...last.blocks,
                if (text.isNotEmpty) TextBlock(text),
              ],
            );
          } else {
            out.add(Message(id: id, author: Author.agent, blocks: blocks));
          }
        case 'tool' when isBrowserTool(m.name ?? ''):
          // Browser calls fold into one card, first in the turn's bubble.
          final toolId = m.toolCallId ?? id;
          final host = _urlHost(m.args?['url']);
          BrowserBlock update(BrowserBlock? current) {
            final kept = host.isEmpty ? current?.host ?? '' : host;
            return current?.copyWith(lastToolId: toolId, host: kept) ??
                BrowserBlock(lastToolId: toolId, running: false, host: kept);
          }

          if (out.lastOrNull case final last?
              when last.author == Author.agent) {
            out[out.length - 1] = last.copyWith(
              blocks: _upsertBrowser(last.blocks, update),
            );
          } else {
            out.add(
              Message(id: id, author: Author.agent, blocks: [update(null)]),
            );
          }
        case 'tool':
          // The transcript keeps tool results only for file edits.
          final result = m.text ?? m.content;
          final outcome = toolOutcome(result);
          final block = ToolCallBlock(
            toolId: m.toolCallId ?? id,
            name: m.name ?? 'tool',
            summary: m.context ?? '',
            detail: toolDetail(m.args),
            output: outcome.output,
            error: outcome.error,
            outcomeKnown: result != null,
            running: false,
          );
          // Tool rows attach to the assistant turn that called them.
          if (out.lastOrNull case final last?
              when last.author == Author.agent) {
            out[out.length - 1] = last.copyWith(
              blocks: [...last.blocks, block],
            );
          } else {
            out.add(Message(id: id, author: Author.agent, blocks: [block]));
          }
      }
    }
    return [
      for (final m in out)
        if (m.blocks.isNotEmpty) m,
    ];
  }

  // ---------------------------------------------------------------- events

  void _onEvent(HermesEvent event) {
    final threadId = _threadOfLive[event.sessionId];
    if (threadId == null) return;
    switch (event) {
      case MessageStartEvent():
        _startTurn(threadId);
      case MessageDeltaEvent(:final payload):
        _appendText(threadId, payload.text);
      // The live status line: an explained wait (API retry backoff, slow
      // provider) shows on the pending turn; spinner chatter clears it.
      case ThinkingDeltaEvent(:final payload):
        _setWait(threadId, _waitStatus(payload.text));
      case ReasoningDeltaEvent(:final payload):
        _addReasoning(threadId, payload.text);
      case ReasoningAvailableEvent(:final payload):
        // Non-streaming providers deliver the whole block at once.
        _addReasoning(threadId, payload.text, whole: true);
      case ToolStartEvent(:final payload) when isBrowserTool(payload.name):
        final host = _urlHost(payload.args?['url']);
        _updateTurn(
          threadId,
          (blocks) => _upsertBrowser(
            blocks,
            (current) => BrowserBlock(
              lastToolId: payload.toolId,
              step: browserStep(payload.name, payload.args),
              host: host.isEmpty ? current?.host ?? '' : host,
            ),
          ),
        );
      case ToolStartEvent(:final payload):
        _updateTurn(
          threadId,
          (blocks) => [
            ...blocks,
            ToolCallBlock(
              toolId: payload.toolId,
              name: payload.name,
              summary: payload.preview ?? payload.context ?? '',
              detail: toolDetail(payload.args),
            ),
          ],
        );
      case ToolCompleteEvent(:final payload):
        final summary = payload.summary ?? '';
        final detail = toolDetail(payload.args);
        final outcome = toolOutcome(payload.result);
        final seconds = payload.durationS;
        final duration = seconds == null
            ? null
            : Duration(milliseconds: (seconds * 1000).round());
        _updateTurn(
          threadId,
          (blocks) => [
            for (final b in blocks)
              if (b is BrowserBlock && isBrowserTool(payload.name))
                b.copyWith(lastToolId: payload.toolId)
              else if (b is ToolCallBlock && b.toolId == payload.toolId)
                b.done(
                  summary: summary.isEmpty ? b.summary : summary,
                  detail: detail,
                  output: outcome.output,
                  error: outcome.error,
                  duration: duration,
                )
              else
                b,
          ],
        );
        final activity = detail.isNotEmpty ? detail : summary;
        _observer?.toolCompleted(
          _refOf(threadId),
          ActivityItem(
            tool: payload.name,
            summary: activity.length > 300
                ? '${activity.substring(0, 299)}…'
                : activity,
            at: _now(),
            sessionId: _isDraft(threadId) ? '' : threadId,
          ),
        );
      case MessageCompleteEvent(:final payload):
        _completeTurn(threadId, payload);
      case HermesErrorEvent(:final payload):
        _appendNotice(threadId, payload.message, isError: true);
        _endTurn(threadId);
      case SessionTitleEvent(:final payload):
        _setTitle(threadId, payload.title);
        _observer?.sessionTitled(_refOf(threadId), payload.title);
      // Model switches (`/model`, `config.set`) announce the new model here.
      // Hermes also sends one when a turn is over and its session idle again
      // (`running` is cleared after `message.complete`).
      case SessionInfoEvent(:final payload):
        if (payload.model.isNotEmpty) {
          _emit(
            _state.copyWith(
              models: {
                ..._state.models,
                threadId: ChatModel(
                  provider: payload.provider,
                  model: payload.model,
                ),
              },
            ),
          );
        }
        if (!payload.running) _settled(threadId);
      case RequestCancelEvent(:final payload):
        _cancelRequest(payload.id, payload.reason);
      default:
        break;
    }
  }

  String _startTurn(String threadId) {
    final id = 'turn-${_seq++}';
    _turn[threadId] = id;
    _emit(
      _updateThread(
        threadId,
        (m) => [...m, Message(id: id, author: Author.agent, blocks: const [])],
      ).copyWith(busyThreads: {..._state.busyThreads, threadId}),
    );
    return id;
  }

  /// Applies [update] to the running turn's blocks, starting a turn when none
  /// runs. Whatever the turn shows next replaces its wait line.
  void _updateTurn(String threadId, List<Block> Function(List<Block>) update) {
    final id = _turn[threadId] ?? _startTurn(threadId);
    _emit(
      _updateMessage(
        threadId,
        id,
        (m) => m.copyWith(
          blocks: update([
            for (final b in m.blocks)
              if (b is! WaitBlock) b,
          ]),
        ),
      ),
    );
  }

  /// Shows [status] as the running turn's wait line; '' clears it.
  void _setWait(String threadId, String status) {
    final turnId = _turn[threadId];
    final current = _state.threads
        .where((t) => t.id == threadId)
        .expand((t) => t.messages)
        .where((m) => m.id == turnId)
        .expand((m) => m.blocks)
        .whereType<WaitBlock>()
        .firstOrNull;
    if ((current?.text ?? '') == status) return;
    _updateTurn(
      threadId,
      (blocks) => [...blocks, if (status.isNotEmpty) WaitBlock(status)],
    );
  }

  /// A turn has one browser card, inserted first: [update] replaces it where
  /// it is, or builds it (from null) when the turn has none yet.
  static List<Block> _upsertBrowser(
    List<Block> blocks,
    BrowserBlock Function(BrowserBlock? current) update,
  ) {
    final index = blocks.indexWhere((b) => b is BrowserBlock);
    if (index < 0) return [update(null), ...blocks];
    return [
      for (final (i, b) in blocks.indexed)
        if (i == index) update(b as BrowserBlock) else b,
    ];
  }

  void _appendText(String threadId, String delta) =>
      _updateTurn(threadId, (blocks) {
        if (blocks.lastOrNull case TextBlock(:final text)) {
          return [...blocks.take(blocks.length - 1), TextBlock(text + delta)];
        }
        return [...blocks, TextBlock(delta)];
      });

  /// A turn has one reasoning block, first in the bubble: deltas extend it
  /// wherever they arrive (between tool calls, after text); a [whole] block
  /// only fills it when nothing streamed.
  void _addReasoning(String threadId, String text, {bool whole = false}) {
    if (text.isEmpty) return;
    _updateTurn(threadId, (blocks) {
      final existing = blocks.whereType<ReasoningBlock>().firstOrNull;
      if (existing == null) return [ReasoningBlock(text), ...blocks];
      if (whole) return blocks;
      return [
        for (final b in blocks)
          if (identical(b, existing))
            ReasoningBlock(existing.text + text)
          else
            b,
      ];
    });
  }

  void _completeTurn(String threadId, MessageCompletePayload payload) {
    if (!_turn.containsKey(threadId)) _startTurn(threadId);
    _adoptRowIds(threadId, payload.persistedTurn);
    final finalText = payload.text is String ? payload.text as String : '';
    _updateTurn(threadId, (blocks) {
      final streamed = blocks.whereType<TextBlock>().map((b) => b.text).join();
      final next = finalText.isNotEmpty && finalText != streamed
          ? [...blocks.where((b) => b is! TextBlock), TextBlock(finalText)]
          : [...blocks];
      switch (payload.status) {
        case TurnStatus.error:
          next.add(
            NoticeBlock(
              payload.error ?? payload.failureReason ?? 'The turn failed',
              isError: true,
            ),
          );
        case TurnStatus.interrupted:
          next.add(const NoticeBlock('Stopped'));
        default:
          break;
      }
      return [
        for (final b in next)
          if (b is ToolCallBlock && b.running)
            b.done(summary: b.summary)
          else
            b,
      ];
    });
    _endTurn(threadId);
  }

  /// Renames the turn's messages to their transcript row ids (`row-<n>`), the
  /// same ids a later `session.resume` yields, so caches stay deduplicated.
  void _adoptRowIds(String threadId, PersistedTurn? persisted) {
    final agentRow = persisted?.finalAssistantRowId;
    final userRow = persisted?.userRowId;
    final turnId = _turn[threadId];
    if (persisted == null || turnId == null) return;
    final thread = _state.threads.firstWhere((t) => t.id == threadId);
    final turnIndex = thread.messages.indexWhere((m) => m.id == turnId);
    final userIndex = thread.messages
        .take(turnIndex < 0 ? thread.messages.length : turnIndex)
        .toList()
        .lastIndexWhere((m) => m.author == Author.user);
    final renamed = [
      for (final (i, m) in thread.messages.indexed)
        if (i == turnIndex && agentRow != null)
          m.withId('row-$agentRow')
        else if (i == userIndex && userRow != null)
          m.withId('row-$userRow')
        else
          m,
    ];
    if (agentRow != null) _turn[threadId] = 'row-$agentRow';
    _emit(
      _state.copyWith(
        threads: [
          for (final t in _state.threads)
            t.id == threadId ? t.withMessages(renamed) : t,
        ],
      ),
    );
  }

  /// Every way a turn ends (complete, error, stop) settles its browser card
  /// and drops its wait line.
  void _endTurn(String threadId) {
    final turnId = _turn.remove(threadId);
    final settled = turnId == null
        ? _state
        : _updateMessage(
            threadId,
            turnId,
            (m) => m.blocks.any((b) => b is BrowserBlock || b is WaitBlock)
                ? m.copyWith(
                    blocks: [
                      for (final b in m.blocks)
                        if (b is BrowserBlock)
                          b.copyWith(running: false, step: '')
                        else if (b is! WaitBlock)
                          b,
                    ],
                  )
                : m,
          );
    _emit(
      settled.copyWith(busyThreads: {..._state.busyThreads}..remove(threadId)),
    );
    final thread = _state.threads.where((t) => t.id == threadId).firstOrNull;
    if (thread != null) {
      _observer?.messagesSettled(_refOf(threadId), thread.messages);
    }
    if (!_isDraft(threadId)) _observer?.turnEnded(_refOf(threadId));
  }

  void _appendNotice(String threadId, String text, {bool isError = true}) {
    _emit(
      _updateThread(
        threadId,
        (m) => [
          ...m,
          Message(
            id: 'notice-${_seq++}',
            author: Author.agent,
            blocks: [NoticeBlock(text, isError: isError)],
          ),
        ],
      ),
    );
  }

  void _setTitle(String threadId, String title) {
    if (title.isEmpty) return;
    _emit(
      _state.copyWith(
        threads: [
          for (final t in _state.threads)
            t.id == threadId
                ? Thread(
                    id: t.id,
                    title: title,
                    startedAt: t.startedAt,
                    messages: t.messages,
                  )
                : t,
        ],
      ),
    );
  }

  ChatState _updateThread(
    String threadId,
    List<Message> Function(List<Message>) update,
  ) => _state.copyWith(
    threads: [
      for (final t in _state.threads)
        t.id == threadId ? t.withMessages(update(t.messages)) : t,
    ],
  );

  ChatState _updateMessage(
    String threadId,
    String id,
    Message Function(Message) update,
  ) => _updateThread(
    threadId,
    (messages) => [for (final m in messages) m.id == id ? update(m) : m],
  );

  // ------------------------------------------------------ server requests

  Future<JsonObject> _onRequest(HermesServerRequest<JsonObject> request) {
    if (_disposed) throw const HermesRequestDetached();
    final threadId = _threadOfLive[request.sessionId];
    if (threadId == null) {
      throw UnsupportedError('no thread for ${request.sessionId}');
    }
    final List<ChoiceBlock> blocks;
    final _PendingRequest pending;
    switch (request) {
      case ApprovalServerRequest(:final params):
        final allowed = [
          for (final c in params.choices ?? _approvalLabels.keys.toList())
            if (_approvalLabels.containsKey(c) &&
                !(c == ApprovalChoice.always &&
                    params.allowPermanent == false) &&
                !(c == ApprovalChoice.session && params.allowSession == false))
              c,
        ];
        final description = params.description.isEmpty
            ? ''
            : '\n${params.description}';
        blocks = [
          ChoiceBlock(
            prompt: 'Approve this command?\n${params.command}$description',
            options: [for (final c in allowed) _approvalLabels[c]!],
            customPlaceholder: '',
          ),
        ];
        pending = _PendingRequest(request.id, approval: true);
      case ClarifyServerRequest(:final params):
        final questions = params.questions;
        if (questions != null && questions.isNotEmpty) {
          blocks = [
            for (final q in questions)
              ChoiceBlock(
                prompt: q.question,
                options: q.choices ?? const [],
                customPlaceholder: 'Type your answer',
              ),
          ];
          pending = _PendingRequest(
            request.id,
            questionIds: [for (final q in questions) q.qid],
          );
        } else {
          blocks = [
            ChoiceBlock(
              prompt: params.question ?? '',
              options: params.choices ?? const [],
              customPlaceholder: 'Type your answer',
            ),
          ];
          pending = _PendingRequest(request.id);
        }
      default:
        throw UnsupportedError('${request.method} is not supported yet');
    }
    final messageId = 'request-${request.id}';
    _pending[messageId] = pending;
    final next = _updateThread(
      threadId,
      (m) => [
        ...m,
        Message(id: messageId, author: Author.agent, blocks: blocks),
      ],
    );
    _emit(
      pending.approval
          ? next.copyWith(
              pendingApprovalIds: {...next.pendingApprovalIds, messageId},
            )
          : next,
    );
    return pending.completer.future;
  }

  /// Drops local prompts without making a decision on the server. Only the
  /// next resume's open_requests snapshot can restore actionable prompts.
  void _detachRequests() {
    if (_pending.isEmpty) return;
    final messageIds = _pending.keys.toSet();
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(const HermesRequestDetached());
      }
    }
    _pending.clear();
    _emit(
      _state.copyWith(
        pendingApprovalIds: {..._state.pendingApprovalIds}
          ..removeAll(messageIds),
        threads: [
          for (final thread in _state.threads)
            thread.withMessages([
              for (final message in thread.messages)
                if (!messageIds.contains(message.id)) message,
            ]),
        ],
      ),
    );
  }

  /// Answers the choice at [blockIndex] of [messageId] (approval or clarify).
  void choose(String messageId, String answer, {int blockIndex = 0}) {
    if (_disposed || _state.connection != ChatConnection.ready) return;
    final trimmed = answer.trim();
    final pending = _pending[messageId];
    if (trimmed.isEmpty || pending == null) return;
    final threadId = _threadOfMessage(messageId);
    if (threadId == null) return;
    final message = _state.threads
        .firstWhere((t) => t.id == threadId)
        .messages
        .firstWhere((m) => m.id == messageId);
    final choices = message.blocks.whereType<ChoiceBlock>().toList();
    if (blockIndex >= choices.length) return;
    final choice = choices[blockIndex];
    if (pending.approval && !choice.options.contains(trimmed)) return;
    var seen = -1;
    _emit(
      _updateMessage(
        threadId,
        messageId,
        (m) => m.copyWith(
          blocks: [
            for (final b in m.blocks)
              if (b is ChoiceBlock && ++seen == blockIndex)
                b.withSelected(trimmed)
              else
                b,
          ],
        ),
      ),
    );
    if (pending.approval) {
      final choiceValue = _approvalLabels.entries
          .firstWhere((e) => e.value == trimmed)
          .key;
      _resolve(messageId, ApprovalResult(choice: choiceValue));
      return;
    }
    final qids = pending.questionIds;
    if (qids == null) {
      _resolve(messageId, ClarifyResult(answer: trimmed));
      return;
    }
    pending.answers[qids[blockIndex]] = trimmed;
    if (pending.answers.length == qids.length) {
      _resolve(messageId, ClarifyResult(answers: Map.of(pending.answers)));
    }
  }

  void _resolve(String messageId, JsonObject result) {
    final pending = _pending.remove(messageId);
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(result);
    }
    _settleApproval(messageId);
  }

  /// [messageId] no longer waits on an answer.
  void _settleApproval(String messageId) {
    if (!_state.pendingApprovalIds.contains(messageId)) return;
    _emit(
      _state.copyWith(
        pendingApprovalIds: {..._state.pendingApprovalIds}..remove(messageId),
      ),
    );
  }

  void _cancelRequest(String requestId, String reason) {
    final messageId = 'request-$requestId';
    final pending = _pending.remove(messageId);
    if (pending == null) return;
    _settleApproval(messageId);
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(StateError('cancelled: $reason'));
    }
    final threadId = _threadOfMessage(messageId);
    if (threadId == null) return;
    _emit(
      _updateMessage(
        threadId,
        messageId,
        (m) => m.copyWith(
          blocks: [...m.blocks, NoticeBlock('Request closed ($reason)')],
        ),
      ),
    );
  }

  String? _threadOfMessage(String messageId) => _state.threads
      .where((t) => t.messages.any((m) => m.id == messageId))
      .firstOrNull
      ?.id;

  // --------------------------------------------------------- user actions

  /// Sends [text] to the active thread, creating its session on first use.
  ///
  /// A slash command of the server's catalog runs on the server instead
  /// ([_runCommand]); any other text, `/`-prefixed or not, goes to the agent.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final threadId = _state.activeThreadId;
    final replyTo = _state.replyTo;
    final replyToId = _state.replyToId;
    final transport = _connection?.transport;
    if (_slashCommand(trimmed) case (:final name, arg: _)
        when transport != null && _state.connection == ChatConnection.ready) {
      if (await _isServerCommand(transport, threadId, name)) {
        return _runCommand(transport, threadId, trimmed);
      }
    }
    _emit(_state.copyWith(replyToId: () => null));
    final quoted = replyTo == null
        ? trimmed
        : '${replyTo.plainText.split('\n').map((l) => '> $l').join('\n')}'
              '\n\n$trimmed';
    await _submit(
      threadId,
      Message(
        id: 'local-${_seq++}',
        author: Author.user,
        blocks: [TextBlock(trimmed)],
        replyToId: replyToId,
      ),
      quoted,
    );
  }

  /// Posts [message] in [threadId] and submits [text] as the agent's next
  /// turn.
  Future<void> _submit(String threadId, Message message, String text) async {
    var thread = threadId;
    _emit(_updateThread(thread, (m) => [...m, message]));
    final transport = _connection?.transport;
    if (transport == null || _state.connection != ChatConnection.ready) {
      _appendNotice(thread, 'Not connected — message not sent');
      return;
    }
    _emit(_state.copyWith(busyThreads: {..._state.busyThreads, thread}));
    try {
      thread = await _ensureSession(thread);
      await transport.call(
        HermesMethods.promptSubmit,
        PromptSubmitParams(sessionId: _live[thread]!, text: text),
      );
    } on Object catch (e) {
      _appendNotice(thread, 'Not sent: ${_describe(e)}');
      _emit(
        _state.copyWith(busyThreads: {..._state.busyThreads}..remove(thread)),
      );
    }
  }

  /// The stored id of [threadId]: a draft gets its session first, then the
  /// model picked for it meanwhile.
  Future<String> _ensureSession(String threadId) async {
    if (!_isDraft(threadId)) return threadId;
    final stored = await _createSession(threadId);
    if (_pendingModels.remove(threadId) case final model?) {
      await _applyModel(stored, model);
    }
    return stored;
  }

  /// Whether `/[name]` is in the server's command catalog (`commands.catalog`:
  /// built-ins and their aliases, quick, plugin and skill commands). An
  /// unreadable catalog knows no command: the text goes to the agent.
  Future<bool> _isServerCommand(
    HermesTransport transport,
    String threadId,
    String name,
  ) async {
    final CommandsCatalogResult catalog;
    try {
      catalog = await transport.call(
        HermesMethods.commandsCatalog,
        CommandsCatalogParams(sessionId: _live[threadId]),
      );
    } on Object {
      return false;
    }
    final key = '/$name';
    return [
      ...?catalog.canon?.keys,
      for (final pair in catalog.pairs ?? const <List<String>>[])
        ?pair.firstOrNull,
      ...?catalog.skills?.keys,
    ].any((k) => k.toLowerCase() == key);
  }

  /// Runs the slash [command] typed in [threadId] on the server (`slash.exec`,
  /// like Hermes Desktop and the TUI): a command row shows it until the
  /// server answers, then its output. Commands that start a turn instead
  /// (skills, `/goal <text>`) post their prompt as the user's message.
  Future<void> _runCommand(
    HermesTransport transport,
    String threadId,
    String command,
  ) async {
    final rowId = 'command-${_seq++}';
    _emit(
      _updateThread(
        threadId,
        (m) => [
          ...m,
          Message(
            id: rowId,
            author: Author.agent,
            blocks: [CommandBlock(command: command)],
          ),
        ],
      ),
    );
    var thread = threadId;
    try {
      thread = await _ensureSession(thread);
    } on Object catch (e) {
      return _answerCommand(thread, rowId, '${_describe(e)}', isError: true);
    }
    await _attempt(transport, thread, rowId, command);
  }

  /// Runs [command] for the row [rowId]; a failure becomes the row's error.
  Future<void> _attempt(
    HermesTransport transport,
    String threadId,
    String rowId,
    String command,
  ) async {
    try {
      await _execute(transport, threadId, rowId, command);
    } on Object catch (e) {
      _answerCommand(threadId, rowId, '${_describe(e)}', isError: true);
    }
  }

  /// Runs [command] on the live session of [threadId] and answers the
  /// command row [rowId]; [hops] counts the aliases followed so far.
  ///
  /// Hermes refuses commands that change the session while a turn runs:
  /// with error 4009, or, for `/model`, `/personality`, `/prompt`, with a
  /// busy `warning` after the slash worker ran the command on its own copy
  /// only — the live agent kept its model. Either way nothing was applied:
  /// the command waits for the session to settle and runs again.
  Future<void> _execute(
    HermesTransport transport,
    String threadId,
    String rowId,
    String command, {
    int hops = 0,
  }) async {
    final parts = _slashCommand(command);
    if (parts == null) {
      return _answerCommand(
        threadId,
        rowId,
        'Not a command: $command',
        isError: true,
      );
    }
    final (:name, :arg) = parts;
    final live = _live[threadId]!;
    final settles = _settles[threadId] ?? 0;
    SlashExecResult result;
    try {
      try {
        result = await transport.call(
          HermesMethods.slashExec,
          SlashExecParams(sessionId: live, command: command.substring(1)),
        );
      } on HermesRpcError catch (e) {
        // Skills and snapshot restores are refused here: they run through
        // the command dispatcher, which answers the same directive fields.
        if (e.code != 4018 || !_dispatchOnly.hasMatch(e.message)) rethrow;
        final dispatched = await transport.call(
          HermesMethods.commandDispatch,
          CommandDispatchParams(name: name, arg: arg, sessionId: live),
        );
        result = SlashExecResult.fromJson(dispatched.toJson());
      }
    } on HermesRpcError catch (e) {
      if (e.code != _sessionBusy) rethrow;
      return _hold(transport, threadId, rowId, command, settles);
    }
    if (_busyWarning.hasMatch(result.warning ?? '')) {
      return _hold(transport, threadId, rowId, command, settles);
    }
    return _followDirective(
      transport,
      threadId,
      rowId,
      command,
      result,
      hops: hops,
    );
  }

  /// Keeps [command] waiting until [threadId]'s session settles; when it
  /// settled while the refusal was on its way ([settledBefore] idle reports
  /// seen at sending), it runs again right away.
  Future<void> _hold(
    HermesTransport transport,
    String threadId,
    String rowId,
    String command,
    int settledBefore,
  ) async {
    if ((_settles[threadId] ?? 0) > settledBefore) {
      return _attempt(transport, threadId, rowId, command);
    }
    _held.putIfAbsent(threadId, () => []).add((rowId: rowId, command: command));
    _emit(
      _updateMessage(
        threadId,
        rowId,
        (m) => m.copyWith(
          blocks: [
            for (final b in m.blocks)
              b is CommandBlock
                  ? CommandBlock(
                      command: b.command,
                      output:
                          'Waits for the current reply to end — '
                          'Stop ends it now.',
                    )
                  : b,
          ],
        ),
      ),
    );
  }

  /// [threadId]'s session is idle on the server: the commands it refused
  /// while busy run again, in order.
  void _settled(String threadId) {
    _settles[threadId] = (_settles[threadId] ?? 0) + 1;
    final held = _held.remove(threadId);
    final transport = _connection?.transport;
    if (held == null || transport == null) return;
    unawaited(() async {
      for (final c in held) {
        await _attempt(transport, threadId, c.rowId, c.command);
      }
    }());
  }

  /// Acts on the server's answer to [command]: output for the row, an alias
  /// to run instead, or a prompt to submit (`send`/`skill`).
  Future<void> _followDirective(
    HermesTransport transport,
    String threadId,
    String rowId,
    String command,
    SlashExecResult result, {
    required int hops,
  }) async {
    final notice = result.notice?.trim() ?? '';
    final message = result.message ?? '';
    switch (result.type$) {
      case DispatchType.alias:
        final target = (result.target ?? '').replaceFirst(RegExp('^/+'), '');
        if (target.isEmpty || hops >= 3) {
          return _answerCommand(
            threadId,
            rowId,
            'Could not follow the alias of $command',
            isError: true,
          );
        }
        final arg = _slashCommand(command)?.arg ?? '';
        return _execute(
          transport,
          threadId,
          rowId,
          '/$target${arg.isEmpty ? '' : ' $arg'}',
          hops: hops + 1,
        );
      case DispatchType.send || DispatchType.skill:
        if (message.trim().isEmpty) {
          return _answerCommand(
            threadId,
            rowId,
            'The server sent no prompt for $command',
            isError: true,
          );
        }
        if (notice.isEmpty) {
          _emit(
            _updateThread(
              threadId,
              (m) => [
                for (final x in m)
                  if (x.id != rowId) x,
              ],
            ),
          );
        } else {
          _answerCommand(threadId, rowId, notice);
        }
        // The bubble shows the invocation (`display`), never a skill's
        // expanded body: that is scaffolding for the model.
        final display = result.display?.trim() ?? '';
        final shown = display.isNotEmpty
            ? display
            : result.type$ == DispatchType.skill
            ? command
            : message.trim();
        return _submit(
          threadId,
          Message(
            id: 'local-${_seq++}',
            author: Author.user,
            blocks: [TextBlock(shown)],
          ),
          message,
        );
      case DispatchType.prefill:
        // `/undo`: the text to edit and resubmit stays readable in the row.
        return _answerCommand(
          threadId,
          rowId,
          [
            notice,
            message.trim(),
          ].where((part) => part.isNotEmpty).join('\n\n'),
        );
      case null ||
          DispatchType.exec ||
          DispatchType.plugin ||
          DispatchType.$unknown:
        // Worker output is CLI text: blank lines around it would show as
        // empty lines in the row; its indentation is kept.
        final output = (result.output ?? '(no output)')
            .replaceFirst(RegExp(r'^(?:[ \t]*\n)+'), '')
            .trimRight();
        final warning = result.warning?.trim() ?? '';
        return _answerCommand(
          threadId,
          rowId,
          warning.isEmpty ? output : 'warning: $warning\n$output',
        );
    }
  }

  void _answerCommand(
    String threadId,
    String rowId,
    String output, {
    bool isError = false,
  }) => _emit(
    _updateMessage(
      threadId,
      rowId,
      (m) => m.copyWith(
        blocks: [
          for (final b in m.blocks)
            b is CommandBlock ? b.done(output, isError: isError) : b,
        ],
      ),
    ),
  );

  Future<String> _createSession(String draftId) async {
    var parentId = _parents[draftId];
    // A side chat of a main chat not created yet: create the main session
    // first so the side chat is filed under it.
    if (parentId != null && _isDraft(parentId)) {
      parentId = await _createSession(parentId);
    }
    final draft = _state.threads.firstWhere((t) => t.id == draftId);
    final result = await _connection!.transport.call(
      HermesMethods.sessionCreate,
      SessionCreateParams(parentSessionId: parentId),
    );
    final storedId = result.storedSessionId;
    _emit(
      _state.copyWith(
        threads: [
          for (final t in _state.threads)
            t.id == draftId
                ? Thread(
                    id: storedId,
                    title: t.title,
                    startedAt: t.startedAt,
                    messages: t.messages,
                  )
                : t,
        ],
        activeThreadId: _state.activeThreadId == draftId
            ? storedId
            : _state.activeThreadId,
        busyThreads: {
          for (final id in _state.busyThreads) id == draftId ? storedId : id,
        },
      ),
    );
    for (final e in _parents.entries.toList()) {
      if (e.value == draftId) _parents[e.key] = storedId;
    }
    if (_parents.remove(draftId) case final parent?) {
      _parents[storedId] = parent;
    }
    _bindLive(storedId, result.sessionId);
    _loaded.add(storedId);
    _observer?.sessionCreated(
      _refOf(storedId),
      title: draft.title,
      parentId: _parents[storedId],
    );
    if (_state.activeThreadId == storedId) {
      _observer?.threadOpened(_refOf(storedId));
    }
    return storedId;
  }

  /// Switches the active thread's model (session-scoped `config.set model`,
  /// the same path as `/model` in Hermes). A draft thread applies it once its
  /// session is created.
  Future<void> setModel(ChatModel model) async {
    final threadId = _state.activeThreadId;
    _emit(_state.copyWith(models: {..._state.models, threadId: model}));
    if (_isDraft(threadId)) {
      _pendingModels[threadId] = model;
      return;
    }
    try {
      await _applyModel(threadId, model);
    } on Object catch (e) {
      _appendNotice(threadId, 'Could not switch model: ${_describe(e)}');
    }
  }

  Future<void> _applyModel(String threadId, ChatModel model) async {
    final live = _live[threadId];
    final transport = _connection?.transport;
    if (live == null || transport == null) return;
    await transport.call(
      HermesMethods.configSet,
      ConfigSetParams(
        key: 'model',
        value: '${model.model} --provider ${model.provider}',
        sessionId: live,
        scope: 'session',
      ),
    );
  }

  /// Stops the running turn of the active thread.
  Future<void> interrupt() async {
    final threadId = _state.activeThreadId;
    final live = _live[threadId];
    final transport = _connection?.transport;
    if (live == null || transport == null || !_state.busy) return;
    try {
      await transport.call(
        HermesMethods.sessionInterrupt,
        SessionInterruptParams(sessionId: live),
      );
    } on Object catch (e) {
      _appendNotice(threadId, 'Could not stop: ${_describe(e)}');
    }
  }

  void toggleReaction(String messageId, String emoji) {
    final threadId = _threadOfMessage(messageId);
    if (threadId == null) return;
    _emit(
      _updateMessage(threadId, messageId, (m) {
        final has = m.reactions.contains(emoji);
        return m.copyWith(
          reactions: has
              ? [
                  for (final r in m.reactions)
                    if (r != emoji) r,
                ]
              : [...m.reactions, emoji],
        );
      }),
    );
  }

  /// Picks an offer in a flight card; picking it again clears it.
  void selectOffer(String messageId, String offerId) {
    final next = Map.of(_state.selectedOffers);
    if (next[messageId] == offerId) {
      next.remove(messageId);
    } else {
      next[messageId] = offerId;
    }
    _emit(_state.copyWith(selectedOffers: next));
  }

  void startReply(String messageId) =>
      _emit(_state.copyWith(replyToId: () => messageId));

  void cancelReply() => _emit(_state.copyWith(replyToId: () => null));

  /// Shows the agent's computer (browser viewer) in place of the chat.
  void openComputer() => _emit(_state.copyWith(computerOpen: true));

  /// Returns from the computer viewer to the chat.
  void closeComputer() => _emit(_state.copyWith(computerOpen: false));

  /// Opens an empty side chat; its session is created on the first message
  /// and titled by the agent (an untitled thread has an empty [Thread.title]).
  void newSideChat() {
    final thread = Thread(
      id: _draftId(),
      title: '',
      startedAt: _clock(),
      messages: const [],
    );
    _parents[thread.id] = _state.mainThread.id;
    _emit(
      _state.copyWith(
        threads: [..._state.threads, thread],
        activeThreadId: thread.id,
        replyToId: () => null,
      ),
    );
  }

  void openThread(String threadId) {
    if (threadId == _state.activeThreadId) return;
    _emit(_state.copyWith(activeThreadId: threadId, replyToId: () => null));
    if (!_isDraft(threadId)) {
      _observer?.threadOpened(_refOf(threadId));
      if (!_loaded.contains(threadId)) unawaited(_resume(threadId));
    }
  }

  /// Renames a side chat (`session.title` on its live session). Throws the
  /// server error; a draft is renamed locally.
  Future<void> renameThread(String threadId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    if (!_isDraft(threadId)) {
      final transport = _requireTransport();
      if (_live[threadId] == null) await _resume(threadId);
      final live = _live[threadId];
      if (live == null) throw StateError('could not open $threadId');
      await transport.call(
        HermesMethods.sessionTitle,
        SessionTitleParams(sessionId: live, title: trimmed),
      );
      _observer?.sessionTitled(_refOf(threadId), trimmed);
    }
    _setTitle(threadId, trimmed);
  }

  /// Archives a side chat: hidden on the server, dropped from [ChatState]
  /// (the main chat opens if it was on screen). Throws the server error.
  Future<void> archiveThread(String threadId) async {
    if (!_isDraft(threadId)) {
      await _requireTransport().call(
        HermesMethods.sessionSetHidden,
        SessionSetHiddenParams(sessionId: threadId, hidden: true),
      );
      _observer?.sessionArchived(_refOf(threadId), archived: true);
    }
    _dropThread(threadId);
  }

  /// Brings an archived side chat of this main chat back into the list.
  Future<void> restoreThread(String sessionId, {required String title}) async {
    await _requireTransport().call(
      HermesMethods.sessionSetHidden,
      SessionSetHiddenParams(sessionId: sessionId, hidden: false),
    );
    _observer?.sessionArchived(_refOf(sessionId), archived: false);
    if (_state.threads.any((t) => t.id == sessionId)) return;
    _parents[sessionId] = _state.mainThread.id;
    _emit(
      _state.copyWith(
        threads: [
          ..._state.threads,
          Thread(id: sessionId, title: title, startedAt: '', messages: []),
        ],
      ),
    );
  }

  /// Deletes a side chat and its transcript on the server (its live session
  /// is closed first: Hermes refuses to delete a live session). Throws the
  /// server error.
  Future<void> deleteThread(String threadId) async {
    if (!_isDraft(threadId)) {
      final transport = _requireTransport();
      if (_live[threadId] case final live?) {
        await transport.call(
          HermesMethods.sessionClose,
          SessionCloseParams(sessionId: live),
        );
        _threadOfLive.remove(live);
        _live.remove(threadId);
        _connection?.unregister(live, _handler);
      }
      await transport.call(
        HermesMethods.sessionDelete,
        SessionDeleteParams(sessionId: threadId),
      );
      _observer?.sessionDeleted(_refOf(threadId));
    }
    _dropThread(threadId);
  }

  HermesTransport _requireTransport() {
    final transport = _connection?.transport;
    if (transport == null || _state.connection != ChatConnection.ready) {
      throw StateError('Not connected');
    }
    return transport;
  }

  /// Removes a side thread from the state; the main chat opens in its place.
  void _dropThread(String threadId) {
    if (threadId == _state.mainThread.id) {
      throw ArgumentError.value(threadId, 'threadId', 'the main chat stays');
    }
    _parents.remove(threadId);
    _loaded.remove(threadId);
    final wasActive = _state.activeThreadId == threadId;
    _emit(
      _state.copyWith(
        threads: [
          for (final t in _state.threads)
            if (t.id != threadId) t,
        ],
        activeThreadId: wasActive ? _state.mainThread.id : null,
        busyThreads: {..._state.busyThreads}..remove(threadId),
        replyToId: wasActive ? () => null : null,
      ),
    );
    if (wasActive && !_isDraft(_state.mainThread.id)) {
      _observer?.threadOpened(_refOf(_state.mainThread.id));
    }
  }

  /// Detaches from the connection; unanswered requests are left to the
  /// server (they reappear as `open_requests` on the next resume).
  Future<void> dispose() async {
    _disposed = true;
    _listeners.clear();
    _detachRequests();
    for (final live in _live.values) {
      _connection?.unregister(live, _handler);
    }
    await _eventsSub?.cancel();
    await _stateSub?.cancel();
  }
}

final class _PendingRequest {
  _PendingRequest(this.requestId, {this.approval = false, this.questionIds});

  final String requestId;
  final bool approval;

  /// Batch clarify question ids, in block order.
  final List<String>? questionIds;
  final Map<String, String> answers = {};
  final completer = Completer<JsonObject>();
}

String _wallClock() => formatChatTime(DateTime.now());

/// "1:05 PM" (local time), the thread header format.
String formatChatTime(DateTime time) {
  final local = time.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// `/name arg…`: a `/` then a bare name (`/usr/bin` and `/ x` are prose),
/// the argument's interior kept verbatim (Hermes' `apps/shared/src/slash.ts`).
final _slashPattern = RegExp(r'^/([^\s/]+)(?:\s+([\s\S]*))?$');

/// [text] split as a slash command (name lower-cased, like every Hermes
/// surface), or null when it is not one.
({String name, String arg})? _slashCommand(String text) {
  final match = _slashPattern.firstMatch(text.trim());
  if (match == null) return null;
  return (name: match[1]!.toLowerCase(), arg: (match[2] ?? '').trim());
}

/// `slash.exec` refusals (code 4018) that mean "run this through
/// `command.dispatch`": skill commands and `/snapshot restore`
/// (`tui_gateway/methods_tools.py`). Other 4018s come from a dispatcher
/// `slash.exec` already forwarded to; running them again would repeat them.
final _dispatchOnly = RegExp(
  r'^skill command: use command\.dispatch for /|'
  r'use command\.dispatch for /snapshot restore',
);

/// JSON-RPC error of a command refused because the session is running a
/// turn (`tui_gateway/methods_tools.py::_busy_error`).
const _sessionBusy = 4009;

/// `slash.exec`'s `warning` when the live session refused the command's
/// effect because a turn was running (`tui_gateway/user_messages.py::
/// busy_message`, via `methods_slash.py::_mirror_slash_side_effects`).
final _busyWarning = RegExp(r'^session busy\b');

/// Browser card status line of a `browser_*` tool call ([args] as sent in
/// `tool.start`).
String browserStep(String name, Map<String, Object?>? args) => switch (name) {
  'browser_navigate' => switch (_urlHost(args?['url'])) {
    '' => 'Opening page',
    final host => 'Opening $host',
  },
  'browser_click' => 'Clicking',
  'browser_type' => 'Typing',
  'browser_press' => 'Pressing keys',
  'browser_scroll' => 'Scrolling',
  'browser_back' => 'Going back',
  'browser_snapshot' ||
  'browser_vision' ||
  'browser_get_images' ||
  'browser_console' => 'Reading page',
  _ => 'Working in browser',
};

/// Host of a tool's `url` argument (`https://` assumed without a scheme),
/// or '' when there is none.
String _urlHost(Object? url) {
  if (url is! String || url.trim().isEmpty) return '';
  final trimmed = url.trim();
  return Uri.tryParse(trimmed.contains('://') ? trimmed : 'https://$trimmed')
          ?.host ??
      '';
}

/// An API retry backoff as Hermes words it on the live status line
/// (`agent/turn_recovery.py::compute_error_backoff`):
/// `⏳ rate limited — resets in ~13m, retrying in 600s (attempt 1/3)`.
final _retryWait = RegExp(
  r'^⏳\s*(.*?)\s*retrying in (\d+(?:\.\d+)?)s \(attempt (\d+)/(\d+)\)',
);

/// The other waits Hermes explains there (the frames Hermes Desktop shows):
/// a silent or reconnecting provider, a local model loading.
final _explainedWait = RegExp(
  r'^(?:⏳|⚠|↻|⚙)\uFE0F?\s*(?:(?:still\s+)?waiting on|loading|'
  r'processing prompt|no (?:output|response)|model returned)',
  caseSensitive: false,
);

/// The pending turn's wait line for a `thinking.delta` frame, or '' for the
/// spinner's chatter (`(◕‿◕) pondering...`, '' between API attempts).
String _waitStatus(String frame) {
  final text = frame.trim();
  if (_retryWait.firstMatch(text) case final retry?) {
    final seconds = double.parse(retry[2]!).round();
    final wait = seconds < 60 ? '${seconds}s' : '${(seconds / 60).round()} min';
    final reason = retry[1]!
        .replaceFirst(RegExp(r'[\s,—]+$'), '')
        .replaceAll(' — ', ', ');
    final line = 'Retrying in $wait (attempt ${retry[3]}/${retry[4]})';
    return reason.isEmpty ? line : '$line — $reason';
  }
  if (!_explainedWait.hasMatch(text)) return '';
  final line = text.replaceFirst(RegExp(r'^\S+\s*'), '');
  return '${line[0].toUpperCase()}${line.substring(1)}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Side chat list time-ago: "just now", "3m", "4h", "Sat" within a
/// week, else "Sep 26".
String formatTimeAgo(DateTime at, DateTime now) {
  final age = now.difference(at);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  final local = at.toLocal();
  if (age.inDays < 7) return _weekdays[local.weekday - 1];
  return '${_months[local.month - 1]} ${local.day}';
}

/// A stored timestamp (the plugin's ISO-8601 `created_at`, a timeline
/// entry's `at`) in the [formatTimeAgo] style; text that is not a timestamp
/// comes back unchanged.
String formatTimestamp(String stamp, DateTime now) {
  final at = DateTime.tryParse(stamp);
  return at == null ? stamp : formatTimeAgo(at, now);
}
