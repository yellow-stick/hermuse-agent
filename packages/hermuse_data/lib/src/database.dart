import 'package:drift/drift.dart';
import 'package:hermes_client/hermes_client.dart';

part 'database.g.dart';

/// A cached transcript message of `(instanceId, profile, sessionId)`.
typedef CachedMessage = MessageRow;

@DriftDatabase(include: {'tables.drift'})
final class HermuseDatabase extends _$HermuseDatabase {
  HermuseDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Side chat archive and pins.
        await m.addColumn(sessions, sessions.archived);
        await m.addColumn(sessions, sessions.pinnedAt);
      }
      // Version 3 added a device-local Activity table, dropped by version 5
      // (Activity now comes from the server): older databases skip it.
      if (from < 4) {
        // Rebuild composite keys before copying rows. A legacy registered
        // profile owns its existing cache; otherwise it belongs to default.
        await customStatement(
          'CREATE TEMP TABLE old_sessions AS SELECT * FROM sessions',
        );
        await customStatement(
          'CREATE TEMP TABLE old_messages AS SELECT * FROM messages',
        );
        for (final trigger in [
          messagesFtsInsert,
          messagesFtsDelete,
          messagesFtsUpdate,
        ]) {
          await customStatement('DROP TRIGGER ${trigger.entityName}');
        }
        await customStatement('DROP TABLE messages_fts');
        await customStatement('DROP TABLE messages');
        await customStatement('DROP TABLE sessions');
        await m.createTable(sessions);
        await m.createTable(messages);
        await m.createTable(messagesFts);
        await m.createTrigger(messagesFtsInsert);
        await m.createTrigger(messagesFtsDelete);
        await m.createTrigger(messagesFtsUpdate);
        const legacyProfile = "COALESCE(NULLIF(i.profile, ''), 'default')";
        await customStatement(
          'INSERT INTO sessions '
          '(instance_id, profile, session_id, title, parent_id, updated_at, '
          'archived, pinned_at) '
          'SELECT s.instance_id, $legacyProfile, s.session_id, s.title, '
          's.parent_id, s.updated_at, s.archived, s.pinned_at '
          'FROM old_sessions s JOIN instances i ON i.id = s.instance_id',
        );
        await customStatement(
          'INSERT INTO messages '
          '(instance_id, profile, session_id, message_id, author, body_text, '
          'created_at) '
          'SELECT m.instance_id, $legacyProfile, m.session_id, m.message_id, '
          'm.author, m.body_text, m.created_at '
          'FROM old_messages m JOIN instances i ON i.id = m.instance_id',
        );
        await customStatement('DROP TABLE old_messages');
        await customStatement('DROP TABLE old_sessions');
        final namedInstances = await customSelect(
          "SELECT id, profile FROM instances "
          "WHERE profile IS NOT NULL AND profile NOT IN ('', 'default')",
        ).get();
        for (final instance in namedInstances) {
          final id = instance.read<String>('id');
          final profile = Uri.encodeComponent(instance.read<String>('profile'));
          final settingsRows = await select(settings).get();
          for (final setting in settingsRows) {
            final key = setting.key;
            final modelPrefix = 'model_selection:$id:';
            final String? scopedKey;
            if (key == 'main_session:$id' || key == 'open_thread:$id') {
              scopedKey = '$key:profile:$profile';
            } else if (key.startsWith(modelPrefix) &&
                !key.substring(modelPrefix.length).startsWith('profile:')) {
              scopedKey =
                  '${modelPrefix}profile:$profile:'
                  '${key.substring(modelPrefix.length)}';
            } else {
              scopedKey = null;
            }
            if (scopedKey == null) continue;
            await customStatement(
              'INSERT OR IGNORE INTO settings ("key", value) VALUES (?, ?)',
              [scopedKey, setting.value],
            );
            await customStatement('DELETE FROM settings WHERE "key" = ?', [
              key,
            ]);
          }
        }
      }
      if (from < 5) {
        await customStatement('DROP TABLE IF EXISTS activity');
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
    String profile = 'default',
  }) => _sideChats(instanceId, parentId, archived, profile).watch();

  /// One-shot variant of [watchSideChats] (same order). Use it for single
  /// reads: `.first` on a watch stream pauses/cancels the subscription and
  /// never resolves under a fake-async test zone.
  Future<List<SessionRow>> loadSideChats(
    String instanceId,
    String parentId, {
    bool archived = false,
    String profile = 'default',
  }) => _sideChats(instanceId, parentId, archived, profile).get();

  SimpleSelectStatement<Sessions, SessionRow> _sideChats(
    String instanceId,
    String parentId,
    bool archived,
    String profile,
  ) => select(sessions)
    ..where(
      (t) =>
          t.instanceId.equals(instanceId) &
          t.profile.equals(profile) &
          t.parentId.equals(parentId) &
          t.archived.equals(archived),
    )
    ..orderBy([
      (t) => OrderingTerm(expression: t.pinnedAt.isNull()),
      (t) => OrderingTerm(expression: t.pinnedAt, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);

  /// One cached session (the main chat's last activity), null if unknown.
  Stream<SessionRow?> watchSession(
    String instanceId,
    String sessionId, {
    String profile = 'default',
  }) => _session(instanceId, sessionId, profile).watchSingleOrNull();

  Future<SessionRow?> loadSession(
    String instanceId,
    String sessionId, {
    String profile = 'default',
  }) => _session(instanceId, sessionId, profile).getSingleOrNull();

  SimpleSelectStatement<Sessions, SessionRow> _session(
    String instanceId,
    String sessionId,
    String profile,
  ) => select(sessions)
    ..where(
      (t) =>
          t.instanceId.equals(instanceId) &
          t.profile.equals(profile) &
          t.sessionId.equals(sessionId),
    );

  Future<void> upsertSession(SessionRow row) =>
      into(sessions).insertOnConflictUpdate(row);

  /// Files the side chats of the main session [from] under [to] (the main
  /// chat moved to another session).
  Future<void> reparentSideChats(
    String instanceId, {
    required String from,
    required String to,
    String profile = 'default',
  }) =>
      (update(sessions)..where(
            (t) =>
                t.instanceId.equals(instanceId) &
                t.profile.equals(profile) &
                t.parentId.equals(from),
          ))
          .write(SessionsCompanion(parentId: Value(to)));

  Future<void> renameSession(
    String instanceId,
    String sessionId,
    String title, {
    String profile = 'default',
  }) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(title: Value(title)),
    profile: profile,
  );

  /// Records activity on a session (orders the side chat list).
  Future<void> touchSession(
    String instanceId,
    String sessionId,
    int at, {
    String profile = 'default',
  }) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(updatedAt: Value(at)),
    profile: profile,
  );

  /// Archiving also unpins.
  Future<void> setSessionArchived(
    String instanceId,
    String sessionId, {
    required bool archived,
    String profile = 'default',
  }) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(
      archived: Value(archived),
      pinnedAt: archived ? const Value(null) : const Value.absent(),
    ),
    profile: profile,
  );

  /// Pins at [at] (ms since epoch), or unpins when null.
  Future<void> setSessionPinned(
    String instanceId,
    String sessionId,
    int? at, {
    String profile = 'default',
  }) => _updateSession(
    instanceId,
    sessionId,
    SessionsCompanion(pinnedAt: Value(at)),
    profile: profile,
  );

  /// Drops a session and (by cascade) its cached transcript.
  Future<void> deleteSession(
    String instanceId,
    String sessionId, {
    String profile = 'default',
  }) =>
      (delete(sessions)..where(
            (t) =>
                t.instanceId.equals(instanceId) &
                t.profile.equals(profile) &
                t.sessionId.equals(sessionId),
          ))
          .go();

  Future<void> _updateSession(
    String instanceId,
    String sessionId,
    SessionsCompanion changes, {
    String profile = 'default',
  }) =>
      (update(sessions)..where(
            (t) =>
                t.instanceId.equals(instanceId) &
                t.profile.equals(profile) &
                t.sessionId.equals(sessionId),
          ))
          .write(changes);

  // ----------------------------------------------------------------- messages

  Future<List<CachedMessage>> loadMessages(
    String instanceId,
    String sessionId, {
    String profile = 'default',
  }) =>
      (select(messages)
            ..where(
              (t) =>
                  t.instanceId.equals(instanceId) &
                  t.profile.equals(profile) &
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
    List<CachedMessage> rows, {
    String profile = 'default',
  }) => batch((b) {
    b.insert(
      sessions,
      SessionsCompanion.insert(
        instanceId: instanceId,
        profile: Value(profile),
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
    String profile = 'default',
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
      profile,
      ids,
      limit,
    ).get();
    return [for (final r in rows) r.m];
  }

  // ----------------------------------------------------------------- settings

  Future<String?> readSetting(String key) async => (await (select(
    settings,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> writeSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingRow(key: key, value: value));

  /// Atomically saves related preferences in one statement.
  ///
  /// Drift's IndexedDB backend flushes standalone writes, but can defer an
  /// explicit transaction's commit until a later write. Keep selections
  /// durable before publishing them, including when a page closes next.
  Future<void> writeSettings(Map<String, String> values) async {
    if (values.isEmpty) return;
    final variables = <Variable<String>>[];
    values.forEach((key, value) {
      variables
        ..add(Variable.withString(key))
        ..add(Variable.withString(value));
    });
    await customInsert(
      'INSERT INTO settings ("key", value) VALUES '
      '${List.filled(values.length, '(?, ?)').join(', ')} '
      'ON CONFLICT ("key") DO UPDATE SET value = excluded.value',
      variables: variables,
      updates: {settings},
    );
  }
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
