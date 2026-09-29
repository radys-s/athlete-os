import 'package:athlete_os/app_controller.dart';
import 'package:athlete_os/database.dart';
import 'package:athlete_os/models.dart';
import 'package:athlete_os/store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Plan _plan({double weight = 40}) => Plan(
  id: 'plan-1',
  name: 'Push',
  exercises: [
    PlanExercise(
      id: 'item-1',
      exerciseId: 'bench_press',
      targets: [12, 12, 12],
      weight: weight,
      step: 2.5,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AthleteDatabase database;
  late LocalStore store;
  late AppController app;

  setUp(() async {
    builtInExercises = [
      {'id': 'bench_press', 'name': 'Bench press', 'muscle': 'Hrudník'},
    ];
    database = AthleteDatabase(NativeDatabase.memory());
    store = LocalStore(database);
    app = AppController(store);
    await app.initialize();
  });

  tearDown(() async {
    app.dispose();
    await database.close();
  });

  test('rapid edits to different sets are all kept', () async {
    await app.savePlan(_plan());
    await app.startPlan(app.plans.single);
    final sets = app.active!.exercises.single.sets;
    sets[0].weight = 42.5;
    app.touchActive();
    sets[1].reps = 9;
    app.touchActive();
    sets[2].rir = 2;
    sets[2].done = true;
    app.touchActive();
    await app.flushActive();
    final saved = Workout.fromJson((await store.get(app.active!.id))!);
    final s = saved.exercises.single.sets;
    expect(s[0].weight, 42.5);
    expect(s[1].reps, 9);
    expect(s[2].rir, 2);
    expect(s[2].done, isTrue);
  });

  test('debounced save eventually writes without an explicit flush', () async {
    await app.savePlan(_plan());
    await app.startPlan(app.plans.single);
    app.active!.exercises.single.sets[0].weight = 50;
    app.touchActive();
    expect(app.activeSaving, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final saved = Workout.fromJson((await store.get(app.active!.id))!);
    expect(saved.exercises.single.sets[0].weight, 50);
    expect(app.activeSaving, isFalse);
  });

  test('finishing, proposals and stale-proposal guard', () async {
    await app.savePlan(_plan());
    await app.startPlan(app.plans.single);
    for (final set in app.active!.exercises.single.sets) {
      set.done = true;
    }
    final proposals = await app.finish();
    expect(proposals.single.eligible, isTrue);
    expect(proposals.single.suggestedWeight, 42.5);
    expect(proposals.single.planExerciseId, 'item-1');
    expect(app.active, isNull);
    final session = app.sessions.single;
    expect(session.exercises.single.weightPr, isTrue);

    // Plan changed after the workout: the old proposal must not apply.
    final changed = app.plans.single.copy()..exercises.single.weight = 45;
    await app.savePlan(changed);
    final error = await app.decideProposal(
      session.id,
      session.proposals.single.id,
      accept: true,
    );
    expect(error, contains('už není aktuální'));
    expect(app.plans.single.exercises.single.weight, 45);
  });

  test('accepting a proposal updates the plan and keeps history order', () async {
    await app.savePlan(_plan());
    // Two finished workouts; deciding on the older one must not reorder them.
    for (var i = 0; i < 2; i++) {
      await app.startPlan(app.plans.single);
      for (final set in app.active!.exercises.single.sets) {
        set.done = true;
        set.weight = 40;
      }
      await app.finish();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final newestFirst = app.sessions.map((s) => s.id).toList();
    final older = app.sessions.last;
    // Newer workout's proposal is stale after the older one is accepted.
    final error = await app.decideProposal(
      older.id,
      older.proposals.single.id,
      accept: true,
    );
    expect(error, isNull);
    expect(app.plans.single.exercises.single.weight, 42.5);
    expect(app.sessions.map((s) => s.id).toList(), newestFirst);
    expect(app.sessions.last.proposals.single.status, 'accepted');
  });

  test('discarding removes the active workout without history', () async {
    await app.savePlan(_plan());
    await app.startPlan(app.plans.single);
    await app.discardActive();
    expect(app.active, isNull);
    expect(app.sessions, isEmpty);
    expect(await store.all('active'), isEmpty);
  });

  test('a second workout cannot start while one is active', () async {
    await app.savePlan(_plan());
    await app.startPlan(app.plans.single);
    expect(() => app.startPlan(app.plans.single), throwsStateError);
  });
}
