import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

/// SQLite na hlavním vlákně s trvalým úložištěm v IndexedDB.
///
/// Drift volá `COMMIT` ještě před uvolněním příznaku transakce, takže
/// `WasmDatabase` po commitu nikdy nezavolá `flush()` a zápisy by zůstaly
/// jen v paměti. Proto se po každém commitu flushuje tady.
QueryExecutor openDatabaseConnection() => LazyDatabase(() async {
  final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(
    dbName: 'athlete_os',
    writeAutomatically: false,
  );
  sqlite3.registerVirtualFileSystem(fileSystem, makeDefault: true);
  return WasmDatabase(
    sqlite3: sqlite3,
    path: '/database',
    fileSystem: fileSystem,
  ).interceptWith(_FlushAfterCommit(fileSystem));
});

class _FlushAfterCommit extends QueryInterceptor {
  final IndexedDbFileSystem _fileSystem;
  _FlushAfterCommit(this._fileSystem);

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    await _fileSystem.flush();
  }
}
