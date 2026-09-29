import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openDatabaseConnection() => DatabaseConnection.delayed(
  Future(() async {
    final result = await WasmDatabase.open(
      databaseName: 'athlete_os',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    if (result.chosenImplementation.toString().contains('inMemory') ||
        result.chosenImplementation.toString().contains('unsafe')) {
      throw StateError('Prohlížeč neposkytuje bezpečné trvalé úložiště.');
    }
    return result.resolvedExecutor;
  }),
);
