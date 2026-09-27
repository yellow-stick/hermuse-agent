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

  Future<void> seedMessages() async {
    await db.saveInstances([instance('a', 'A')]);
    await db.upsertSession(
      const SessionRow(
        instanceId: 'a',
        sessionId: 's1',
        title: 'Trip',
        updatedAt: 1,
        archived: false,
      ),
    );
    await db.upsertMessages([
      const MessageRow(
        instanceId: 'a',
        sessionId: 's1',
        messageId: 'm1',
        author: 'user',
        bodyText: 'Book a flight to Oslo (cheap)',
        createdAt: 1,
      ),
      const MessageRow(
        instanceId: 'a',
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

  test('a version 1 database gains the archive and pin columns', () async {
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
            INSERT INTO instances VALUES ('a', 'A', 'remote', 'https://a',
              'password', NULL, 0, 0);
            INSERT INTO sessions VALUES ('a', 'side', 'Kept', 'main', 5);
            PRAGMA user_version = 1;
          ''');
        },
      ),
    );
    addTearDown(legacy.close);
    final rows = await legacy.loadSideChats('a', 'main');
    expect(rows.single.title, 'Kept');
    expect(rows.single.archived, isFalse);
    expect(rows.single.pinnedAt, isNull);
  });
}
