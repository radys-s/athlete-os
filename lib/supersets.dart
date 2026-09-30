import 'app_controller.dart';
import 'models.dart';

String? supersetId(WorkoutExercise exercise) =>
    exercise.extra['supersetId'] as String?;

List<WorkoutExercise> supersetMembers(
  Workout workout,
  WorkoutExercise exercise,
) {
  final group = supersetId(exercise);
  if (group == null) return [exercise];
  return workout.exercises.where((e) => supersetId(e) == group).toList();
}

/// Rest starts after every exercise in the group has completed this round.
bool shouldRestAfterSet(Workout workout, WorkoutExercise exercise) {
  final completed = exercise.workSets.where((s) => s.done).length;
  return supersetMembers(workout, exercise).every(
    (e) =>
        e.workSets.where((s) => s.done).length >=
        completed.clamp(0, e.workSets.length),
  );
}

extension SupersetControls on AppController {
  Future<void> linkSuperset(
    WorkoutExercise first,
    WorkoutExercise second,
  ) async {
    final workout = active;
    if (locked ||
        workout == null ||
        identical(first, second) ||
        !workout.exercises.contains(first) ||
        !workout.exercises.contains(second)) {
      throw StateError('Vyber dva různé cviky v tomto tréninku.');
    }
    final members = {
      ...supersetMembers(workout, first),
      ...supersetMembers(workout, second),
    };
    final group = supersetId(first) ?? supersetId(second) ?? newId();
    for (final e in members) {
      e.extra['supersetId'] = group;
    }
    touchActive();
    notifyListeners();
    await flushActive();
  }

  Future<void> unlinkSuperset(WorkoutExercise exercise) async {
    final workout = active;
    if (locked || workout == null || !workout.exercises.contains(exercise)) {
      throw StateError('Cvik už není v aktivním tréninku.');
    }
    final others = supersetMembers(
      workout,
      exercise,
    ).where((e) => e != exercise).toList();
    exercise.extra.remove('supersetId');
    if (others.length == 1) others.single.extra.remove('supersetId');
    touchActive();
    notifyListeners();
    await flushActive();
  }
}
