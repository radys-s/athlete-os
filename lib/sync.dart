import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const scanApiUrl = String.fromEnvironment('SCAN_API_URL');

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

bool _samePayload(String local, Object? remote) =>
    jsonEncode(_canonical(jsonDecode(local))) == jsonEncode(_canonical(remote));

/// Cloud access used by [CloudSync]; a fake implementation drives the tests.
abstract class RemoteApi {
  String? get userId;

  /// Rows changed at or after [since] (all rows when null), oldest first.
  Future<List<Map<String, dynamic>>> pull({String? since});

  Future<Map<String, dynamic>> push({
    required String id,
    required String kind,
    required Object? payload,
    required bool deleted,
    required int expectedRevision,
  });

  Future<List<Map<String, dynamic>>> fetchByIds(List<String> ids);
}

class SupabaseRemote implements RemoteApi {
  SupabaseClient get client => Supabase.instance.client;

  @override
  String? get userId => client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> pull({String? since}) async {
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += 500) {
      var query = client.from('user_entities').select().eq('user_id', userId!);
      if (since != null) query = query.gte('updated_at', since);
      final page =
          (await query.order('updated_at').order('id').range(from, from + 499))
              .cast<Map<String, dynamic>>();
      rows.addAll(page);
      if (page.length < 500) break;
    }
    return rows;
  }

  @override
  Future<Map<String, dynamic>> push({
    required String id,
    required String kind,
    required Object? payload,
    required bool deleted,
    required int expectedRevision,
  }) async {
    final result = await client.rpc(
      'push_entity',
      params: {
        'p_id': id,
        'p_kind': kind,
        'p_payload': payload,
        'p_deleted': deleted,
        'p_expected_revision': expectedRevision,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    return (await client
            .from('user_entities')
            .select()
            .eq('user_id', userId!)
            .inFilter('id', ids))
        .cast<Map<String, dynamic>>();
  }
}

class CloudSync {
  final LocalStore store;
  final RemoteApi? _remote;
  CloudSync(this.store, [this._remote]);

  static bool get configured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  RemoteApi get remote => _remote ?? SupabaseRemote();

  /// Pulls overlap the previous cursor a bit so a row committed late with an
  /// older `updated_at` is not missed.
  static const cursorOverlap = Duration(minutes: 2);

  Future<void> sync() async {
    if (_remote == null && !configured) return;
    final api = remote;
    final userId = api.userId;
    if (userId == null) return;
    await store.bindAccount(userId);

    final cursor = await store.meta('last_pull_at');
    final since = cursor == null
        ? null
        : DateTime.parse(cursor)
              .subtract(cursorOverlap)
              .toUtc()
              .toIso8601String();
    final pulled = await api.pull(since: since);
    final byId = {for (final item in pulled) item['id'] as String: item};
    String? newest;
    for (final item in pulled) {
      final id = item['id'] as String;
      final stamp = item['updated_at'] as String;
      if (newest == null ||
          DateTime.parse(stamp).isAfter(DateTime.parse(newest))) {
        newest = stamp;
      }
      final local = await store.raw(id);
      if (local == null || local['dirty'] == 0) {
        await store.importRemote(item);
      } else if ((local['remote_revision'] as int) !=
          (item['revision'] as int)) {
        if (_samePayload(local['payload'] as String, item['payload']) &&
            (local['deleted'] == 1) == (item['deleted'] == true)) {
          await store.markClean(
            id,
            stamp,
            item['revision'] as int,
            local['payload'] as String,
            sentDeleted: local['deleted'] as int,
          );
        } else {
          await store.markConflict(id);
        }
      }
    }

    for (final local in await store.dirtyRows()) {
      final id = local['id'] as String;
      final server = byId[id];
      if (server != null && local['remote_revision'] == 0) {
        if (_samePayload(local['payload'] as String, server['payload']) &&
            (local['deleted'] == 1) == (server['deleted'] == true)) {
          await store.markClean(
            id,
            server['updated_at'] as String,
            server['revision'] as int,
            local['payload'] as String,
            sentDeleted: local['deleted'] as int,
          );
        } else {
          await store.markConflict(id);
        }
        continue;
      }
      final value = await api.push(
        id: id,
        kind: local['kind'] as String,
        payload: jsonDecode(local['payload'] as String),
        deleted: local['deleted'] == 1,
        expectedRevision: local['remote_revision'] as int,
      );
      if (value['conflict'] == true) {
        await store.markConflict(id);
      } else {
        await store.markClean(
          id,
          value['updated_at'] as String,
          value['revision'] as int,
          local['payload'] as String,
          sentDeleted: local['deleted'] as int,
        );
      }
    }
    // The cursor moves only after every pulled row has been processed.
    if (newest != null) await store.setMeta('last_pull_at', newest);
  }

  Future<List<Map<String, dynamic>>> conflicts() async {
    if (_remote == null && !configured) return [];
    final api = remote;
    if (api.userId == null) return [];
    return api.fetchByIds(await store.conflictIds());
  }
}
