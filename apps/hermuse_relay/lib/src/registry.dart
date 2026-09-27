// Sqlite-backed registry of upstream Hermes instances.
library;

import 'package:sqlite3/sqlite3.dart';

import 'normalize.dart';

/// A registered upstream Hermes dashboard.
class Upstream {
  final String id;
  final String baseUrl;
  final String? label;
  final DateTime createdAt;

  const Upstream({
    required this.id,
    required this.baseUrl,
    this.label,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'base_url': baseUrl,
    if (label != null) 'label': label,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Persists upstreams in table
/// `upstreams(id TEXT PK, base_url TEXT UNIQUE, label TEXT, created_at)`.
///
/// [db] is owned by the caller when passed in; use [UpstreamRegistry.open]
/// to open a file-backed database instead.
class UpstreamRegistry {
  final Database _db;

  UpstreamRegistry(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS upstreams(
        id TEXT PRIMARY KEY,
        base_url TEXT NOT NULL UNIQUE,
        label TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  factory UpstreamRegistry.open(String path) {
    final db = sqlite3.open(path);
    return UpstreamRegistry(db);
  }

  Upstream? byId(String id) {
    final rows = _db.select(
      'SELECT id, base_url, label, created_at FROM upstreams WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _row(rows.first);
  }

  Upstream? byUrl(String normalizedBaseUrl) {
    final rows = _db.select(
      'SELECT id, base_url, label, created_at FROM upstreams WHERE base_url = ?',
      [normalizedBaseUrl],
    );
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// Inserts a new upstream, or returns the existing row when [normalized]
  /// is already registered (registration is idempotent per base URL).
  Upstream register(String normalized, String? label) {
    final existing = byUrl(normalized);
    if (existing != null) return existing;
    final created = DateTime.now().toUtc();
    final id = _newId();
    _db.execute(
      'INSERT INTO upstreams(id, base_url, label, created_at) '
      'VALUES(?, ?, ?, ?)',
      [id, normalized, label, created.toIso8601String()],
    );
    return Upstream(
      id: id,
      baseUrl: normalized,
      label: label,
      createdAt: created,
    );
  }

  bool remove(String id) {
    _db.execute('DELETE FROM upstreams WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  List<Upstream> list() {
    final rows = _db.select(
      'SELECT id, base_url, label, created_at FROM upstreams '
      'ORDER BY created_at ASC',
    );
    return [for (final row in rows) _row(row)];
  }

  /// Resolves a user-typed URL to a registered upstream, or `null`.
  Upstream? resolve(String rawUrl) {
    final normalized = normalizeUpstreamUrl(rawUrl);
    return byUrl(normalized);
  }

  void close() => _db.close();

  Upstream _row(Row row) => Upstream(
    id: row['id'] as String,
    baseUrl: row['base_url'] as String,
    label: row['label'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  static String _newId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final rand = _counter = (_counter + 1) % 0xffffff;
    return '${now.toRadixString(36)}${rand.toRadixString(36).padLeft(4, '0')}';
  }

  static int _counter = 0;
}
