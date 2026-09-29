import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'progression.dart';
import 'store.dart';
import 'sync.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final store = LocalStore();
  late final CloudSync cloud = CloudSync(store);
  List<Map<String, dynamic>> plans = [];
  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> customExercises = [];
  Map<String, dynamic>? active;
  String mode = 'Standard';
  String layout = 'Přehledný';
  bool ready = false;
  bool locked = false;
  bool pendingImport = false;
  String? syncError;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _syncTimer;
  bool _syncing = false;
  bool _syncRequested = false;

  Future<void> initialize() async {
    await store.open();
    await _refreshAccountState();
    await reload();
    if (CloudSync.configured) {
      WidgetsBinding.instance.addObserver(this);
      _syncTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(sync()),
      );
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((event) {
            unawaited(_refreshAccountState());
          });
    }
    ready = true;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> reload() async {
    plans = (await store.all('plan'))
        .where((plan) => plan['archived'] != true)
        .toList();
    sessions = await store.all('session');
    customExercises = await store.all('exercise');
    final activeSessions = await store.all('active');
    active = activeSessions.isEmpty ? null : activeSessions.first;
    final settings = await store.get('settings');
    mode = settings?['mode'] as String? ?? 'Standard';
    layout = settings?['layout'] as String? ?? 'Přehledný';
    notifyListeners();
  }

  Future<void> sync() async {
    if (locked || pendingImport) return;
    if (_syncing) {
      _syncRequested = true;
      return;
    }
    _syncing = true;
    do {
      _syncRequested = false;
      try {
        await cloud.sync();
        syncError = null;
        await reload();
        if (await store.conflictCount() > 0) {
          syncError = 'Některé změny vyžadují vyřešit konflikt.';
        }
      } catch (_) {
        syncError =
            'Změny jsou bezpečně v telefonu. Synchronizace se zkusí znovu.';
      }
    } while (_syncRequested);
    _syncing = false;
    notifyListeners();
  }

  Future<void> _refreshAccountState() async {
    final owner = await store.accountOwner();
    final currentId = user?.id;
    locked = owner != null && owner != currentId;
    pendingImport = !locked && owner == null && currentId != null &&
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

  Future<void> setPreferences({String? newMode, String? newLayout}) async {
    mode = newMode ?? mode;
    layout = newLayout ?? layout;
    await store.put('settings', {
      'id': 'settings',
      'mode': mode,
      'layout': layout,
    });
    notifyListeners();
    unawaited(sync());
  }

  Future<void> saveExercise(String name, String muscle) async {
    await store.put('exercise', {
      'id': store.newId(),
      'name': name.trim(),
      'muscle': muscle,
    });
    await reload();
    unawaited(sync());
  }

  Future<void> savePlan(Map<String, dynamic> plan) async {
    await store.put('plan', plan);
    await reload();
    unawaited(sync());
  }

  Future<void> duplicatePlan(Map<String, dynamic> plan) async {
    final copy = deepCopy(plan);
    copy['id'] = store.newId();
    copy['name'] = '${plan['name']} – kopie';
    copy['archived'] = false;
    await savePlan(copy);
  }

  Future<void> archivePlan(Map<String, dynamic> plan) async {
    final copy = deepCopy(plan);
    copy['archived'] = true;
    await savePlan(copy);
  }

  Future<void> deleteSession(String id) async {
    await store.remove(id);
    await reload();
    unawaited(sync());
  }

  Future<void> startPlan(Map<String, dynamic> plan) async {
    if (active != null) throw StateError('Nejdřív dokonči rozepsaný trénink.');
    final exercises = asMaps(plan['exercises']).map((item) {
      final targets = item['ruleType'] == 'repRange'
          ? List<num>.filled(
              (item['targets'] as List).length,
              (item['rangeMax'] as num?)?.toInt() ?? 12,
            )
          : (item['targets'] as List<dynamic>).cast<num>();
      return {
        'exerciseId': item['exerciseId'],
        'targets': targets,
        'rule': deepCopy(item),
        'sets': targets
            .map(
              (reps) => {
                'target': reps.toInt(),
                'reps': reps.toInt(),
                'weight': item['weight'],
                'rir': null,
                'done': false,
              },
            )
            .toList(),
      };
    }).toList();
    active = {
      'id': store.newId(),
      'planId': plan['id'],
      'planName': plan['name'],
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'exercises': exercises,
    };
    await store.put('active', active!);
    notifyListeners();
  }

  Future<void> startFromSession(Map<String, dynamic> session) async {
    if (active != null) throw StateError('Nejdřív dokonči rozepsaný trénink.');
    final exercises = asMaps(session['exercises']).map((item) {
      final sets = asMaps(item['sets'])
          .map(
            (set) => {
              'target': set['target'],
              'reps': set['reps'],
              'weight': set['weight'],
              'rir': null,
              'done': false,
            },
          )
          .toList();
      return {
        'exerciseId': item['exerciseId'],
        'targets': sets.map((s) => s['target']).toList(),
        if (item['rule'] != null) 'rule': item['rule'],
        'sets': sets,
      };
    }).toList();
    active = {
      'id': store.newId(),
      'planId': session['planId'],
      'planName': '${session['planName']} – znovu',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'exercises': exercises,
    };
    await store.put('active', active!);
    notifyListeners();
  }

  Future<void> saveActive() async {
    if (active == null) return;
    await store.put('active', active!);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> finish() async {
    final workout = active;
    if (workout == null) return [];
    final plan = await store.get(workout['planId'] as String);
    final proposals = <Map<String, dynamic>>[];
    if (plan != null) {
      final planExercises = asMaps(plan['exercises']);
      for (final exercise in asMaps(workout['exercises'])) {
        final item = planExercises
            .where((p) => p['exerciseId'] == exercise['exerciseId'])
            .firstOrNull;
        if (item == null) continue;
        final rule = exercise['rule'] is Map
            ? Map<String, dynamic>.from(exercise['rule'] as Map)
            : item;
        final result = evaluateProgression(rule, asMaps(exercise['sets']));
        proposals.add({
          'id': store.newId(),
          'exerciseId': exercise['exerciseId'],
          'planId': plan['id'],
          'currentWeight': item['weight'],
          'ruleWeight': rule['weight'],
          'suggestedWeight': result.suggestedWeight,
          'eligible': result.completed,
          'reason': result.reason,
          'status': 'pending',
        });
      }
    }
    final completed = deepCopy(workout);
    completed['id'] = store.newId();
    completed['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    completed['proposals'] = proposals;
    final completedExercises = asMaps(completed['exercises']);
    for (final exercise in completedExercises) {
      final id = exercise['exerciseId'];
      final currentBest = asMaps(exercise['sets'])
          .where((set) => set['done'] == true)
          .map((set) => (set['weight'] as num).toDouble())
          .fold<double>(0, (best, value) => value > best ? value : best);
      final previousBest = sessions
          .expand((session) => asMaps(session['exercises']))
          .where((item) => item['exerciseId'] == id)
          .expand((item) => asMaps(item['sets']))
          .where((set) => set['done'] == true)
          .map((set) => (set['weight'] as num).toDouble())
          .fold<double>(0, (best, value) => value > best ? value : best);
      exercise['weightPr'] = currentBest > 0 && currentBest > previousBest;
    }
    completed['exercises'] = completedExercises;
    await store.finishWorkout(workout, completed);
    active = null;
    await reload();
    unawaited(sync());
    return proposals;
  }

  Future<void> decideProposal(
    String sessionId,
    String proposalId, {
    required bool accept,
    double? chosenWeight,
  }) async {
    final session = await store.get(sessionId);
    if (session == null) return;
    final proposals = asMaps(session['proposals']);
    final proposal = proposals
        .where((item) => item['id'] == proposalId)
        .firstOrNull;
    if (proposal == null || proposal['status'] != 'pending') return;
    if (accept && proposal['eligible'] == true) {
      final plan = await store.get(proposal['planId'] as String);
      if (plan != null) {
        final exercises = asMaps(plan['exercises']);
        final exercise = exercises
            .where((e) => e['exerciseId'] == proposal['exerciseId'])
            .firstOrNull;
        if (exercise != null) {
          if (exercise['weight'] != proposal['ruleWeight']) {
            throw StateError(
              'Cíl cviku se mezitím změnil. Návrh už není aktuální.',
            );
          }
          exercise['weight'] = chosenWeight ?? proposal['suggestedWeight'];
          plan['exercises'] = exercises;
          await store.put('plan', plan);
        }
      }
    }
    proposal['status'] = accept ? 'accepted' : 'dismissed';
    proposal['chosenWeight'] = chosenWeight;
    session['proposals'] = proposals;
    await store.put('session', session);
    await reload();
    unawaited(sync());
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
      email: email, token: code, type: OtpType.email,
    );
  }

  Future<void> signOut() async {
    if (CloudSync.configured) await Supabase.instance.client.auth.signOut();
    locked = await store.accountOwner() != null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
