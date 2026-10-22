import 'models.dart';

String _cell(Object? value) {
  final text = '${value ?? ''}';
  return text.contains(RegExp('[",\n\r;]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

/// Local time as "2026-10-22 18:05", which Czech Excel reads as a date.
String _localStamp(DateTime value) {
  final l = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// Jedna řádka na sérii, nejnovější trénink první. Začíná znakem BOM, aby
/// Excel otevřel UTF-8 s diakritikou správně.
String sessionsToCsv(
  List<Workout> sessions,
  String Function(String exerciseId) nameOf,
) {
  final rows = <List<Object?>>[
    [
      'date',
      'workout',
      'exercise',
      'set',
      'kind',
      'measurement',
      'seconds',
      'target',
      'reps',
      'weight_kg',
      'rir',
      'done',
      'workout_note',
    ],
  ];
  for (final session in sessions) {
    for (final exercise in session.exercises) {
      for (var i = 0; i < exercise.sets.length; i++) {
        final set = exercise.sets[i];
        rows.add([
          _localStamp(session.finishedAt ?? session.startedAt),
          session.planName,
          nameOf(exercise.exerciseId),
          i + 1,
          set.kind,
          exercise.measurement.name,
          exercise.measurement == MeasurementType.timed ? set.seconds : null,
          set.target,
          exercise.measurement == MeasurementType.timed ? null : set.reps,
          exercise.measurement == MeasurementType.timed
              ? null
              : formatNumber(set.weight),
          set.rir,
          set.done ? 1 : 0,
          session.note,
        ]);
      }
    }
  }
  return '﻿${rows.map((row) => row.map(_cell).join(';')).join('\r\n')}';
}
