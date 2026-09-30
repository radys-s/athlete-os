import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

late List<Map<String, String>> builtInExercises;

enum MeasurementType {
  weighted,
  bodyweight,
  assisted,
  timed;

  static MeasurementType parse(Object? value) =>
      values.firstWhere((type) => type.name == value, orElse: () => weighted);

  String get label => switch (this) {
    weighted => 'Váha a opakování',
    bodyweight => 'Vlastní váha',
    assisted => 'Dopomoc a opakování',
    timed => 'Čas',
  };

  String get weightLabel => switch (this) {
    bodyweight => 'Přidané kg (volitelné)',
    assisted => 'Dopomoc (kg)',
    _ => 'kg',
  };
}

MeasurementType exerciseMeasurement(
  String id,
  List<Map<String, dynamic>> custom,
) {
  for (final exercise in [...builtInExercises, ...custom]) {
    if (exercise['id'] == id) {
      return MeasurementType.parse(exercise['measurement']);
    }
  }
  return MeasurementType.weighted;
}

String setMeasurementLabel(WorkoutSet set, MeasurementType type) {
  final kg = set.weight == set.weight.roundToDouble()
      ? set.weight.toStringAsFixed(0)
      : set.weight.toString();
  return switch (type) {
    MeasurementType.timed => '${set.seconds} s',
    MeasurementType.bodyweight =>
      '${set.reps} opakování${set.weight > 0 ? ' + $kg kg' : ''}',
    MeasurementType.assisted => '$kg kg dopomoc × ${set.reps}',
    MeasurementType.weighted => '$kg kg × ${set.reps}',
  };
}

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
String completedWorkoutId(String activeId) =>
    _uuid.v5(Namespace.url.value, 'athlete-os/session/$activeId');

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
  MeasurementType measurement;
  String id;
  String exerciseId;
  List<int> targets;
  double weight;
  double step;
  String ruleType; // fixed | repRange
  int rangeMin;
  int rangeMax;
  int warmupSets;
  final Map<String, dynamic> extra;

  PlanExercise({
    this.measurement = MeasurementType.weighted,
    required this.id,
    required this.exerciseId,
    List<int>? targets,
    this.weight = 0,
    this.step = 2.5,
    this.ruleType = 'fixed',
    this.rangeMin = 8,
    this.rangeMax = 12,
    this.warmupSets = 0,
    Map<String, dynamic>? extra,
  }) : targets = targets ?? [12, 10, 8],
       extra = extra ?? {};

  static const _known = {
    'measurement',
    'id',
    'exerciseId',
    'targets',
    'weight',
    'step',
    'ruleType',
    'rangeMin',
    'rangeMax',
    'warmupSets',
  };

  factory PlanExercise.fromJson(Map<String, dynamic> json) {
    final exerciseId = json['exerciseId'] as String;
    final targets = ((json['targets'] as List<dynamic>?) ?? const [12, 10, 8])
        .map((e) => _i(e, 10))
        .toList();
    return PlanExercise(
      measurement: MeasurementType.parse(json['measurement']),
      // Legacy plans have no item id; the exercise id was unique per plan.
      id: json['id'] as String? ?? exerciseId,
      exerciseId: exerciseId,
      targets: targets.isEmpty ? [10] : targets,
      weight: _d(json['weight']),
      step: _d(json['step'], 2.5),
      ruleType: json['ruleType'] as String? ?? 'fixed',
      rangeMin: _i(json['rangeMin'], 8),
      rangeMax: _i(json['rangeMax'], 12),
      warmupSets: _i(json['warmupSets']),
      extra: _extra(json, _known),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'measurement': measurement.name,
    'id': id,
    'exerciseId': exerciseId,
    'targets': targets,
    'weight': weight,
    'step': step,
    'ruleType': ruleType,
    'rangeMin': rangeMin,
    'rangeMax': rangeMax,
    'warmupSets': warmupSets,
  };

  PlanExercise copy() => PlanExercise.fromJson(deepCopy(toJson()));

  /// Rep-range rules always aim every set at the upper bound.
  void syncTargetsToRange() {
    targets = List<int>.filled(targets.length, rangeMax < 1 ? 1 : rangeMax);
  }

  String? validate() {
    if (targets.isEmpty || targets.any((t) => t < 1)) {
      return measurement == MeasurementType.timed
          ? 'Cíl času musí být alespoň 1 sekunda.'
          : 'Cíl opakování musí být alespoň 1.';
    }
    if (measurement == MeasurementType.weighted &&
        (!step.isFinite || step <= 0)) {
      return 'Krok váhy musí být větší než 0.';
    }
    if (warmupSets < 0 || warmupSets > 5) {
      return 'Počet rozcvičovacích sérií musí být 0 až 5.';
    }
    if (measurement != MeasurementType.timed &&
        (!weight.isFinite || weight < 0)) {
      return 'Váha musí být platné nezáporné číslo.';
    }
    if (measurement == MeasurementType.weighted &&
        ruleType == 'repRange' &&
        (rangeMin < 1 || rangeMax < rangeMin)) {
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
  int seconds;
  int target;
  int reps;
  double weight;
  int? rir;
  bool done;
  String kind; // work | warmup
  final Map<String, dynamic> extra;

  WorkoutSet({
    this.seconds = 0,
    required this.target,
    required this.reps,
    required this.weight,
    this.rir,
    this.done = false,
    this.kind = 'work',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {
    'seconds',
    'target',
    'reps',
    'weight',
    'rir',
    'done',
    'kind',
  };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    seconds: _i(json['seconds']),
    target: _i(json['target'], _i(json['reps'])),
    reps: _i(json['reps']),
    weight: _d(json['weight']),
    rir: json['rir'] is num ? (json['rir'] as num).toInt() : null,
    done: json['done'] == true,
    kind: json['kind'] == 'warmup' ? 'warmup' : 'work',
    extra: _extra(json, _known),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'seconds': seconds,
    'target': target,
    'reps': reps,
    'weight': weight,
    'rir': rir,
    'done': done,
    'kind': kind,
  };
}

class WorkoutExercise {
  MeasurementType measurement;
  String exerciseId;
  String? planExerciseId;
  List<WorkoutSet> sets;

  /// Snapshot of the plan rule at workout start; history never depends on
  /// later plan edits.
  PlanExercise? rule;
  bool weightPr;
  String note;
  final Map<String, dynamic> extra;

  WorkoutExercise({
    this.measurement = MeasurementType.weighted,
    required this.exerciseId,
    this.planExerciseId,
    required this.sets,
    this.rule,
    this.weightPr = false,
    this.note = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  static const _known = {
    'measurement',
    'note',
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
      measurement: MeasurementType.parse(json['measurement']),
      exerciseId: json['exerciseId'] as String,
      planExerciseId: json['planExerciseId'] as String? ?? rule?.id,
      sets: asMaps(json['sets']).map(WorkoutSet.fromJson).toList(),
      rule: rule,
      weightPr: json['weightPr'] == true,
      note: json['note'] as String? ?? '',
      extra: _extra(json, _known),
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'measurement': measurement.name,
    if (note.trim().isNotEmpty) 'note': note,
    'exerciseId': exerciseId,
    if (planExerciseId != null) 'planExerciseId': planExerciseId,
    'targets': sets.map((s) => s.target).toList(),
    'sets': sets.map((s) => s.toJson()).toList(),
    if (rule != null) 'rule': rule!.toJson(),
    'weightPr': weightPr,
  };

  double get bestDoneWeight => measurement != MeasurementType.weighted
      ? 0
      : sets
            .where((s) => s.done && s.kind == 'work')
            .fold<double>(0, (best, s) => s.weight > best ? s.weight : best);

  List<WorkoutSet> get workSets => sets.where((s) => s.kind == 'work').toList();
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
  String note;
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
    this.note = '',
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
    'note',
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
    note: json['note'] as String? ?? '',
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
    'note': note,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
  };

  Workout copy() => Workout.fromJson(deepCopy(toJson()));

  String? validateCompleted() {
    if (!exercises.any((e) => e.workSets.any((s) => s.done))) {
      return 'Zapiš alespoň jednu pracovní sérii.';
    }
    for (final exercise in exercises) {
      for (final set in exercise.sets.where((s) => s.done)) {
        if (exercise.measurement == MeasurementType.timed
            ? set.seconds < 1
            : (set.reps < 1 ||
                  !set.weight.isFinite ||
                  set.weight < 0 ||
                  (set.rir != null && (set.rir! < 0 || set.rir! > 10)))) {
          if (exercise.measurement == MeasurementType.timed) {
            return 'Čas dokončené série musí být alespoň 1 sekunda.';
          }
          return 'Oprav opakování, váhu nebo RIR u dokončené série.';
        }
      }
    }
    return null;
  }
}
