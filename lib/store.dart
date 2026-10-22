import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'models.dart';

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
    bool reviveDeleted = true,
  }) async {
    final id = data['id'] as String;
    await db.transaction(() async {
      final prior = await raw(id);
      // A late autosave must not bring back a workout that was already
      // finished or discarded.
      if (!reviveDeleted && prior?['deleted'] == 1) return;
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

  Future<String?> meta(String key) async {
    final rows = await db
        .customSelect(
          'SELECT value FROM metadata WHERE key=?',
          variables: [Variable.withString(key)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('value');
  }

  Future<void> setMeta(String key, String value) => db.customStatement(
    'INSERT INTO metadata(key,value) VALUES(?,?) '
    'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  /// Ids of rows waiting for a conflict decision.
  Future<List<String>> conflictIds() async {
    final rows = await db
        .customSelect('SELECT id FROM entities WHERE conflict=1')
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// Removes every local record (used after account deletion or when
  /// handing the device over).
  Future<void> wipeLocal() async {
    await db.transaction(() async {
      await db.customStatement('DELETE FROM entities');
      await db.customStatement('DELETE FROM metadata');
    });
  }

  Future<int> dirtyCount() async {
    final rows = await db
        .customSelect('SELECT COUNT(*) AS count FROM entities WHERE dirty=1')
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

  Future<String> exportBackup() async {
    final rows = await db.customSelect('''
      SELECT kind,payload FROM entities
      WHERE deleted=0 AND kind IN ('plan','session','active','exercise','settings')
      ORDER BY kind,id
    ''').get();
    return jsonEncode({
      'format': 'athlete-os-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'items': [
        for (final row in rows)
          {
            'kind': row.read<String>('kind'),
            'payload': jsonDecode(row.read<String>('payload')),
          },
      ],
    });
  }

  Future<int> importBackup(String source) async {
    if (source.length > 20 * 1024 * 1024) {
      throw const FormatException(
        'Záloha je příliš velká pro vložení ze schránky.',
      );
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['format'] != 'athlete-os-backup' ||
        decoded['version'] != 1 ||
        decoded['items'] is! List) {
      throw const FormatException('Toto není podporovaná záloha Athlete OS.');
    }
    final allowedKinds = {'plan', 'session', 'active', 'exercise', 'settings'};
    final items = <(String, Map<String, dynamic>)>[];
    final ids = <String>{};
    for (final rawItem in decoded['items'] as List) {
      if (rawItem is! Map || rawItem['payload'] is! Map) {
        throw const FormatException('Záloha obsahuje neplatný záznam.');
      }
      final kind = rawItem['kind'];
      final payload = Map<String, dynamic>.from(rawItem['payload'] as Map);
      final id = payload['id'];
      if (kind is! String ||
          !allowedKinds.contains(kind) ||
          id is! String ||
          id.isEmpty ||
          !ids.add(id)) {
        throw const FormatException(
          'Záloha obsahuje neplatná nebo duplicitní ID.',
        );
      }
      try {
        switch (kind) {
          case 'plan':
            Plan.fromJson(payload);
          case 'session':
          case 'active':
            Workout.fromJson(payload);
        }
      } on TypeError {
        throw const FormatException('Záloha obsahuje poškozený záznam.');
      }
      switch (kind) {
        case 'exercise':
          if (payload['name'] is! String || payload['muscle'] is! String) {
            throw const FormatException('Záloha obsahuje neplatný cvik.');
          }
          break;
        case 'settings':
          if (id != 'settings') {
            throw const FormatException('Záloha obsahuje neplatné nastavení.');
          }
          break;
      }
      items.add((kind, payload));
    }
    await db.transaction(() async {
      final existing = await db
          .customSelect(
            "SELECT COUNT(*) AS count FROM entities WHERE kind!='settings'",
          )
          .get();
      if (await accountOwner() != null ||
          existing.first.read<int>('count') > 0) {
        throw StateError(
          'Obnovu lze provést jen do prázdné instalace bez účtu.',
        );
      }
      await db.customStatement("DELETE FROM entities WHERE kind='settings'");
      final now = DateTime.now().toUtc().toIso8601String();
      for (final (kind, payload) in items) {
        await db.customStatement(
          '''
          INSERT INTO entities(id,kind,payload,updated_at,dirty,deleted,conflict,remote_revision)
          VALUES(?,?,?,?,1,0,0,0)
        ''',
          [payload['id'], kind, jsonEncode(payload), now],
        );
      }
    });
    return items.length;
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
