import 'package:athlete_os/database.dart';
import 'package:athlete_os/store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AthleteDatabase database;
  late LocalStore store;

  setUp(() async {
    database = AthleteDatabase(NativeDatabase.memory());
    store = LocalStore(database);
    await store.open();
  });

  tearDown(() async => database.close());

  test('finishing a workout atomically prevents duplicate history', () async {
    final active = {'id': 'active-1', 'planId': 'plan-1', 'exercises': []};
    final completed = {'id': 'session-1', 'planId': 'plan-1', 'exercises': []};
    await store.put('active', active);
    await store.finishWorkout(active, completed);
    expect((await store.all('active')), isEmpty);
    expect((await store.all('session')).length, 1);
    await expectLater(store.finishWorkout(active, {
      ...completed, 'id': 'session-2',
    }), throwsStateError);
    expect((await store.all('session')).length, 1);
  });

  test('remote import does not overwrite a local edit made while pulling', () async {
    await store.put('plan', {'id': 'plan-1', 'name': 'Local'});
    await store.importRemote({
      'id': 'plan-1', 'kind': 'plan', 'payload': {'id': 'plan-1', 'name': 'Remote'},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted': false, 'revision': 2,
    });
    expect((await store.get('plan-1'))?['name'], 'Local');
  });

  test('acknowledged deletion does not clean a newer local edit', () async {
    await store.put('plan', {'id': 'plan-1', 'name': 'Old'});
    await store.remove('plan-1');
    await store.put('plan', {'id': 'plan-1', 'name': 'New'});
    await store.markClean('plan-1', '2026-09-27T00:00:00Z', 1,
        '{"id":"plan-1","name":"Old"}', sentDeleted: 1);
    expect((await store.raw('plan-1'))?['dirty'], 1);
    expect((await store.get('plan-1'))?['name'], 'New');
  });

  test('a database created by the old sqflite build opens with its data', () async {
    final old = AthleteDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''CREATE TABLE entities (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL,
            updated_at TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1,
            deleted INTEGER NOT NULL DEFAULT 0, conflict INTEGER NOT NULL DEFAULT 0,
            remote_revision INTEGER NOT NULL DEFAULT 0)''');
          raw.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          raw.execute(
            "INSERT INTO entities(id,kind,payload,updated_at) VALUES('p1','plan','{\"id\":\"p1\",\"name\":\"Old\"}','2026-09-01T00:00:00Z')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    final oldStore = LocalStore(old);
    await oldStore.open();
    expect((await oldStore.get('p1'))?['name'], 'Old');
    final indexes = await old
        .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
        .get();
    expect(indexes.map((r) => r.read<String>('name')), contains('entities_kind'));
    await old.close();
  });

  test('editing a conflicted record keeps the conflict flag', () async {
    await store.put('plan', {'id': 'plan-1', 'name': 'A'});
    await store.markConflict('plan-1');
    await store.put('plan', {'id': 'plan-1', 'name': 'B'});
    expect((await store.raw('plan-1'))?['conflict'], 1);
  });
}
