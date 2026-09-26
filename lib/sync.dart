import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const scanApiUrl = String.fromEnvironment('SCAN_API_URL');

class CloudSync {
  final LocalStore store;
  CloudSync(this.store);

  static bool get configured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  SupabaseClient get client => Supabase.instance.client;

  Future<void> sync() async {
    if (!configured || client.auth.currentUser == null) return;
    final userId = client.auth.currentUser!.id;
    await store.bindAccount(userId);
    final remote =
        (await client.from('user_entities').select().eq('user_id', userId))
            .cast<Map<String, dynamic>>();
    final byId = {for (final item in remote) item['id'] as String: item};
    for (final item in remote) {
      final id = item['id'] as String;
      final local = await store.raw(id);
      if (local == null || local['dirty'] == 0) {
        await store.importRemote(item);
      } else {
        if ((local['remote_revision'] as int) != (item['revision'] as int)) {
          await store.markConflict(id);
        }
      }
    }
    for (final local in await store.dirtyRows()) {
      final id = local['id'] as String;
      final server = byId[id];
      if (server != null && local['remote_revision'] == 0) {
        await store.markConflict(id);
        continue;
      }
      final result = await client.rpc(
        'push_entity',
        params: {
          'p_id': id,
          'p_kind': local['kind'],
          'p_payload': jsonDecode(local['payload'] as String),
          'p_deleted': local['deleted'] == 1,
          'p_expected_revision': local['remote_revision'],
        },
      );
      final value = Map<String, dynamic>.from(result as Map);
      if (value['conflict'] == true) {
        await store.markConflict(id);
      } else {
        await store.markClean(
          id,
          value['updated_at'] as String,
          value['revision'] as int,
          local['payload'] as String,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> conflicts() async {
    if (!configured || client.auth.currentUser == null) return [];
    final userId = client.auth.currentUser!.id;
    final remote =
        (await client.from('user_entities').select().eq('user_id', userId))
            .cast<Map<String, dynamic>>();
    final conflicts = <Map<String, dynamic>>[];
    for (final item in remote) {
      final local = await store.raw(item['id'] as String);
      if (local?['conflict'] == 1) conflicts.add(item);
    }
    return conflicts;
  }
}
