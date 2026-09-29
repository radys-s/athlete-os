import 'models.dart';

String _cell(Object? value) {
  final text = '${value ?? ''}';
  return text.contains(RegExp('[",\n\r;]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

/// Jedna řádka na sérii, nejnovější trénink první.
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
          (session.finishedAt ?? session.startedAt).toIso8601String(),
          session.planName,
          nameOf(exercise.exerciseId),
          i + 1,
          set.kind,
          set.target,
          set.reps,
          set.weight,
          set.rir,
          set.done ? 1 : 0,
          session.note,
        ]);
      }
    }
  }
  return rows.map((row) => row.map(_cell).join(',')).join('\r\n');
}
