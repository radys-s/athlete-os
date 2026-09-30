import 'package:athlete_os/app_controller.dart';
import 'package:athlete_os/database.dart';
import 'package:athlete_os/models.dart';
import 'package:athlete_os/store.dart';
import 'package:athlete_os/ui/workout_page.dart';
import 'package:athlete_os/workout_controls.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutExercise exercise(String id, {bool done = false}) => WorkoutExercise(
  exerciseId: id,
  sets: [WorkoutSet(target: 10, reps: 10, weight: 20, done: done)],
);

Workout workout(List<WorkoutExercise> exercises) => Workout(
  id: 'active',
  planName: 'Trénink',
  startedAt: DateTime.utc(2026),
  exercises: exercises,
);

class WidgetController extends AppController {
  WidgetController(super.store);
  Map<String, dynamic>? saved;
  @override
  void touchActive() {}
  @override
  Future<void> flushActive() async {
    saved = active?.toJson();
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AthleteDatabase db;
  late LocalStore store;
  late AppController app;

  setUp(() {
    builtInExercises = [
      {'id': 'a', 'name': 'První cvik', 'muscle': 'Hrudník'},
      {'id': 'b', 'name': 'Druhý cvik', 'muscle': 'Záda'},
      {'id': 'c', 'name': 'Alternativa', 'muscle': 'Nohy'},
    ];
    db = AthleteDatabase(NativeDatabase.memory());
    store = LocalStore(db);
    app = AppController(store);
  });
  tearDown(() async {
    app.dispose();
    await db.close();
  });

  test(
    'replacement uses new history, detaches plan and preserves original rule',
    () async {
      final rule = PlanExercise(id: 'item', exerciseId: 'a', weight: 80);
      final original = exercise('a')
        ..planExerciseId = rule.id
        ..rule = rule.copy();
      app.active = workout([original]);
      app.sessions = [
        workout([
          WorkoutExercise(
            exerciseId: 'c',
            sets: [WorkoutSet(target: 12, reps: 11, weight: 35, done: true)],
          ),
        ]),
      ];
      await app.replaceActiveExercise(original, 'c');
      final saved = Workout.fromJson((await store.get('active'))!);
      final replacement = saved.exercises.single;
      expect(replacement.exerciseId, 'c');
      expect(replacement.planExerciseId, isNull);
      expect(replacement.rule, isNull);
      expect(replacement.extra['detachedFromPlan'], true);
      expect(replacement.sets, hasLength(3));
      expect(
        replacement.sets.every(
          (s) => !s.done && s.target == 12 && s.reps == 12 && s.weight == 35,
        ),
        true,
      );
      expect(original.rule!.toJson(), rule.toJson());
      expect(original.exerciseId, 'a');
      expect(original.planExerciseId, 'item');
    },
  );

  test(
    'replacement refuses completed warmup and duplicate without mutation',
    () async {
      final original = exercise('a', done: true);
      original.sets.single.kind = 'warmup';
      app.active = workout([original, exercise('b')]);
      await expectLater(
        app.replaceActiveExercise(original, 'c'),
        throwsStateError,
      );
      original.sets.single.done = false;
      await expectLater(
        app.replaceActiveExercise(original, 'b'),
        throwsStateError,
      );
      expect(app.active!.exercises.first, same(original));
      expect(await store.get('active'), isNull);
    },
  );

  test('reorder and confirmed removal persist and notify listeners', () async {
    final first = exercise('a', done: true);
    final second = exercise('b');
    app.active = workout([first, second]);
    var notifications = 0;
    app.addListener(() => notifications++);
    await app.moveActiveExercise(second, -1);
    expect(
      Workout.fromJson((await store.get('active'))!).exercises
          .map((e) => e.exerciseId),
      ['b', 'a'],
    );
    await expectLater(app.removeActiveExercise(first), throwsStateError);
    expect(app.active!.exercises, hasLength(2));
    await app.removeActiveExercise(first, discardCompletedSets: true);
    expect(
      Workout.fromJson((await store.get('active'))!)
          .exercises
          .single
          .exerciseId,
      'b',
    );
    expect(notifications, greaterThanOrEqualTo(2));
  });

  test(
    'detached alternative never progresses matching plan entry, even on repeat',
    () async {
      final plan = Plan(
        id: 'plan',
        name: 'Plán',
        exercises: [
          PlanExercise(id: 'item-a', exerciseId: 'a', weight: 50),
          PlanExercise(id: 'item-c', exerciseId: 'c', weight: 30),
        ],
      );
      await app.savePlan(plan);
      await app.startPlan(plan);
      final original = app.active!.exercises.first;
      await app.removeActiveExercise(app.active!.exercises.last);
      await app.replaceActiveExercise(original, 'c');
      for (final set in app.active!.exercises.single.sets) {
        set.done = true;
      }
      expect(await app.finish(), isEmpty);
      final session = app.sessions.first;
      await app.startFromSession(session);
      expect(app.active!.exercises.single.extra['detachedFromPlan'], true);
      for (final set in app.active!.exercises.single.sets) {
        set.done = true;
      }
      expect(await app.finish(), isEmpty);
      final savedPlan = Plan.fromJson((await store.get('plan'))!);
      expect(savedPlan.toJson(), plan.toJson());
    },
  );

  Future<WidgetController> mount(
    WidgetTester tester,
    List<WorkoutExercise> entries,
  ) async {
    app.dispose();
    final controller = WidgetController(store)..active = workout(entries);
    app = controller;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: WorkoutPage(app))),
    );
    return controller;
  }

  Future<void> menu(WidgetTester tester, String id, String action) async {
    final control = find.byKey(ValueKey('controls-$id'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('completed replacement explains adding alternative', (
    tester,
  ) async {
    await mount(tester, [exercise('a', done: true)]);
    await menu(tester, 'a', 'Nahradit cvik');
    expect(
      find.text('Cvik má dokončené série. Alternativu přidej jako nový cvik.'),
      findsOneWidget,
    );
    expect(app.active!.exercises.single.exerciseId, 'a');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'removal confirmation can cancel and explicitly discard logged sets',
    (tester) async {
      final controller = await mount(tester, [exercise('a', done: true)]);
      await menu(tester, 'a', 'Odebrat cvik');
      expect(find.text('Odebrat cvik i se sériemi?'), findsOneWidget);
      await tester.tap(find.text('Zpět'));
      await tester.pumpAndSettle();
      expect(app.active!.exercises, hasLength(1));
      await menu(tester, 'a', 'Odebrat cvik');
      await tester.tap(find.widgetWithText(FilledButton, 'Odebrat cvik'));
      await tester.pumpAndSettle();
      expect(app.active!.exercises, isEmpty);
      expect(controller.saved!['exercises'], isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('menu reorder updates visible card order', (tester) async {
    await mount(tester, [exercise('a'), exercise('b')]);
    await menu(tester, 'a', 'Posunout dolů');
    expect(app.active!.exercises.map((e) => e.exerciseId), ['b', 'a']);
    await tester.ensureVisible(find.text('Druhý cvik'));
    expect(
      tester.getTopLeft(find.text('Druhý cvik')).dy,
      lessThan(tester.getTopLeft(find.text('První cvik')).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid typed numbers cannot become completed sets', (
    tester,
  ) async {
    await mount(tester, [exercise('a')]);
    final weight = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'kg',
    );
    final reps = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'reps',
    );
    final rir = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'RIR',
    );
    final done = find.byType(Checkbox);
    for (final value in ['', 'text', 'NaN', 'Infinity', '-1']) {
      await tester.enterText(weight, value);
      await tester.tap(done);
      await tester.pump();
      expect(app.active!.exercises.single.sets.single.done, false);
      expect(find.text('Zadej váhu ≥ 0'), findsOneWidget);
    }
    await tester.enterText(weight, '0');
    await tester.enterText(reps, '0');
    await tester.tap(done);
    await tester.pump();
    expect(app.active!.exercises.single.sets.single.done, false);
    await tester.enterText(reps, '10');
    await tester.enterText(rir, 'text');
    await tester.tap(done);
    await tester.pump();
    expect(app.active!.exercises.single.sets.single.done, false);
    await tester.enterText(rir, '2');
    await tester.tap(done);
    await tester.pump();
    expect(app.active!.exercises.single.sets.single.done, true);
    await tester.enterText(weight, '');
    await tester.pump();
    expect(app.active!.exercises.single.sets.single.done, false);
    await tester.pumpWidget(const SizedBox());
  });
}
