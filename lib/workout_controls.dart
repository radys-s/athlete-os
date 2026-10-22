import 'app_controller.dart';
import 'models.dart';

/// Structural edits apply to this workout only, never to its source plan.
extension WorkoutControls on AppController {
  Workout _editableWorkout(WorkoutExercise exercise) {
    if (locked) throw StateError('Nejdřív odemkni aplikaci.');
    final workout = active;
    if (workout == null || !workout.exercises.contains(exercise)) {
      throw StateError('Cvik už není v aktivním tréninku.');
    }
    return workout;
  }

  Future<void> replaceActiveExercise(
    WorkoutExercise exercise,
    String exerciseId,
  ) async {
    final workout = _editableWorkout(exercise);
    if (exercise.sets.any((set) => set.done)) {
      throw StateError(
        'Cvik má dokončené série. Alternativu přidej jako nový cvik.',
      );
    }
    if (workout.exercises.any((item) => item.exerciseId == exerciseId)) {
      throw StateError('Cvik už je v tomto tréninku.');
    }
    final measurement = exerciseMeasurement(exerciseId, customExercises);
    final lastWork = sessions
        .expand((session) => session.exercises)
        .where(
          (item) =>
              item.exerciseId == exerciseId && item.measurement == measurement,
        )
        .expand((item) => item.workSets.where((set) => set.done))
        .firstOrNull;
    final replacement = WorkoutExercise(
      exerciseId: exerciseId,
      measurement: measurement,
      sets: List.generate(
        3,
        (_) => WorkoutSet(
          target:
              lastWork?.target ??
              (measurement == MeasurementType.timed ? 30 : 10),
          reps: measurement == MeasurementType.timed
              ? 0
              : lastWork?.target ?? 10,
          seconds: measurement == MeasurementType.timed
              ? lastWork?.seconds ?? 30
              : 0,
          weight: lastWork?.weight ?? 0,
        ),
      ),
      // A null rule alone permits legacy matching by exercise ID on finish.
      extra: {
        'detachedFromPlan': true,
        if (exercise.extra['supersetId'] != null)
          'supersetId': exercise.extra['supersetId'],
      },
    );
    workout.exercises[workout.exercises.indexOf(exercise)] = replacement;
    touchActive();
    notifyListeners();
    await flushActive();
  }

  Future<void> removeActiveExercise(
    WorkoutExercise exercise, {
    bool discardCompletedSets = false,
  }) async {
    final workout = _editableWorkout(exercise);
    if (!discardCompletedSets && exercise.sets.any((set) => set.done)) {
      throw StateError('Odebrání dokončených sérií vyžaduje potvrzení.');
    }
    workout.exercises.remove(exercise);
    dropLoneSupersets([for (final e in workout.exercises) e.extra]);
    touchActive();
    notifyListeners();
    await flushActive();
  }

  Future<void> moveActiveExercise(WorkoutExercise exercise, int delta) async {
    final workout = _editableWorkout(exercise);
    if (delta != -1 && delta != 1) {
      throw ArgumentError.value(delta, 'delta', 'Použij -1 nebo 1.');
    }
    final index = workout.exercises.indexOf(exercise);
    final destination = index + delta;
    if (destination < 0 || destination >= workout.exercises.length) return;
    workout.exercises.removeAt(index);
    workout.exercises.insert(destination, exercise);
    touchActive();
    notifyListeners();
    await flushActive();
  }
}
