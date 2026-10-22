import 'package:athlete_os/models.dart';
import 'package:athlete_os/progression.dart';
import 'package:athlete_os/csv_export.dart';
import 'package:athlete_os/ui/workout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutSet series({
  double weight = 0,
  int reps = 10,
  int seconds = 0,
  bool done = true,
  String kind = 'work',
}) => WorkoutSet(
  target: 10,
  reps: reps,
  weight: weight,
  seconds: seconds,
  done: done,
  kind: kind,
);
WorkoutExercise exercise(MeasurementType type, List<WorkoutSet> sets) =>
    WorkoutExercise(exerciseId: 'pull_up', measurement: type, sets: sets);
Workout session(List<WorkoutExercise> exercises) => Workout(
  id: 'session',
  planName: 'Workout',
  startedAt: DateTime.utc(2026),
  exercises: exercises,
);

void main() {
  test(
    'legacy records remain weighted regardless of current catalog metadata',
    () {
      builtInExercises = [
        {
          'id': 'pull_up',
          'name': 'Pull-up',
          'muscle': 'Záda',
          'measurement': 'bodyweight',
        },
      ];
      final legacy = WorkoutExercise.fromJson({
        'exerciseId': 'pull_up',
        'sets': [
          {'target': 10, 'reps': 10, 'weight': 70, 'done': true},
        ],
        'future': {'version': 4},
      });
      expect(legacy.measurement, MeasurementType.weighted);
      expect(legacy.bestDoneWeight, 70);
      expect(legacy.toJson()['future'], {'version': 4});
      expect(exerciseMeasurement('pull_up', []), MeasurementType.bodyweight);
      expect(
        PlanExercise.fromJson({'exerciseId': 'pull_up'}).measurement,
        MeasurementType.weighted,
      );
    },
  );
  test(
    'all measurement snapshots round trip with seconds and unknown fields',
    () {
      for (final type in MeasurementType.values) {
        final rule = PlanExercise(
          id: 'rule',
          exerciseId: 'pull_up',
          measurement: type,
          targets: [30],
          extra: {'future': 'rule'},
        );
        final record = exercise(type, [series(seconds: 35)])
          ..rule = rule
          ..planExerciseId = rule.id;
        record.sets.single.extra['future'] = 'set';
        final copy = WorkoutExercise.fromJson(deepCopy(record.toJson()));
        expect(copy.toJson(), record.toJson());
        expect(copy.rule!.id, 'rule');
        expect(copy.measurement, type);
      }
    },
  );
  test('timed completion validates duration only and rejects zero seconds', () {
    final workout = session([
      exercise(MeasurementType.timed, [
        series(reps: 0, seconds: 30, weight: double.nan),
      ]),
    ]);
    expect(workout.validateCompleted(), isNull);
    workout.exercises.single.sets.single.seconds = 0;
    expect(workout.validateCompleted(), contains('sekunda'));
    final body = session([
      exercise(MeasurementType.bodyweight, [series(reps: 0)]),
    ]);
    expect(body.validateCompleted(), isNotNull);
  });
  test(
    'nonweighted measurements never produce weight progression or PR weight',
    () {
      for (final type in [
        MeasurementType.bodyweight,
        MeasurementType.assisted,
        MeasurementType.timed,
      ]) {
        final rule = PlanExercise(
          id: 'rule',
          exerciseId: 'pull_up',
          measurement: type,
          weight: 50,
        );
        final performed = [series(weight: 50, reps: 20).toJson()];
        expect(evaluateProgression(rule.toJson(), performed).completed, false);
        expect(exercise(type, [series(weight: 100)]).bestDoneWeight, 0);
      }
    },
  );
  test(
    'analytics exclude warmups and incomplete sets and rank assistance down',
    () {
      expect(
        bestCompletedMeasurement(
          exercise(MeasurementType.assisted, [
            series(weight: 40),
            series(weight: 25),
            series(weight: 0, done: false),
            series(weight: 5, kind: 'warmup'),
          ]),
        ),
        25,
      );
      expect(
        bestCompletedMeasurement(
          exercise(MeasurementType.bodyweight, [
            series(reps: 8),
            series(reps: 15, weight: 20),
          ]),
        ),
        15,
      );
      expect(
        bestCompletedMeasurement(
          exercise(MeasurementType.timed, [
            series(seconds: 30),
            series(seconds: 55),
          ]),
        ),
        55,
      );
      final workout = session([
        exercise(MeasurementType.weighted, [series(weight: 10, reps: 8)]),
        exercise(MeasurementType.assisted, [series(weight: 40)]),
        exercise(MeasurementType.bodyweight, [series(weight: 20)]),
        exercise(MeasurementType.timed, [series(seconds: 60, weight: 30)]),
      ]);
      expect(completedVolume([workout.toJson()]), 80);
      expect(
        bestCompletedMeasurement(
          exercise(MeasurementType.timed, [series(seconds: 0, done: false)]),
        ),
        isNull,
      );
    },
  );
  test('CSV distinguishes seconds and assistance from external load', () {
    final csv = sessionsToCsv([
      session([
        exercise(MeasurementType.timed, [series(seconds: 45, reps: 0)]),
        exercise(MeasurementType.assisted, [series(weight: 35)]),
      ]),
    ], (_) => 'Cvik');
    expect(csv, contains('measurement;seconds'));
    expect(csv, contains(';timed;45;10;;;'));
    expect(csv, contains(';assisted;;10;10;35;'));
  });
  testWidgets('timed row has seconds only and clears invalid completion', (
    tester,
  ) async {
    final set = series(reps: 0, seconds: 30, done: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => SetRow(
              index: 0,
              set: set,
              measurement: MeasurementType.timed,
              showRir: true,
              onChanged: () {},
              onDone: (v) => update(() => set.done = v),
              onRemove: null,
            ),
          ),
        ),
      ),
    );
    expect(find.text('sekundy'), findsOneWidget);
    expect(find.text('kg'), findsNothing);
    expect(find.text('reps'), findsNothing);
    expect(find.text('RIR'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(set.done, true);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(set.done, false);
    expect(find.text('Alespoň 1 s'), findsOneWidget);
  });
  testWidgets('bodyweight accepts blank optional added load', (tester) async {
    final set = series(done: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SetRow(
            index: 0,
            set: set,
            measurement: MeasurementType.bodyweight,
            showRir: false,
            onChanged: () {},
            onDone: (v) => set.done = v,
            onRemove: null,
          ),
        ),
      ),
    );
    final weight = find.byWidgetPredicate(
      (w) =>
          w is TextField && w.decoration?.labelText == 'Přidané kg (volitelné)',
    );
    await tester.enterText(weight, '');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(set.done, true);
    expect(
      setMeasurementLabel(set, MeasurementType.bodyweight),
      '10 opakování',
    );
  });
}
