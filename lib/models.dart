import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

late List<Map<String, String>> builtInExercises;

Future<void> loadCatalog() async {
  final raw = await rootBundle.loadString('catalog/exercises.json');
  builtInExercises = (jsonDecode(raw) as List<dynamic>)
      .map((item) => Map<String, String>.from(item as Map))
      .toList();
}

Map<String, dynamic> deepCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

List<Map<String, dynamic>> asMaps(dynamic value) =>
    ((value as List<dynamic>?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

String exerciseName(String id, List<Map<String, dynamic>> custom) {
  for (final exercise in [...builtInExercises, ...custom]) {
    if (exercise['id'] == id) return exercise['name'] as String;
  }
  return 'Neznámý cvik';
}

String exerciseMuscle(String id, List<Map<String, dynamic>> custom) {
  for (final exercise in [...builtInExercises, ...custom]) {
    if (exercise['id'] == id) return exercise['muscle'] as String;
  }
  return 'Ostatní';
}

const _uuid = Uuid();
String newId() => _uuid.v4();

double _d(Object? v, [double fallback = 0]) => v is num
    ? v.toDouble()
    : (v is String ? double.tryParse(v) ?? fallback : fallback);
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

/// Keys the app does not know about are kept so data written by a newer
/// version survives a round trip through this version.
Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> known) => {
  for (final e in json.entries)
    if (!known.contains(e.key)) e.key: e.value,
};

class PlanExercise {
  String id;
  String exerciseId;
  List<int> targets;
  double weight;
  double step;
  String ruleType; // fixed | repRange
  int rangeMin;
  int rangeMax;
  final Map<String, dynamic> extra;

  PlanExercise({
    required this.id,
    required this.exerciseId,
    List<int>? targets,
    this.weight = 0,
    this.step = 2.5,
    this.ruleType = 'fixed',
    this.rangeMin = 8,
    this.rangeMax = 12,
    Map<String, dynamic>? extra,
  }) : targets = targets ?? [12, 10, 8],
       extra = extra ?? {};

  static const _known = {
    'id',
    'exerciseId',
    'targets',
    'weight',
    'step',
    'ruleType',
    'rangeMin',
    'rangeMax',
  };

  factory PlanExercise.fromJson(Map<String, dynamic> json) {
    final exerciseId = json['exerciseId'] as String;
    final targets = ((json['targets'] as List<dynamic>?) ?? const [12, 10, 8])
        .map((e) => _i(e, 10))
        .toList();
    return PlanExercise(
      // Legacy plans have no item id; the exercise id was unique per plan.
      id: json['id'] as String? ?? exerciseId,
      exerciseId: exerciseId,
      targets: targets.isEmpty ? [10] : targets,
      weight: _d(json['weight']),
      step: _d(json['step'], 2.5),
      ruleType: json['ruleType'] as String? ?? 'fixed',
      rangeMin: _i(json['rangeMin'], 8),
      rangeMax: _i(json['rangeMax'], 12),
      extra: _extra(json, _known),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'exerciseId': exerciseId,
    'targets': targets,
    'weight': weight,
    'step': step,
    'ruleType': ruleType,
    'rangeMin': rangeMin,
    'rangeMax': rangeMax,
  };

  PlanExercise copy() => PlanExercise.fromJson(deepCopy(toJson()));

  /// Rep-range rules always aim every set at the upper bound.
  void syncTargetsToRange() {
    targets = List<int>.filled(targets.length, rangeMax < 1 ? 1 : rangeMax);
  }

  String? validate() {
    if (targets.isEmpty || targets.any((t) => t < 1)) {
      return 'Cíl opakování musí být alespoň 1.';
    }
    if (step <= 0) return 'Krok váhy musí být větší než 0.';
    if (weight < 0) return 'Váha nemůže být záporná.';
    if (ruleType == 'repRange' && (rangeMin < 1 || rangeMax < rangeMin)) {
      return 'Rozsah opakování je neplatný.';
    }
    return null;
  }
}

class Plan {
  String id;
  String name;
  bool archived;
  List<PlanExercise> exercises;
  final Map<String, dynamic> extra;

  Plan({
    required this.id,
    required this.name,
    this.archived = false,
    List<PlanExercise>? exercises,
    Map<String, dynamic>? extra,
  }) : exercises = exercises ?? [],
       extra = extra ?? {};

  static const _known = {'id', 'name', 'archived', 'exercises'};

  factory Plan.create() => Plan(id: newId(), name: '');

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    archived: json['archived'] == true,
    exercises: asMaps(json['exercises']).map(PlanExercise.fromJson).toList(),
    extra: _extra(json, _known),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'archived': archived,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  Plan copy() => Plan.fromJson(deepCopy(toJson()));

  String? validate() {
    if (name.trim().isEmpty) return 'Doplň název plánu.';
    if (exercises.isEmpty) return 'Přidej alespoň jeden cvik.';
    for (final e in exercises) {
      final error = e.validate();
      if (error != null) return error;
    }
    return null;
  }
}

class WorkoutSet {
  int target;
  int reps;
  double weight;
  int? rir;
  bool done;
  final Map<String, dynamic> extra;

  WorkoutSet({
    required this.target,
    required this.reps,
    required this.weight,
    this.rir,
    this.done = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {'target', 'reps', 'weight', 'rir', 'done'};

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    target: _i(json['target'], _i(json['reps'])),
    reps: _i(json['reps']),
    weight: _d(json['weight']),
    rir: json['rir'] is num ? (json['rir'] as num).toInt() : null,
    done: json['done'] == true,
    extra: _extra(json, _known),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'target': target,
    'reps': reps,
    'weight': weight,
    'rir': rir,
    'done': done,
  };
}

class WorkoutExercise {
  String exerciseId;
  String? planExerciseId;
  List<WorkoutSet> sets;

  /// Snapshot of the plan rule at workout start; history never depends on
  /// later plan edits.
  PlanExercise? rule;
  bool weightPr;
  final Map<String, dynamic> extra;

  WorkoutExercise({
    required this.exerciseId,
    this.planExerciseId,
    required this.sets,
    this.rule,
    this.weightPr = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {
    'exerciseId',
    'planExerciseId',
    'sets',
    'rule',
    'weightPr',
    'targets',
  };

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    PlanExercise? rule;
    if (json['rule'] is Map) {
      rule = PlanExercise.fromJson(
        Map<String, dynamic>.from(json['rule'] as Map),
      );
    }
    return WorkoutExercise(
      exerciseId: json['exerciseId'] as String,
      planExerciseId: json['planExerciseId'] as String? ?? rule?.id,
      sets: asMaps(json['sets']).map(WorkoutSet.fromJson).toList(),
      rule: rule,
      weightPr: json['weightPr'] == true,
      extra: _extra(json, _known),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'exerciseId': exerciseId,
    if (planExerciseId != null) 'planExerciseId': planExerciseId,
    'targets': sets.map((s) => s.target).toList(),
    'sets': sets.map((s) => s.toJson()).toList(),
    if (rule != null) 'rule': rule!.toJson(),
    'weightPr': weightPr,
  };

  double get bestDoneWeight => sets
      .where((s) => s.done)
      .fold<double>(0, (best, s) => s.weight > best ? s.weight : best);
}

class Proposal {
  String id;
  String exerciseId;
  String? planExerciseId;
  String? planId;
  double currentWeight;
  double ruleWeight;
  double suggestedWeight;
  bool eligible;
  String reason;
  String status; // pending | accepted | dismissed
  double? chosenWeight;
  final Map<String, dynamic> extra;

  Proposal({
    required this.id,
    required this.exerciseId,
    this.planExerciseId,
    this.planId,
    required this.currentWeight,
    required this.ruleWeight,
    required this.suggestedWeight,
    required this.eligible,
    required this.reason,
    this.status = 'pending',
    this.chosenWeight,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {
    'id',
    'exerciseId',
    'planExerciseId',
    'planId',
    'currentWeight',
    'ruleWeight',
    'suggestedWeight',
    'eligible',
    'reason',
    'status',
    'chosenWeight',
  };

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
    id: json['id'] as String,
    exerciseId: json['exerciseId'] as String,
    planExerciseId: json['planExerciseId'] as String?,
    planId: json['planId'] as String?,
    currentWeight: _d(json['currentWeight']),
    ruleWeight: _d(json['ruleWeight']),
    suggestedWeight: _d(json['suggestedWeight']),
    eligible: json['eligible'] == true,
    reason: json['reason'] as String? ?? '',
    status: json['status'] as String? ?? 'pending',
    chosenWeight: json['chosenWeight'] is num
        ? (json['chosenWeight'] as num).toDouble()
        : null,
    extra: _extra(json, _known),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'exerciseId': exerciseId,
    if (planExerciseId != null) 'planExerciseId': planExerciseId,
    'planId': planId,
    'currentWeight': currentWeight,
    'ruleWeight': ruleWeight,
    'suggestedWeight': suggestedWeight,
    'eligible': eligible,
    'reason': reason,
    'status': status,
    'chosenWeight': chosenWeight,
  };

  String get statusLabel => switch (status) {
    'accepted' => 'Přijato',
    'dismissed' => 'Ponecháno',
    _ => 'Čeká na rozhodnutí',
  };
}

/// One record type for both an in-progress workout (kind `active`) and a
/// finished one (kind `session`, `finishedAt` set).
class Workout {
  String id;
  String? planId;
  String planName;
  DateTime startedAt;
  DateTime? finishedAt;
  DateTime? restEnd;
  int restSeconds;
  List<WorkoutExercise> exercises;
  List<Proposal> proposals;
  final Map<String, dynamic> extra;

  Workout({
    required this.id,
    this.planId,
    required this.planName,
    required this.startedAt,
    this.finishedAt,
    this.restEnd,
    this.restSeconds = 90,
    required this.exercises,
    List<Proposal>? proposals,
    Map<String, dynamic>? extra,
  }) : proposals = proposals ?? [],
       extra = extra ?? {};

  static const _known = {
    'id',
    'planId',
    'planName',
    'startedAt',
    'finishedAt',
    'restEnd',
    'restSeconds',
    'exercises',
    'proposals',
  };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: json['id'] as String,
    planId: json['planId'] as String?,
    planName: json['planName'] as String? ?? 'Trénink',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '') ??
        DateTime.now().toUtc(),
    finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
    restEnd: DateTime.tryParse(json['restEnd'] as String? ?? ''),
    restSeconds: _i(json['restSeconds'], 90),
    exercises: asMaps(json['exercises']).map(WorkoutExercise.fromJson).toList(),
    proposals: asMaps(json['proposals']).map(Proposal.fromJson).toList(),
    extra: _extra(json, _known),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'id': id,
    'planId': planId,
    'planName': planName,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    if (restEnd != null) 'restEnd': restEnd!.toUtc().toIso8601String(),
    'restSeconds': restSeconds,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
  };

  Workout copy() => Workout.fromJson(deepCopy(toJson()));
}
