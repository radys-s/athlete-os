import 'package:athlete_os/database.dart';
import 'package:athlete_os/store.dart';
import 'package:athlete_os/sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the Supabase table + `push_entity` CAS function.
class FakeRemote implements RemoteApi {
  final Map<String, Map<String, dynamic>> rows = {};
  DateTime clock = DateTime.utc(2026, 9, 1, 12);
  final List<String?> pullSinces = [];
  bool failNextPush = false;

  @override
  String? userId = 'user-1';

  String _stamp() =>
      (clock = clock.add(const Duration(seconds: 1))).toIso8601String();

  @override
  Future<List<Map<String, dynamic>>> pull({String? since}) async {
    pullSinces.add(since);
    final list =
        rows.values
            .where(
              (r) =>
                  since == null ||
                  DateTime.parse(r['updated_at'])
                          .compareTo(DateTime.parse(since)) >=
                      0,
            )
            .map((r) => Map<String, dynamic>.from(r))
            .toList()
          ..sort(
            (a, b) => (a['updated_at'] as String).compareTo(b['updated_at']),
          );
    return list;
  }

  @override
  Future<Map<String, dynamic>> push({
    required String id,
    required String kind,
    required Object? payload,
    required bool deleted,
    required int expectedRevision,
  }) async {
    final existing = rows[id];
    final current = existing == null ? 0 : existing['revision'] as int;
    if (current != expectedRevision) return {'conflict': true};
    // Simulates a lost response: the server applied the write but the client
    // never learns about it.
    final revision = current + 1;
    final stamp = _stamp();
    rows[id] = {
      'id': id,
      'kind': kind,
      'payload': payload,
      'deleted': deleted,
      'revision': revision,
      'updated_at': stamp,
    };
    if (failNextPush) {
      failNextPush = false;
      throw Exception('network lost');
    }
    return {'conflict': false, 'revision': revision, 'updated_at': stamp};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByIds(List<String> ids) async => [
    for (final id in ids)
      if (rows[id] != null) Map<String, dynamic>.from(rows[id]!),
  ];

  /// Another device changes a row.
  void remoteEdit(
    String id,
    Map<String, dynamic> payload, {
    String kind = 'plan',
  }) {
    final current = rows[id]?['revision'] as int? ?? 0;
    rows[id] = {
      'id': id,
      'kind': kind,
      'payload': payload,
      'deleted': false,
      'revision': current + 1,
      'updated_at': _stamp(),
    };
  }
}

void main() {
  late AthleteDatabase database;
  late LocalStore store;
  late FakeRemote remote;
  late CloudSync sync;

  setUp(() async {
    database = AthleteDatabase(NativeDatabase.memory());
    store = LocalStore(database);
    await store.open();
    remote = FakeRemote();
    sync = CloudSync(store, remote);
  });

  tearDown(() => database.close());

  test('local rows are pushed and marked clean', () async {
    await store.put('plan', {'id': 'p1', 'name': 'A'});
    await sync.sync();
    expect(remote.rows['p1']!['revision'], 1);
    final raw = await store.raw('p1');
    expect(raw!['dirty'], 0);
    expect(raw['remote_revision'], 1);
  });

  test(
    'each pull reconciles all rows even after the cursor advances',
    () async {
      remote.remoteEdit('p1', {'id': 'p1', 'name': 'One'});
      await sync.sync();
      expect(remote.pullSinces.last, isNull); // first sync = full pull
      expect(await store.meta('last_pull_at'), isNotNull);

      remote.remoteEdit('p2', {'id': 'p2', 'name': 'Two'});
      await sync.sync();
      expect(remote.pullSinces.last, isNull);
      expect(await store.raw('p2'), isNotNull);
    },
  );

  test('a late commit older than the previous cursor is not lost', () async {
    remote.remoteEdit('new', {'id': 'new', 'name': 'New'});
    await sync.sync();
    remote.remoteEdit('late', {'id': 'late', 'name': 'Late'});
    remote.rows['late']!['updated_at'] = DateTime.utc(
      2026,
      8,
    ).toIso8601String();
    await sync.sync();
    expect((await store.get('late'))!['name'], 'Late');
  });

  test('remote edit of a clean row is imported', () async {
    await store.put('plan', {'id': 'p1', 'name': 'A'});
    await sync.sync();
    remote.remoteEdit('p1', {'id': 'p1', 'name': 'Changed'});
    await sync.sync();
    expect((await store.get('p1'))!['name'], 'Changed');
  });

  test('concurrent edit on both sides becomes a conflict', () async {
    await store.put('plan', {'id': 'p1', 'name': 'A'});
    await sync.sync();
    await store.put('plan', {'id': 'p1', 'name': 'Local'});
    remote.remoteEdit('p1', {'id': 'p1', 'name': 'Remote'});
    await sync.sync();
    expect(await store.conflictCount(), 1);
    final conflicts = await sync.conflicts();
    expect(conflicts.single['payload']['name'], 'Remote');
    expect((await store.get('p1'))!['name'], 'Local');
  });

  test(
    'lost push response is reconciled on the next sync without conflict',
    () async {
      await store.put('plan', {'id': 'p1', 'name': 'A'});
      remote.failNextPush = true;
      await expectLater(sync.sync(), throwsException);
      expect((await store.raw('p1'))!['dirty'], 1);
      await sync.sync();
      expect(await store.conflictCount(), 0);
      final raw = await store.raw('p1');
      expect(raw!['dirty'], 0);
      expect(raw['remote_revision'], 1);
    },
  );

  test('deleted rows are tombstoned in the cloud', () async {
    await store.put('plan', {'id': 'p1', 'name': 'A'});
    await sync.sync();
    await store.remove('p1');
    await sync.sync();
    expect(remote.rows['p1']!['deleted'], true);
    expect(await store.get('p1'), isNull);
  });

  test('signed-out user does not touch the cloud', () async {
    remote.userId = null;
    await store.put('plan', {'id': 'p1', 'name': 'A'});
    await sync.sync();
    expect(remote.rows, isEmpty);
    expect(remote.pullSinces, isEmpty);
  });
}
