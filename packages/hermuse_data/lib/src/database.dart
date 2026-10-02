import 'package:drift/drift.dart';
import 'package:hermes_client/hermes_client.dart';

part 'database.g.dart';

/// A cached transcript message of `(instanceId, sessionId)`.
typedef CachedMessage = MessageRow;

@DriftDatabase(include: {'tables.drift'})
final class HermuseDatabase extends _$HermuseDatabase {
  HermuseDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Side chat archive and pins.
        await m.addColumn(sessions, sessions.archived);
        await m.addColumn(sessions, sessions.pinnedAt);
      }
      if (from < 3) {
        // The profile panel's Activity.
        await m.createTable(activity);
        await m.createIndex(activityByTime);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // ---------------------------------------------------------------- instances

  Stream<List<HermesInstance>> watchInstances() =>
      (select(instances)
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch()
          .map((rows) => rows.map(_toInstance).toList());

  Future<List<HermesInstance>> loadInstances() async =>
      (await (select(
            instances,
          )..orderBy([(t) => OrderingTerm(expression: t.position)])).get())
          .map(_toInstance)
          .toList();

  Future<String?> loadPrimaryInstanceId() async => (await (select(
    instances,
  )..where((t) => t.isPrimary)).getSingleOrNull())?.id;

  /// Replaces the whole instance list (registry commits are small).
  Future<void> saveInstances(List<HermesInstance> list, {String? primaryId}) =>
      transaction(() async {
        final keep = list.map((i) => i.id).toSet();
        await (delete(instances)..where((t) => t.id.isNotIn(keep))).go();
        for (final (index, i) in list.indexed) {
          await into(instances).insertOnConflictUpdate(
            InstancesCompanion.insert(
              id: i.id,
              label: i.label,
              kind: i.kind.name,
              baseUrl: i.baseUrl.toString(),
              auth: i.auth.name,
              profile: Value(i.profile),
              isPrimary: Value(i.id == primaryId),
              position: index,
            ),
          );
        }
      });

  static HermesInstance _toInstance(InstanceRow r) => HermesInstance(
    id: r.id,
    label: r.label,
    kind: InstanceKind.values.byName(r.kind),
    baseUrl: Uri.parse(r.baseUrl),
    auth: AuthMethod.values.byName(r.auth),
    profile: r.profile,
  );

  // ----------------------------------------------------------------- sessions

  /// Side chats of the main session [parentId]: pinned first (most recently
  /// pinned on top), then by last activity. [archived] selects the archive.
  Stream<List<SessionRow>> watchSideChats(
    String instanceId,
    String parentId, {
    bool archived = false,
  }) => _sideChats(instanceId, parentId, archived).watch();

  /// One-shot variant of [watchSideChats] (same order). Use it for single
  /// reads: `.first` on a watch stream pauses/cancels the subscription and
  /// never resolves under a fake-async test zone.
  Future<List<SessionRow>> loadSideChats(
    String instanceId,
    String parentId, {
    bool archived = false,
  }) => _sideChats(instanceId, parentId, archived).get();

  SimpleSelectStatement<Sessions, SessionRow> _sideChats(
    String instanceId,
    String parentId,
    bool archived,
  ) => select(sessions)
    ..where(
      (t) =>
          t.instanceId.equals(instanceId) &
          t.parentId.equals(parentId) &
          t.archived.equals(archived),
    )
    ..orderBy([
      (t) => OrderingTerm(expression: t.pinnedAt.isNull()),
      (t) => OrderingTerm(expression: t.pinnedAt, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);

  /// One cached session (the main chat's last activity), null if unknown.
  Stream<SessionRow?> watchSession(String instanceId, String sessionId) =>
      _session(instanceId, sessionId).watchSingleOrNull();

  Future<SessionRow?> loadSession(String instanceId, String sessionId) =>
      _session(instanceId, sessionId).getSingleOrNull();

  SimpleSelectStatement<Sessions, SessionRow> _session(
    String instanceId,
    String sessionId,
  ) => select(sessions)
    ..where(
      (t) => t.instanceId.equals(instanceId) & t.sessionId.equals(sessionId),
    );

  Future<void> upsertSession(SessionRow row) =>
      into(sessions).insertOnConflictUpdate(row);

  Future<void> renameSession(
    String instanceId,
    String sessionId,
    String title,
  ) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(title: Value(title)),
  );

  /// Records activity on a session (orders the side chat list).
  Future<void> touchSession(String instanceId, String sessionId, int at) =>
      _updateSession(
        instanceId,
        sessionId,
        SessionsCompanion(updatedAt: Value(at)),
      );

  /// Archiving also unpins.
  Future<void> setSessionArchived(
    String instanceId,
    String sessionId, {
    required bool archived,
  }) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(
      archived: Value(archived),
      pinnedAt: archived ? const Value(null) : const Value.absent(),
    ),
  );

  /// Pins at [at] (ms since epoch), or unpins when null.
  Future<void> setSessionPinned(String instanceId, String sessionId, int? at) =>
      _updateSession(
        instanceId,
        sessionId,
        SessionsCompanion(pinnedAt: Value(at)),
      );

  /// Drops a session and (by cascade) its cached transcript.
  Future<void> deleteSession(String instanceId, String sessionId) =>
      (delete(sessions)..where(
            (t) =>
                t.instanceId.equals(instanceId) & t.sessionId.equals(sessionId),
          ))
          .go();

  Future<void> _updateSession(
    String instanceId,
    String sessionId,
    SessionsCompanion changes,
  ) =>
      (update(sessions)..where(
            (t) =>
                t.instanceId.equals(instanceId) & t.sessionId.equals(sessionId),
          ))
          .write(changes);

  // ----------------------------------------------------------------- messages

  Future<List<CachedMessage>> loadMessages(
    String instanceId,
    String sessionId,
  ) =>
      (select(messages)
            ..where(
              (t) =>
                  t.instanceId.equals(instanceId) &
                  t.sessionId.equals(sessionId),
            )
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  Future<void> upsertMessages(List<CachedMessage> rows) => batch((b) {
    b.insertAllOnConflictUpdate(messages, rows);
  });

  /// Caches a transcript, indexing its session first if it is unknown
  /// (a chat opened by id before any session sync).
  Future<void> cacheTranscript(
    String instanceId,
    String sessionId,
    List<CachedMessage> rows,
  ) => batch((b) {
    b.insert(
      sessions,
      SessionsCompanion.insert(
        instanceId: instanceId,
        sessionId: sessionId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    b.insertAllOnConflictUpdate(messages, rows);
  });

  /// Full-text search over the cached transcripts of [sessionIds] on
  /// [instanceId], best match first (FTS5; the input is quoted per term so
  /// user punctuation cannot break the query).
  Future<List<CachedMessage>> search(
    String text, {
    required String instanceId,
    required Iterable<String> sessionIds,
    int limit = 50,
  }) async {
    final terms = text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*');
    final ids = sessionIds.toList();
    if (terms.isEmpty || ids.isEmpty) return const [];
    final rows = await searchMessages(
      terms.join(' '),
      instanceId,
      ids,
      limit,
    ).get();
    return [for (final r in rows) r.m];
  }

  // ----------------------------------------------------------------- activity

  /// Rows kept per instance; older ones go as new ones arrive.
  static const activityKept = 500;

  /// Records a finished tool of [instanceId] and drops what falls past
  /// [activityKept].
  Future<void> addActivity({
    required String instanceId,
    required String sessionId,
    required String tool,
    required String summary,
    required DateTime at,
  }) => transaction(() async {
    await into(activity).insert(
      ActivityCompanion.insert(
        instanceId: instanceId,
        sessionId: sessionId,
        tool: tool,
        summary: Value(summary),
        at: at.millisecondsSinceEpoch,
      ),
    );
    await customStatement(
      'DELETE FROM activity WHERE instance_id = ? AND id NOT IN '
      '(SELECT id FROM activity WHERE instance_id = ? '
      'ORDER BY at DESC, id DESC LIMIT ?)',
      [instanceId, instanceId, activityKept],
    );
  });

  /// Activity of [instanceId], newest first.
  Stream<List<ActivityRow>> watchActivity(
    String instanceId, {
    int limit = 200,
  }) =>
      (select(activity)
            ..where((t) => t.instanceId.equals(instanceId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.at),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(limit))
          .watch();

  // ----------------------------------------------------------------- settings

  Future<String?> readSetting(String key) async => (await (select(
    settings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingRow(key: key, value: value));
}

/// [InstanceStore] backed by [HermuseDatabase].
final class DriftInstanceStore implements InstanceStore {
  DriftInstanceStore(this._db);
  final HermuseDatabase _db;

  @override
  Future<List<HermesInstance>> load() => _db.loadInstances();

  @override
  Future<String?> loadPrimaryId() => _db.loadPrimaryInstanceId();

  @override
  Future<void> save(List<HermesInstance> instances, {String? primaryId}) =>
      _db.saveInstances(instances, primaryId: primaryId);
}
