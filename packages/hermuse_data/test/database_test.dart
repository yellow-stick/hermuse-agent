import 'package:drift/native.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:test/test.dart';

void main() {
  late HermuseDatabase db;
  setUp(() => db = openMemoryDatabase());
  tearDown(() => db.close());

  HermesInstance instance(String id, String label) => HermesInstance(
    id: id,
    label: label,
    kind: InstanceKind.remote,
    baseUrl: Uri.parse('https://$id.example'),
    auth: AuthMethod.password,
  );

  test(
    'instance list keeps order, primary flag and drops removed rows',
    () async {
      await db.saveInstances([
        instance('a', 'A'),
        instance('b', 'B'),
      ], primaryId: 'b');
      await db.saveInstances([
        instance('c', 'C'),
        instance('b', 'B'),
      ], primaryId: 'b');
      expect((await db.loadInstances()).map((i) => i.id), ['c', 'b']);
      expect(await db.loadPrimaryInstanceId(), 'b');
    },
  );

  test('side chats follow the main chat to its new session', () async {
    await db.saveInstances([instance('a', 'A')]);
    for (final (id, profile) in [('s1', 'default'), ('s2', 'aya')]) {
      await db.upsertSession(
        SessionRow(
          instanceId: 'a',
          profile: profile,
          sessionId: id,
          title: id,
          parentId: 'old',
          updatedAt: 1,
          archived: false,
        ),
      );
    }
    await db.reparentSideChats('a', from: 'old', to: 'bot');
    expect((await db.loadSideChats('a', 'bot')).single.sessionId, 's1');
    expect(await db.loadSideChats('a', 'old'), isEmpty);
    expect(
      (await db.loadSideChats('a', 'old', profile: 'aya')).single.sessionId,
      's2',
    );
  });

  Future<void> seedMessages() async {
    await db.saveInstances([instance('a', 'A')]);
    await db.upsertSession(
      const SessionRow(
        instanceId: 'a',
        profile: 'default',
        sessionId: 's1',
        title: 'Trip',
        updatedAt: 1,
        archived: false,
      ),
    );
    await db.upsertMessages([
      const MessageRow(
        instanceId: 'a',
        profile: 'default',
        sessionId: 's1',
        messageId: 'm1',
        author: 'user',
        bodyText: 'Book a flight to Oslo (cheap)',
        createdAt: 1,
      ),
      const MessageRow(
        instanceId: 'a',
        profile: 'default',
        sessionId: 's1',
        messageId: 'm2',
        author: 'agent',
        bodyText: 'Found three options for Lisbon',
        createdAt: 2,
      ),
    ]);
  }

  Future<List<CachedMessage>> find(String text) =>
      db.search(text, instanceId: 'a', sessionIds: ['s1']);

  test('full-text search matches prefixes and survives FTS syntax', () async {
    await seedMessages();
    expect((await find('osl')).map((m) => m.messageId), ['m1']);
    expect(await find('"(cheap'), hasLength(1));
    expect(await find('   '), isEmpty);
    expect(
      await db.search('osl', instanceId: 'a', sessionIds: ['other']),
      isEmpty,
      reason: 'only the listed sessions are searched',
    );
  });

  test('updating or deleting a message keeps the FTS index in sync', () async {
    await seedMessages();
    await db.upsertMessages([
      const MessageRow(
        instanceId: 'a',
        profile: 'default',
        sessionId: 's1',
        messageId: 'm1',
        author: 'user',
        bodyText: 'Book a train to Bergen',
        createdAt: 1,
      ),
    ]);
    expect(await find('oslo'), isEmpty);
    expect((await find('bergen')).single.messageId, 'm1');

    await db.deleteSession('a', 's1');
    expect(await find('bergen'), isEmpty, reason: 'cascade + trigger');
  });

  test('side chats: pinned first, then recent; archiving unpins', () async {
    await db.saveInstances([instance('a', 'A')]);
    SessionRow side(String id, int at) => SessionRow(
      instanceId: 'a',
      profile: 'default',
      sessionId: id,
      title: id,
      parentId: 'main',
      updatedAt: at,
      archived: false,
    );
    for (final row in [side('old', 1), side('new', 3), side('mid', 2)]) {
      await db.upsertSession(row);
    }
    await db.upsertSession(
      const SessionRow(
        instanceId: 'a',
        profile: 'default',
        sessionId: 'main',
        title: 'Main',
        updatedAt: 9,
        archived: false,
      ),
    );
    Future<List<String>> ids({bool archived = false}) async => [
      for (final r in await db.loadSideChats('a', 'main', archived: archived))
        r.sessionId,
    ];
    expect(await ids(), ['new', 'mid', 'old'], reason: 'main is not a side');

    await db.setSessionPinned('a', 'old', 10);
    await db.setSessionPinned('a', 'mid', 20);
    expect(await ids(), ['mid', 'old', 'new']);

    await db.setSessionArchived('a', 'mid', archived: true);
    expect(await ids(), ['old', 'new']);
    expect(await ids(archived: true), ['mid']);
    await db.setSessionArchived('a', 'mid', archived: false);
    expect(await ids(), ['old', 'new', 'mid'], reason: 'restored unpinned');
  });

  for (final version in [1, 3]) {
    test(
      'version $version preserves default and named-profile history',
      () async {
        final legacy = HermuseDatabase(
          NativeDatabase.memory(
            setup: (raw) {
              raw.execute('''
            CREATE TABLE instances (id TEXT NOT NULL PRIMARY KEY,
              label TEXT NOT NULL UNIQUE COLLATE NOCASE, kind TEXT NOT NULL,
              base_url TEXT NOT NULL, auth TEXT NOT NULL, profile TEXT,
              is_primary BOOLEAN NOT NULL DEFAULT FALSE,
              position INTEGER NOT NULL);
            CREATE TABLE sessions (instance_id TEXT NOT NULL
                REFERENCES instances (id) ON DELETE CASCADE,
              session_id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
              parent_id TEXT, updated_at INTEGER NOT NULL,
              PRIMARY KEY (instance_id, session_id));
            CREATE TABLE messages (
              instance_id TEXT NOT NULL, session_id TEXT NOT NULL,
              message_id TEXT NOT NULL, author TEXT NOT NULL,
              body_text TEXT NOT NULL, created_at INTEGER NOT NULL,
              PRIMARY KEY (instance_id, session_id, message_id),
              FOREIGN KEY (instance_id, session_id)
                REFERENCES sessions (instance_id, session_id) ON DELETE CASCADE);
            CREATE VIRTUAL TABLE messages_fts USING fts5(
              body_text, content='messages', content_rowid='rowid');
            CREATE TRIGGER messages_fts_insert AFTER INSERT ON messages BEGIN
              INSERT INTO messages_fts (rowid, body_text)
                VALUES (new.rowid, new.body_text);
            END;
            CREATE TRIGGER messages_fts_delete AFTER DELETE ON messages BEGIN
              INSERT INTO messages_fts (messages_fts, rowid, body_text)
                VALUES ('delete', old.rowid, old.body_text);
            END;
            CREATE TRIGGER messages_fts_update AFTER UPDATE ON messages BEGIN
              INSERT INTO messages_fts (messages_fts, rowid, body_text)
                VALUES ('delete', old.rowid, old.body_text);
              INSERT INTO messages_fts (rowid, body_text)
                VALUES (new.rowid, new.body_text);
            END;
            CREATE TABLE settings ("key" TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO instances VALUES ('a', 'A', 'remote', 'https://a',
              'password', NULL, 0, 0);
            INSERT INTO sessions VALUES ('a', 'side', 'Kept', 'main', 5);
            INSERT INTO instances VALUES ('legacy', 'Legacy', 'remote',
              'https://legacy', 'password', 'aya', 0, 1);
            INSERT INTO sessions VALUES ('legacy', 'side', 'Named', 'main', 6);
            INSERT INTO settings VALUES ('main_session:legacy', 'side');
            INSERT INTO settings VALUES ('open_thread:legacy', 'side');
            INSERT INTO messages VALUES (
              'a', 'side', 'row-1', 'user', 'Original conversation', 1);
            PRAGMA user_version = 1;
          ''');
              if (version == 3) {
                raw.execute('''
              ALTER TABLE sessions ADD COLUMN archived BOOLEAN NOT NULL DEFAULT FALSE;
              ALTER TABLE sessions ADD COLUMN pinned_at INTEGER;
              CREATE TABLE activity (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                instance_id TEXT NOT NULL REFERENCES instances (id) ON DELETE CASCADE,
                session_id TEXT NOT NULL, tool TEXT NOT NULL,
                summary TEXT NOT NULL DEFAULT '', at INTEGER NOT NULL);
              CREATE INDEX activity_by_time ON activity (instance_id, at);
              INSERT INTO activity (instance_id, session_id, tool, at)
                VALUES ('legacy', 'side', 'read_file', 1);
              PRAGMA user_version = 3;
            ''');
              }
            },
          ),
        );
        addTearDown(legacy.close);
        final rows = await legacy.loadSideChats('a', 'main');
        expect(rows.single.title, 'Kept');
        expect(rows.single.archived, isFalse);
        expect(rows.single.pinnedAt, isNull);
        expect(rows.single.profile, 'default');
        expect(
          (await legacy.search(
            'Original',
            instanceId: 'a',
            sessionIds: ['side'],
          )).single.bodyText,
          'Original conversation',
        );
        expect(
          await legacy.loadMessages('a', 'side', profile: 'noah'),
          isEmpty,
        );
        expect(
          (await legacy.loadSideChats(
            'legacy',
            'main',
            profile: 'aya',
          )).single.title,
          'Named',
        );
        expect(await legacy.loadSideChats('legacy', 'main'), isEmpty);
        expect(
          await legacy.readSetting('main_session:legacy:profile:aya'),
          'side',
        );
        expect(await legacy.readSetting('main_session:legacy'), isNull);
        // Version 5: the device-local Activity table is gone.
        expect(
          await legacy
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name LIKE 'activity%'",
              )
              .get(),
          isEmpty,
        );
      },
    );
  }

  group('Profile cache isolation', () {
    test('identical sessions and message ids never collide or cascade across profiles', () async {
      await db.saveInstances([instance('a', 'A')]);
      for (final profile in ['default', 'aya']) {
        await db.upsertSession(
          SessionRow(
            instanceId: 'a',
            profile: profile,
            sessionId: 'same',
            title: '$profile side',
            parentId: 'main',
            updatedAt: 1,
            archived: false,
          ),
        );
        await db.cacheTranscript('a', 'same', [
          MessageRow(
            instanceId: 'a',
            profile: profile,
            sessionId: 'same',
            messageId: 'row-1',
            author: 'user',
            bodyText: '$profile private',
            createdAt: 1,
          ),
        ], profile: profile);
      }
      await db.renameSession('a', 'same', 'Renamed', profile: 'aya');
      await db.setSessionPinned('a', 'same', 10, profile: 'aya');
      await db.setSessionArchived('a', 'same', archived: true, profile: 'aya');
      expect(
        (await db.loadSideChats('a', 'main')).single.title,
        'default side',
      );
      expect(
        (await db.loadSideChats(
          'a',
          'main',
          profile: 'aya',
          archived: true,
        )).single.title,
        'Renamed',
      );
      expect(
        (await db.search(
          'private',
          instanceId: 'a',
          sessionIds: ['same'],
        )).single.bodyText,
        'default private',
      );
      expect(
        (await db.search(
          'private',
          instanceId: 'a',
          sessionIds: ['same'],
          profile: 'aya',
        )).single.bodyText,
        'aya private',
      );
      await db.deleteSession('a', 'same', profile: 'aya');
      expect(await db.loadMessages('a', 'same', profile: 'aya'), isEmpty);
      expect(
        (await db.loadMessages('a', 'same')).single.bodyText,
        'default private',
      );
      expect(
        await db.search(
          'private',
          instanceId: 'a',
          sessionIds: ['same'],
          profile: 'aya',
        ),
        isEmpty,
      );
    });
  });
}
