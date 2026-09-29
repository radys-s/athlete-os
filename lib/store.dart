import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class LocalStore {
  final AthleteDatabase db;
  LocalStore([AthleteDatabase? database]) : db = database ?? AthleteDatabase();
  final _uuid = const Uuid();

  Future<void> open() async {
    await db.customSelect('SELECT count(*) AS count FROM entities').get();
  }

  String newId() => _uuid.v4();

  Future<void> put(
    String kind,
    Map<String, dynamic> data, {
    bool dirty = true,
  }) async {
    final id = data['id'] as String;
    await db.transaction(() async {
      final prior = await raw(id);
      await db.customStatement(
        '''
        INSERT INTO entities(id,kind,payload,updated_at,dirty,deleted,conflict,remote_revision)
        VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,
          updated_at=excluded.updated_at,dirty=excluded.dirty,deleted=0,
          conflict=entities.conflict,remote_revision=excluded.remote_revision
      ''',
        [
          id,
          kind,
          jsonEncode(data),
          DateTime.now().toUtc().toIso8601String(),
          dirty ? 1 : 0,
          0,
          0,
          prior?['remote_revision'] ?? 0,
        ],
      );
    });
  }

  Future<List<Map<String, dynamic>>> all(String kind) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM entities WHERE kind=? AND deleted=0 ORDER BY updated_at DESC',
          variables: [Variable.withString(kind)],
        )
        .get();
    return rows
        .map(
          (r) => jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
        )
        .toList();
  }

  Future<Map<String, dynamic>?> get(String id) async {
    final row = await raw(id);
    if (row == null || row['deleted'] == 1) return null;
    return jsonDecode(row['payload'] as String) as Map<String, dynamic>;
  }

  Future<void> remove(String id) async {
    await db.customStatement(
      'UPDATE entities SET deleted=1,dirty=1,updated_at=? WHERE id=?',
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> finishWorkout(
    Map<String, dynamic> active,
    Map<String, dynamic> completed,
  ) async {
    await db.transaction(() async {
      final current = await raw(active['id'] as String);
      if (current == null || current['deleted'] == 1) {
        throw StateError('Trénink už byl dokončen.');
      }
      await db.customStatement(
        '''
        INSERT INTO entities(id,kind,payload,updated_at,dirty,deleted,conflict,remote_revision)
        VALUES(?,?,?, ?,1,0,0,0)
      ''',
        [
          completed['id'],
          'session',
          jsonEncode(completed),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      await remove(active['id'] as String);
    });
  }

  Future<List<Map<String, Object?>>> dirtyRows() async =>
      (await db
              .customSelect(
                'SELECT * FROM entities WHERE dirty=1 AND conflict=0',
              )
              .get())
          .map((r) => r.data)
          .toList();

  Future<Map<String, Object?>?> raw(String id) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM entities WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<void> importRemote(
    Map<String, dynamic> row, {
    bool force = false,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO entities(id,kind,payload,updated_at,dirty,deleted,conflict,remote_revision)
      VALUES(?,?,?,?,0,?,0,?)
      ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,
        updated_at=excluded.updated_at,dirty=0,deleted=excluded.deleted,
        conflict=0,remote_revision=excluded.remote_revision
        WHERE entities.dirty=0 OR ?=1
    ''',
      [
        row['id'],
        row['kind'],
        jsonEncode(row['payload']),
        row['updated_at'],
        row['deleted'] == true ? 1 : 0,
        row['revision'],
        force ? 1 : 0,
      ],
    );
  }

  Future<void> markClean(
    String id,
    String timestamp,
    int revision,
    String sentPayload, {
    required int sentDeleted,
  }) async {
    await db.transaction(() async {
      final current = await raw(id);
      if (current == null) return;
      final unchanged =
          current['payload'] == sentPayload &&
          current['deleted'] == sentDeleted;
      await db.customStatement(
        '''
        UPDATE entities SET dirty=?,updated_at=?,remote_revision=? WHERE id=?
      ''',
        [
          unchanged ? 0 : 1,
          unchanged ? timestamp : current['updated_at'],
          revision,
          id,
        ],
      );
    });
  }

  Future<void> markConflict(String id) =>
      db.customStatement('UPDATE entities SET conflict=1 WHERE id=?', [id]);

  Future<int> conflictCount() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS count FROM entities WHERE conflict=1')
        .get();
    return rows.first.read<int>('count');
  }

  Future<String?> accountOwner() async {
    final rows = await db
        .customSelect(
          'SELECT value FROM metadata WHERE key=?',
          variables: [Variable.withString('account_owner')],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<bool> hasWorkoutData() async {
    final rows = await db.customSelect('''
      SELECT COUNT(*) AS count FROM entities
      WHERE deleted=0 AND kind IN ('plan','session','exercise','active')
    ''').get();
    return rows.first.read<int>('count') > 0;
  }

  Future<void> bindAccount(String userId) async {
    await db.transaction(() async {
      final owner = await accountOwner();
      if (owner != null && owner != userId) {
        throw StateError('Tato instalace obsahuje data jiného účtu.');
      }
      await db.customStatement(
        '''
        INSERT INTO metadata(key,value) VALUES('account_owner',?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value
      ''',
        [userId],
      );
    });
  }

  Future<void> resolveConflict(
    String id, {
    required bool keepLocal,
    Map<String, dynamic>? remote,
  }) async {
    if (remote == null) throw ArgumentError('Remote version required');
    if (!keepLocal) return importRemote(remote, force: true);
    await db.customStatement(
      '''
      UPDATE entities SET conflict=0,dirty=1,updated_at=?,remote_revision=? WHERE id=?
    ''',
      [DateTime.now().toUtc().toIso8601String(), remote['revision'], id],
    );
  }
}
