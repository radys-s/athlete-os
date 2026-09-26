import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class LocalStore {
  late final Database db;
  final _uuid = const Uuid();

  Future<void> open() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'athlete_os.db'),
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''CREATE TABLE entities (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL,
          updated_at TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1,
          deleted INTEGER NOT NULL DEFAULT 0, conflict INTEGER NOT NULL DEFAULT 0,
          remote_revision INTEGER NOT NULL DEFAULT 0
        )''');
        await database.execute('CREATE INDEX entities_kind ON entities(kind)');
        await database.execute(
          'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
  }

  String newId() => _uuid.v4();

  Future<void> put(
    String kind,
    Map<String, dynamic> data, {
    bool dirty = true,
  }) async {
    final id = data['id'] as String;
    final previous = await raw(id);
    await db.insert('entities', {
      'id': id,
      'kind': kind,
      'payload': jsonEncode(data),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'dirty': dirty ? 1 : 0,
      'deleted': 0,
      'conflict': 0,
      'remote_revision': previous?['remote_revision'] ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> all(String kind) async {
    final rows = await db.query(
      'entities',
      where: 'kind = ? AND deleted = 0',
      whereArgs: [kind],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map(
          (row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        )
        .toList();
  }

  Future<Map<String, dynamic>?> get(String id) async {
    final rows = await db.query(
      'entities',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
  }

  Future<void> remove(String id) async {
    await db.update(
      'entities',
      {
        'deleted': 1,
        'dirty': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> dirtyRows() =>
      db.query('entities', where: 'dirty = 1 AND conflict = 0');

  Future<Map<String, Object?>?> raw(String id) async {
    final rows = await db.query(
      'entities',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> importRemote(Map<String, dynamic> row) async {
    await db.insert('entities', {
      'id': row['id'],
      'kind': row['kind'],
      'payload': jsonEncode(row['payload']),
      'updated_at': row['updated_at'],
      'dirty': 0,
      'deleted': row['deleted'] == true ? 1 : 0,
      'conflict': 0,
      'remote_revision': row['revision'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markClean(
    String id,
    String timestamp,
    int revision,
    String sentPayload,
  ) async {
    final current = await raw(id);
    if (current == null) return;
    await db.update(
      'entities',
      {
        'dirty': current['payload'] == sentPayload ? 0 : 1,
        'updated_at': current['payload'] == sentPayload
            ? timestamp
            : current['updated_at'],
        'remote_revision': revision,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markConflict(String id) async {
    await db.update(
      'entities',
      {'conflict': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> conflictCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM entities WHERE conflict = 1',
    );
    return rows.first['count'] as int;
  }

  Future<String?> accountOwner() async {
    final rows = await db.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['account_owner'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> bindAccount(String userId) async {
    final existing = await accountOwner();
    if (existing != null && existing != userId) {
      throw StateError('Tento telefon je propojen s jiným účtem.');
    }
    await db.insert('metadata', {
      'key': 'account_owner',
      'value': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> resolveConflict(
    String id, {
    required bool keepLocal,
    Map<String, dynamic>? remote,
  }) async {
    if (keepLocal) {
      if (remote == null) throw ArgumentError('Remote version required');
      await db.update(
        'entities',
        {
          'conflict': 0,
          'dirty': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'remote_revision': remote['revision'],
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else if (remote != null) {
      await importRemote(remote);
    }
  }
}
