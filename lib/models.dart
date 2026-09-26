import 'dart:convert';

import 'package:flutter/services.dart';

late List<Map<String, String>> builtInExercises;

Future<void> loadCatalog() async {
  final raw = await rootBundle.loadString('catalog/exercises.json');
  builtInExercises = (jsonDecode(raw) as List<dynamic>)
      .map((item) => Map<String, String>.from(item as Map))
      .toList();
}

Map<String, dynamic> deepCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

List<Map<String, dynamic>> asMaps(dynamic value) => (value as List<dynamic>)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

String exerciseName(String id, List<Map<String, dynamic>> custom) {
  for (final exercise in [...builtInExercises, ...custom]) {
    if (exercise['id'] == id) return exercise['name'] as String;
  }
  return 'Neznámý cvik';
}

String exerciseMuscle(String id, List<Map<String, dynamic>> custom) {
  for (final exercise in [...builtInExercises, ...custom]) {
    if (exercise['id'] == id) return exercise['muscle'] as String;
  }
  return 'Ostatní';
}
