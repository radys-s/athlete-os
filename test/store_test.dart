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
}
