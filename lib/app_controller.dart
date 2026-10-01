import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'progression.dart';
import 'store.dart';
import 'sync.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController([LocalStore? localStore]) : store = localStore ?? LocalStore();

  final LocalStore store;
  late final CloudSync cloud = CloudSync(store);
  List<Plan> plans = [];
  List<Workout> sessions = []; // newest finished workout first
  List<Map<String, dynamic>> customExercises = [];
  List<Map<String, dynamic>> conflicts = [];
  Workout? active;
  List<Workout> otherActiveWorkouts = [];
  String mode = 'Standard';
  String layout = 'Přehledný';
  bool onboardingComplete = false;
  String goal = 'Síla a svaly';
  bool ready = false;
  bool locked = false;
  bool pendingImport = false;
  bool activeSaving = false;
  String? syncError;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _syncTimer;
  Timer? _saveTimer;
  bool _syncing = false;
  bool _syncRequested = false;
  Future<void>? _syncFuture;
  bool _disposed = false;
  bool _flushing = false;
  bool _clearingLocalData = false;
  int _pendingWrites = 0;
  Future<void> _writeTail = Future<void>.value();
  String? saveError;

  Future<void> initialize() async {
    await store.open();
    WidgetsBinding.instance.addObserver(this);
    if (CloudSync.configured) {
      _syncTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(sync()),
      );
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((event) {
            unawaited(_refreshAccountState());
          });
    }
    await _refreshAccountState();
    await reload();
    ready = true;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> reload() async {
    plans = (await store.all('plan'))
        .map(Plan.fromJson)
        .where((plan) => !plan.archived)
        .toList();
    sessions = (await store.all('session')).map(Workout.fromJson).toList()
      ..sort(
        (a, b) => (b.finishedAt ?? b.startedAt).compareTo(
          a.finishedAt ?? a.startedAt,
        ),
      );
    customExercises = await store.all('exercise');
    final activeRows = await store.all('active');
    // Never replace the in-memory workout while edits are waiting to be saved.
    if (_saveTimer == null && !_flushing && saveError == null) {
      final selectedId = active?.id;
      final selected = activeRows
          .where((r) => r['id'] == selectedId)
          .firstOrNull;
      active = activeRows.isEmpty
          ? null
          : Workout.fromJson(selected ?? activeRows.first);
    }
    otherActiveWorkouts = activeRows
        .where((r) => r['id'] != active?.id)
        .map(Workout.fromJson)
        .toList();
    final settings = await store.get('settings');
    mode = settings?['mode'] as String? ?? 'Standard';
    layout = settings?['layout'] as String? ?? 'Přehledný';
    if (!{'Simple', 'Standard', 'Advanced'}.contains(mode)) mode = 'Standard';
    if (!{'Přehledný', 'Detailní', 'Soustředěný'}.contains(layout)) {
      layout = 'Přehledný';
    }
    goal = settings?['goal'] as String? ?? 'Síla a svaly';
    onboardingComplete =
        settings?['onboardingComplete'] == true || await store.hasWorkoutData();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> sync() {
    if (_disposed || locked || pendingImport || _clearingLocalData) {
      return Future<void>.value();
    }
    if (_syncing) {
      _syncRequested = true;
      return _syncFuture ?? Future<void>.value();
    }
    _syncing = true;
    final result = _runSync();
    _syncFuture = result;
    return result;
  }

  Future<void> _runSync() async {
    do {
      _syncRequested = false;
      try {
        if (activeSaving || _flushing || saveError != null) await flushActive();
        await cloud.sync();
        syncError = null;
        await reload();
        conflicts = await store.conflictCount() > 0
            ? await cloud.conflicts()
            : [];
        if (conflicts.isNotEmpty) {
          syncError = 'Některé změny vyžadují vyřešit konflikt.';
        }
      } catch (_) {
        syncError =
            'Změny jsou bezpečně v telefonu. Synchronizace se zkusí znovu.';
      }
    } while (_syncRequested);
    _syncing = false;
    _syncFuture = null;
    notifyListeners();
  }

  Future<void> resolveConflict(
    Map<String, dynamic> remote, {
    required bool keepLocal,
  }) async {
    await store.resolveConflict(
      remote['id'] as String,
      keepLocal: keepLocal,
      remote: remote,
    );
    conflicts = conflicts.where((c) => c['id'] != remote['id']).toList();
    await reload();
    unawaited(sync());
  }

  Future<void> _refreshAccountState() async {
    final owner = await store.accountOwner();
    final currentId = user?.id;
    locked = owner != null && owner != currentId;
    pendingImport =
        !locked &&
        owner == null &&
        currentId != null &&
        await store.hasWorkoutData();
    notifyListeners();
    if (!locked && !pendingImport && currentId != null) unawaited(sync());
  }

  Future<void> confirmImport() async {
    final currentId = user?.id;
    if (currentId == null) throw StateError('Nejdřív se přihlas.');
    await store.bindAccount(currentId);
    pendingImport = false;
    notifyListeners();
    await sync();
  }

  Future<void> setPreferences({
    String? newMode,
    String? newLayout,
    String? newGoal,
    bool? finishOnboarding,
  }) async {
    _requireUnlocked();
    final existing = await store.get('settings');
    final nextMode = newMode ?? mode;
    final nextLayout = newLayout ?? layout;
    final nextGoal = newGoal ?? goal;
    final nextOnboarding = finishOnboarding ?? onboardingComplete;
    await store.put('settings', {
      ...?existing,
      'id': 'settings',
      'mode': nextMode,
      'layout': nextLayout,
      'goal': nextGoal,
      'onboardingComplete': nextOnboarding,
    });
    mode = nextMode;
    layout = nextLayout;
    goal = nextGoal;
    onboardingComplete = nextOnboarding;
    notifyListeners();
    unawaited(sync());
  }

  Future<String> exportBackup() async {
    _requireUnlocked();
    if (active != null) await flushActive();
    return store.exportBackup();
  }

  Future<int> importBackup(String source) async {
    _requireUnlocked();
    final count = await store.importBackup(source);
    await reload();
    await _refreshAccountState();
    return count;
  }

  Future<void> saveExercise(
    String name,
    String muscle,
    String equipment, {
    MeasurementType measurement = MeasurementType.weighted,
  }) async {
    _requireUnlocked();
    await store.put('exercise', {
      'id': newId(),
      'name': name.trim(),
      'muscle': muscle,
      'equipment': equipment,
      'measurement': measurement.name,
    });
    await reload();
    unawaited(sync());
  }

  Future<void> savePlan(Plan plan) async {
    _requireUnlocked();
    final error = plan.validate();
    if (error != null) throw StateError(error);
    await store.put('plan', plan.toJson());
    await reload();
    unawaited(sync());
  }

  Future<void> duplicatePlan(Plan plan) async {
    final copy = Plan.fromJson(deepCopy(plan.toJson()));
    copy.id = newId();
    copy.name = '${plan.name} – kopie';
    copy.archived = false;
    for (final item in copy.exercises) {
      item.id = newId();
    }
    await savePlan(copy);
  }

  Future<void> archivePlan(Plan plan) async {
    final copy = plan.copy()..archived = true;
    await savePlan(copy);
  }

  /// Saves an edited finished workout and recomputes PR flags of all
  /// sessions in chronological order. Pending proposals of the edited
  /// workout are dropped because they were derived from the old numbers.
  Future<void> saveEditedSession(Workout edited) async {
    _requireUnlocked();
    final error = edited.validateCompleted();
    if (error != null) throw StateError(error);
    final prior = await store.raw(edited.id);
    if (prior == null || prior['kind'] != 'session' || prior['deleted'] == 1) {
      throw StateError('Trénink už neexistuje.');
    }
    await store.db.transaction(() async {
      edited.proposals = edited.proposals
          .where((p) => p.status != 'pending')
          .toList();
      await store.put('session', edited.toJson());
      await _recomputePrFlags();
    });
    await reload();
    unawaited(sync());
  }

  Future<void> deleteSession(String id) async {
    _requireUnlocked();
    await store.db.transaction(() async {
      await store.remove(id);
      await _recomputePrFlags();
    });
    await reload();
    unawaited(sync());
  }

  Future<void> _recomputePrFlags() async {
    final best = <String, double>{};
    final ordered = (await store.all('session')).map(Workout.fromJson).toList()
      ..sort(
        (a, b) => (a.finishedAt ?? a.startedAt).compareTo(
          b.finishedAt ?? b.startedAt,
        ),
      );
    for (final session in ordered) {
      var changed = false;
      for (final exercise in session.exercises) {
        final top = exercise.measurement == MeasurementType.weighted
            ? exercise.bestDoneWeight
            : 0.0;
        final previous = best[exercise.exerciseId] ?? 0;
        final pr = top > 0 && top > previous;
        if (exercise.weightPr != pr) {
          exercise.weightPr = pr;
          changed = true;
        }
        if (top > previous) best[exercise.exerciseId] = top;
      }
      if (changed) await store.put('session', session.toJson());
    }
  }

  double _roundToStep(double value, double step) =>
      step > 0 ? (value / step).round() * step : value.roundToDouble();

  WorkoutSet _newSet(
    int target,
    double weight, [
    MeasurementType measurement = MeasurementType.weighted,
  ]) => WorkoutSet(
    target: target,
    reps: measurement == MeasurementType.timed ? 0 : target,
    seconds: measurement == MeasurementType.timed ? target : 0,
    weight: weight,
  );

  Future<void> startQuickWorkout() async {
    _requireUnlocked();
    if (active != null) throw StateError('Nejdřív dokonči rozepsaný trénink.');
    final workout = Workout(
      id: newId(),
      planName: 'Volný trénink',
      startedAt: DateTime.now().toUtc(),
      exercises: [],
    );
    await store.put('active', workout.toJson());
    active = workout;
    notifyListeners();
  }

  Future<void> addExerciseToActive(String exerciseId) async {
    _requireUnlocked();
    final workout = active;
    if (workout == null) throw StateError('Žádný rozepsaný trénink.');
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
    workout.exercises.add(
      WorkoutExercise(
        exerciseId: exerciseId,
        measurement: measurement,
        sets: List.generate(
          3,
          (_) => _newSet(
            lastWork?.target ??
                (measurement == MeasurementType.timed ? 30 : 10),
            lastWork?.weight ?? 0,
            measurement,
          ),
        ),
      ),
    );
    notifyListeners();
    await flushActive();
  }

  Future<void> startPlan(Plan plan) async {
    _requireUnlocked();
    if (active != null) throw StateError('Nejdřív dokonči rozepsaný trénink.');
    final exercises = plan.exercises.map((item) {
      final targets =
          item.measurement == MeasurementType.weighted &&
              item.ruleType == 'repRange'
          ? List<int>.filled(item.targets.length, item.rangeMax)
          : List<int>.of(item.targets);
      return WorkoutExercise(
        exerciseId: item.exerciseId,
        measurement: item.measurement,
        planExerciseId: item.id,
        rule: item.copy(),
        extra: {
          if (item.extra['supersetId'] != null)
            'supersetId': item.extra['supersetId'],
        },
        sets: [
          for (var i = 0; i < item.warmupSets; i++)
            WorkoutSet(
              target: 5,
              reps: item.measurement == MeasurementType.timed ? 0 : 5,
              seconds: item.measurement == MeasurementType.timed ? 5 : 0,
              weight:
                  item.measurement == MeasurementType.weighted &&
                      item.weight > 0
                  ? _roundToStep(
                      item.weight * (i + 1) / (item.warmupSets + 1),
                      item.step,
                    )
                  : item.measurement == MeasurementType.timed
                  ? 0
                  : item.weight,
              kind: 'warmup',
            ),
          ...targets.map((t) => _newSet(t, item.weight, item.measurement)),
        ],
      );
    }).toList();
    final workout = Workout(
      id: newId(),
      planId: plan.id,
      planName: plan.name,
      startedAt: DateTime.now().toUtc(),
      exercises: exercises,
    );
    await store.put('active', workout.toJson());
    active = workout;
    notifyListeners();
  }

  Future<void> startFromSession(Workout session) async {
    _requireUnlocked();
    if (active != null) throw StateError('Nejdřív dokonči rozepsaný trénink.');
    final exercises = session.exercises
        .map(
          (item) => WorkoutExercise(
            exerciseId: item.exerciseId,
            measurement: item.measurement,
            planExerciseId: item.planExerciseId,
            rule: item.rule?.copy(),
            note: item.note,
            extra: deepCopy(item.extra),
            sets: item.sets
                .map(
                  (s) => WorkoutSet(
                    target: s.target,
                    reps: s.reps,
                    weight: s.weight,
                    rir: s.rir,
                    kind: s.kind,
                    seconds: s.seconds,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final workout = Workout(
      id: newId(),
      planId: session.planId,
      planName: '${session.planName} – znovu',
      startedAt: DateTime.now().toUtc(),
      exercises: exercises,
    );
    await store.put('active', workout.toJson());
    active = workout;
    notifyListeners();
  }

  /// Called after every in-place edit of [active]. Writes are debounced so a
  /// burst of keystrokes is one database write.
  void touchActive() {
    if (active == null) return;
    activeSaving = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(flushActive().catchError((Object _) {}));
    });
  }

  Future<void> flushActive() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final workout = active;
    if (workout == null) {
      activeSaving = false;
      saveError = null;
      return;
    }
    final snapshot = workout.toJson();
    _flushing = true;
    _pendingWrites++;
    final next = _writeTail
        .catchError((Object _) {})
        .then((_) => store.put('active', snapshot));
    _writeTail = next;
    try {
      await next;
      saveError = null;
    } catch (_) {
      saveError = 'Trénink se nepodařilo uložit. Zkus to znovu.';
      rethrow;
    } finally {
      _pendingWrites--;
      _flushing = _pendingWrites > 0;
      if (_saveTimer == null && !_flushing) activeSaving = false;
      notifyListeners();
    }
  }

  Future<void> discardActive() async {
    _requireUnlocked();
    final workout = active;
    if (workout == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    await _writeTail.catchError((Object _) {});
    await store.remove(workout.id);
    activeSaving = false;
    saveError = null;
    active = null;
    notifyListeners();
    unawaited(sync());
  }

  PlanExercise? _planItemFor(Plan plan, WorkoutExercise exercise) {
    if (exercise.extra['detachedFromPlan'] == true) return null;
    for (final item in plan.exercises) {
      if (item.id == exercise.planExerciseId) return item;
    }
    if (exercise.planExerciseId == null || exercise.rule == null) {
      for (final item in plan.exercises) {
        if (item.exerciseId == exercise.exerciseId) return item;
      }
    }
    return null;
  }

  Future<List<Proposal>> finish() async {
    _requireUnlocked();
    final workout = active;
    if (workout == null) return [];
    final error = workout.validateCompleted();
    if (error != null) throw StateError(error);
    await flushActive();
    final planId = workout.planId;
    final planRow = planId == null ? null : await store.get(planId);
    final plan = planRow == null ? null : Plan.fromJson(planRow);
    final proposals = <Proposal>[];
    if (plan != null) {
      for (final exercise in workout.exercises) {
        if (exercise.measurement != MeasurementType.weighted) continue;
        final item = _planItemFor(plan, exercise);
        if (item == null) continue;
        final rule = exercise.rule ?? item;
        final result = evaluateProgression(
          rule.toJson(),
          exercise.workSets.map((s) => s.toJson()).toList(),
        );
        proposals.add(
          Proposal(
            id: newId(),
            exerciseId: exercise.exerciseId,
            planExerciseId: item.id,
            planId: plan.id,
            currentWeight: item.weight,
            ruleWeight: rule.weight,
            suggestedWeight: result.suggestedWeight,
            eligible: result.completed,
            reason: result.reason,
            extra: {'ruleSnapshot': rule.toJson()},
          ),
        );
      }
    }
    final completed = workout.copy()
      ..id = completedWorkoutId(workout.id)
      ..finishedAt = DateTime.now().toUtc()
      ..proposals = proposals;
    for (final exercise in completed.exercises) {
      if (exercise.measurement != MeasurementType.weighted) {
        exercise.weightPr = false;
        continue;
      }
      final currentBest = exercise.bestDoneWeight;
      final previousBest = sessions
          .expand((session) => session.exercises)
          .where(
            (item) =>
                item.exerciseId == exercise.exerciseId &&
                item.measurement == MeasurementType.weighted,
          )
          .fold<double>(
            0,
            (best, item) =>
                item.bestDoneWeight > best ? item.bestDoneWeight : best,
          );
      exercise.weightPr = currentBest > 0 && currentBest > previousBest;
    }
    await store.finishWorkout(workout.toJson(), completed.toJson());
    active = null;
    await reload();
    unawaited(sync());
    return proposals;
  }

  /// Returns a Czech error message when the decision cannot be applied.
  Future<String?> decideProposal(
    String sessionId,
    String proposalId, {
    required bool accept,
    double? chosenWeight,
  }) async {
    _requireUnlocked();
    final error = await store.db.transaction<String?>(() async {
      final row = await store.get(sessionId);
      if (row == null) return 'Trénink už neexistuje.';
      final session = Workout.fromJson(row);
      final proposal = session.proposals
          .where((item) => item.id == proposalId)
          .firstOrNull;
      if (proposal == null || proposal.status != 'pending') return null;
      if (accept && !proposal.eligible) {
        return 'Tento návrh nesplňuje pravidlo progrese.';
      }
      final nextWeight = chosenWeight ?? proposal.suggestedWeight;
      if (accept && (!nextWeight.isFinite || nextWeight < 0)) {
        return 'Váha musí být platné nezáporné číslo.';
      }
      if (accept && proposal.eligible) {
        final planRow = proposal.planId == null
            ? null
            : await store.get(proposal.planId!);
        if (planRow == null) return 'Plán už neexistuje.';
        {
          final plan = Plan.fromJson(planRow);
          if (plan.archived) return 'Plán je archivovaný.';
          final item = plan.exercises
              .where(
                (e) =>
                    e.id == (proposal.planExerciseId ?? proposal.exerciseId) ||
                    (proposal.planExerciseId == null &&
                        e.exerciseId == proposal.exerciseId),
              )
              .firstOrNull;
          if (item == null || item.exerciseId != proposal.exerciseId) {
            return 'Cvik už není v plánu.';
          }
          {
            final snapshot = proposal.extra['ruleSnapshot'];
            final ruleChanged =
                snapshot is Map &&
                !_sameRule(
                  item,
                  PlanExercise.fromJson(Map<String, dynamic>.from(snapshot)),
                );
            if (item.weight != proposal.ruleWeight || ruleChanged) {
              return 'Cíl cviku se mezitím změnil. Návrh už není aktuální.';
            }
            item.weight = chosenWeight ?? proposal.suggestedWeight;
            await store.put('plan', plan.toJson());
          }
        }
      }
      proposal.status = accept ? 'accepted' : 'dismissed';
      proposal.chosenWeight = accept ? nextWeight : null;
      await store.put('session', session.toJson());
      return null;
    });
    if (error != null) return error;
    await reload();
    unawaited(sync());
    return null;
  }

  bool _sameRule(PlanExercise a, PlanExercise b) =>
      a.measurement == b.measurement &&
      a.exerciseId == b.exerciseId &&
      a.ruleType == b.ruleType &&
      a.step == b.step &&
      a.rangeMin == b.rangeMin &&
      a.rangeMax == b.rangeMax &&
      listEquals(a.targets, b.targets);

  void _requireUnlocked() {
    if (locked || _clearingLocalData) {
      throw StateError('Data tohoto účtu jsou zamčená.');
    }
  }

  User? get user =>
      CloudSync.configured ? Supabase.instance.client.auth.currentUser : null;

  Future<void> signIn(String email) async {
    if (!CloudSync.configured) throw StateError('Cloud není nakonfigurován.');
    await Supabase.instance.client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: kIsWeb ? Uri.base.origin : 'athleteos://login-callback/',
    );
  }

  Future<void> verifyEmailCode(String email, String code) async {
    if (!CloudSync.configured) throw StateError('Cloud není nakonfigurován.');
    await Supabase.instance.client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  /// Deletes the cloud account (RPC `delete_my_account`) and all local data.
  Future<void> deleteAccount() async {
    if (!CloudSync.configured || user == null) {
      throw StateError('Nejsi přihlášený.');
    }
    await Supabase.instance.client.rpc('delete_my_account');
    await wipeLocalData();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // The auth user no longer exists; a failing sign-out is expected.
    }
    await _refreshAccountState();
  }

  /// Removes all data stored on this device (the cloud copy stays).
  Future<void> wipeLocalData() async {
    _clearingLocalData = true;
    try {
      _syncTimer?.cancel();
      _syncRequested = false;
      locked = true;
      _saveTimer?.cancel();
      _saveTimer = null;
      activeSaving = false;
      saveError = null;
      active = null;
      await _writeTail.catchError((Object _) {});
      await (_syncFuture ?? Future<void>.value()).catchError((Object _) {});
      if (CloudSync.configured) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      await store.wipeLocal();
      conflicts = [];
      await reload();
    } finally {
      _clearingLocalData = false;
      await _refreshAccountState();
      if (CloudSync.configured && !_disposed) {
        _syncTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => unawaited(sync()),
        );
      }
    }
  }

  Future<void> selectActiveWorkout(String id) async {
    if (active != null) await flushActive();
    final row = await store.raw(id);
    if (row == null || row['kind'] != 'active' || row['deleted'] == 1) {
      throw StateError('Rozepsaný trénink už neexistuje.');
    }
    active = Workout.fromJson(await store.get(id) ?? {});
    await reload();
  }

  Future<void> signOut() async {
    if (CloudSync.configured) await Supabase.instance.client.auth.signOut();
    locked = await store.accountOwner() != null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      unawaited(flushActive().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _saveTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
