import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

QueryExecutor openDatabaseConnection() => LazyDatabase(() async {
  // Open the original sqflite file in place so existing Android data survives.
  final path = p.join(await getDatabasesPath(), 'athlete_os.db');
  return NativeDatabase(File(path));
});
