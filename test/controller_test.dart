import 'dart:convert';

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
    Workout? saved;
    for (var attempt = 0; attempt < 60; attempt++) {
      saved = Workout.fromJson((await store.get(app.active!.id))!);
      if (saved.exercises.single.sets[0].weight == 50 && !app.activeSaving) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(saved!.exercises.single.sets[0].weight, 50);
    expect(app.activeSaving, isFalse);
  });

  test(
    'sync flushes a pending edit before reloading the active workout',
    () async {
      await app.savePlan(_plan());
      await app.startPlan(app.plans.single);
      app.active!.exercises.single.sets[0].weight = 47.5;
      app.touchActive();
      await app.sync();
      expect(app.active!.exercises.single.sets[0].weight, 47.5);
      final saved = Workout.fromJson((await store.get(app.active!.id))!);
      expect(saved.exercises.single.sets[0].weight, 47.5);
    },
  );

  test(
    'discard waits for an in-flight save and cannot resurrect a workout',
    () async {
      await app.savePlan(_plan());
      await app.startPlan(app.plans.single);
      final id = app.active!.id;
      app.active!.exercises.single.sets[0].reps = 8;
      app.touchActive();
      final writing = app.flushActive();
      await app.discardActive();
      await writing;
      expect(await store.get(id), isNull);
      expect(await store.all('active'), isEmpty);
    },
  );

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

  test(
    'warmups survive history but do not count toward PR or progression',
    () async {
      final plan = _plan();
      plan.exercises.single.warmupSets = 2;
      await app.savePlan(plan);
      await app.startPlan(app.plans.single);
      final workout = app.active!;
      workout.note = 'Lokty v pořádku';
      final sets = workout.exercises.single.sets;
      expect(sets.length, 5);
      expect(sets.take(2).every((s) => s.kind == 'warmup'), isTrue);
      for (final set in sets) {
        set.done = true;
      }
      sets.first.weight = 100;
      final proposals = await app.finish();
      expect(proposals.single.eligible, isTrue);
      expect(app.sessions.single.exercises.single.bestDoneWeight, 40);
      expect(app.sessions.single.note, 'Lokty v pořádku');
    },
  );

  test(
    'extra working set cannot silently change the saved progression rule',
    () async {
      await app.savePlan(_plan());
      await app.startPlan(app.plans.single);
      final exercise = app.active!.exercises.single;
      for (final set in exercise.sets) {
        set.done = true;
      }
      exercise.sets.add(
        WorkoutSet(target: 12, reps: 12, weight: 40, done: true),
      );
      final proposals = await app.finish();
      expect(proposals.single.eligible, isFalse);
      expect(proposals.single.reason, contains('Počet pracovních sérií'));
    },
  );

  test(
    'accepting a proposal updates the plan and keeps history order',
    () async {
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
    },
  );

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

  test(
    'quick workout starts without a plan and persists added exercise',
    () async {
      await app.startQuickWorkout();
      expect(app.active!.planId, isNull);
      await app.addExerciseToActive('bench_press');
      final id = app.active!.id;
      final stored = Workout.fromJson((await store.get(id))!);
      expect(stored.exercises.single.sets.length, 3);
      expect(stored.exercises.single.exerciseId, 'bench_press');
      expect(() => app.addExerciseToActive('bench_press'), throwsStateError);
      for (final set in app.active!.exercises.single.sets) {
        set.done = true;
      }
      expect(await app.finish(), isEmpty);
      expect(app.sessions.single.planName, 'Volný trénink');
    },
  );

  test('backup includes the latest unsaved active set', () async {
    await app.startQuickWorkout();
    await app.addExerciseToActive('bench_press');
    app.active!.exercises.single.sets.first.weight = 47.5;
    app.touchActive();
    final backup = jsonDecode(await app.exportBackup()) as Map<String, dynamic>;
    final activeItem = (backup['items'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['kind'] == 'active');
    final saved = Workout.fromJson(
      Map<String, dynamic>.from(activeItem['payload'] as Map),
    );
    expect(saved.exercises.single.sets.first.weight, 47.5);
  });
}
