import 'models.dart';

class ProgressionResult {
  final bool completed;
  final String reason;
  final double suggestedWeight;

  const ProgressionResult(this.completed, this.reason, this.suggestedWeight);
}

ProgressionResult evaluateProgression(
  Map<String, dynamic> exercise,
  List<Map<String, dynamic>> performed,
) {
  if (MeasurementType.parse(exercise['measurement']) !=
      MeasurementType.weighted) {
    return ProgressionResult(
      false,
      'Tento typ měření nepoužívá automatický návrh váhy.',
      (exercise['weight'] as num?)?.toDouble() ?? 0,
    );
  }
  final targets = (exercise['targets'] as List<dynamic>).cast<num>();
  final currentWeight = (exercise['weight'] as num).toDouble();
  final step = (exercise['step'] as num).toDouble();
  final rangeRule = exercise['ruleType'] == 'repRange';
  final rangeMax = (exercise['rangeMax'] as num?)?.toInt() ?? 12;
  final rangeMin = (exercise['rangeMin'] as num?)?.toInt() ?? 8;
  if (currentWeight <= 0) {
    return const ProgressionResult(
      false,
      'Pro návrh vyšší váhy nejdřív nastav výchozí váhu cviku v plánu.',
      0,
    );
  }
  if (performed.length != targets.length) {
    return ProgressionResult(
      false,
      'Počet pracovních sérií se liší od plánu. Automatický návrh váhy se nepoužije.',
      currentWeight,
    );
  }
  if (performed.any((set) => set['done'] != true)) {
    return ProgressionResult(
      false,
      'Nejsou dokončené všechny série.',
      currentWeight,
    );
  }
  for (var i = 0; i < targets.length; i++) {
    if ((performed[i]['weight'] as num).toDouble() < currentWeight) {
      return ProgressionResult(
        false,
        'Série ${i + 1} byla pod plánovanou váhou. Ponechat současný cíl.',
        currentWeight,
      );
    }
    final goal = rangeRule ? rangeMax : targets[i];
    if ((performed[i]['reps'] as num) < goal) {
      if (rangeRule && (performed[i]['reps'] as num) >= rangeMin) {
        return ProgressionResult(
          false,
          'Série ${i + 1} je v rozsahu $rangeMin–$rangeMax. Zatím ponechat váhu.',
          currentWeight,
        );
      }
      return ProgressionResult(
        false,
        'Série ${i + 1}: ${performed[i]['reps']} z cílových $goal opakování. Ponechat současný cíl.',
        currentWeight,
      );
    }
  }
  return ProgressionResult(
    true,
    rangeRule
        ? 'Všechny série dosáhly horní hranice $rangeMax opakování. Pravidlo navrhuje přidat ${step.toStringAsFixed(1)} kg.'
        : 'Splnil jsi všech ${targets.length} cílových sérií. Pravidlo navrhuje přidat ${step.toStringAsFixed(1)} kg.',
    currentWeight + step,
  );
}

double? estimatedOneRepMax(double weight, int reps) {
  if (weight <= 0 || reps < 1 || reps > 10) return null;
  return weight * (1 + reps / 30);
}

/// Comparable within a single measurement type; assistance improves downward.
double? bestCompletedMeasurement(WorkoutExercise exercise) {
  final sets = exercise.workSets.where((s) => s.done);
  double? best;
  for (final set in sets) {
    final value = switch (exercise.measurement) {
      MeasurementType.weighted || MeasurementType.assisted => set.weight,
      MeasurementType.bodyweight => set.reps.toDouble(),
      MeasurementType.timed => set.seconds.toDouble(),
    };
    if (!value.isFinite || value < 0) continue;
    if (best == null ||
        (exercise.measurement == MeasurementType.assisted
            ? value < best
            : value > best)) {
      best = value;
    }
  }
  return best;
}

double completedVolume(List<Map<String, dynamic>> sessions) {
  var total = 0.0;
  for (final session in sessions) {
    for (final exercise in asMaps(session['exercises'])) {
      if (MeasurementType.parse(exercise['measurement']) !=
          MeasurementType.weighted) {
        continue;
      }
      for (final set in asMaps(exercise['sets'])) {
        if (set['done'] == true && set['kind'] != 'warmup') {
          total +=
              (set['reps'] as num).toDouble() *
              (set['weight'] as num).toDouble();
        }
      }
    }
  }
  return total;
}
