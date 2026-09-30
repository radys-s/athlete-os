import 'package:athlete_os/app_controller.dart';
import 'package:athlete_os/database.dart';
import 'package:athlete_os/models.dart';
import 'package:athlete_os/store.dart';
import 'package:athlete_os/supersets.dart';
import 'package:athlete_os/ui/superset_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('superset dialog groups and unlinks an active workout', (
    tester,
  ) async {
    builtInExercises = [];
    final db = AthleteDatabase(NativeDatabase.memory());
    final app = AppController(LocalStore(db));
    await app.initialize();
    try {
      await app.startQuickWorkout();
      await app.addExerciseToActive('a');
      await app.addExerciseToActive('b');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, _) => SupersetEditor(app),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Spojit cviky do supersetu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spojit'));
      await tester.pumpAndSettle();
      expect(
        supersetMembers(app.active!, app.active!.exercises.first),
        hasLength(2),
      );
      expect(find.byTooltip('Rozpojit superset'), findsOneWidget);
      await tester.tap(find.byTooltip('Rozpojit superset'));
      await tester.pumpAndSettle();
      expect(app.active!.exercises.every((e) => supersetId(e) == null), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      app.dispose();
      await db.close();
    }
  });
  test('exhausted shorter exercise does not suppress later rest rounds', () {
    WorkoutExercise make(int count) => WorkoutExercise(
      exerciseId: '$count',
      extra: {'supersetId': 'g'},
      sets: List.generate(
        count,
        (_) => WorkoutSet(target: 8, reps: 8, weight: 40, done: true),
      ),
    );
    final a = make(3), b = make(1);
    final workout = Workout(
      id: 'w',
      planName: 'Superset',
      startedAt: DateTime.utc(2026),
      exercises: [a, b],
    );
    expect(shouldRestAfterSet(workout, a), true);
    b.sets.first.done = false;
    expect(shouldRestAfterSet(workout, a), false);
  });
  test(
    'superset grouping survives save/history/repeat and rests after a round',
    () async {
      builtInExercises = [];
      final db = AthleteDatabase(NativeDatabase.memory());
      final app = AppController(LocalStore(db));
      await app.initialize();
      try {
        await app.startQuickWorkout();
        await app.addExerciseToActive('a');
        await app.addExerciseToActive('b');
        final a = app.active!.exercises[0], b = app.active!.exercises[1];
        await app.linkSuperset(a, b);
        a.sets.first.done = true;
        expect(shouldRestAfterSet(app.active!, a), false);
        b.sets.first.done = true;
        expect(shouldRestAfterSet(app.active!, b), true);
        await app.finish();
        expect(
          supersetId(app.sessions.single.exercises[0]),
          supersetId(app.sessions.single.exercises[1]),
        );
        await app.startFromSession(app.sessions.single);
        final repeated = app.active!.exercises;
        expect(supersetMembers(app.active!, repeated[0]), hasLength(2));
        await app.unlinkSuperset(repeated[0]);
        expect(repeated.every((e) => supersetId(e) == null), true);
      } finally {
        app.dispose();
        await db.close();
      }
    },
  );
}
