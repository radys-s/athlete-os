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
  final targets = (exercise['targets'] as List<dynamic>).cast<num>();
  final currentWeight = (exercise['weight'] as num).toDouble();
  final step = (exercise['step'] as num).toDouble();
  if (currentWeight <= 0) {
    return const ProgressionResult(
      false,
      'Pro návrh vyšší váhy nejdřív nastav výchozí váhu cviku v plánu.',
      0,
    );
  }
  if (performed.length != targets.length ||
      performed.any((set) => set['done'] != true)) {
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
    if ((performed[i]['reps'] as num) < targets[i]) {
      return ProgressionResult(
        false,
        'Série ${i + 1}: ${performed[i]['reps']} z cílových ${targets[i]} opakování. Ponechat současný cíl.',
        currentWeight,
      );
    }
  }
  return ProgressionResult(
    true,
    'Splnil jsi všech ${targets.length} cílových sérií. Pravidlo navrhuje přidat ${step.toStringAsFixed(1)} kg.',
    currentWeight + step,
  );
}

double? estimatedOneRepMax(double weight, int reps) {
  if (weight <= 0 || reps < 1 || reps > 10) return null;
  return weight * (1 + reps / 30);
}

double completedVolume(List<Map<String, dynamic>> sessions) {
  var total = 0.0;
  for (final session in sessions) {
    for (final exercise in asMaps(session['exercises'])) {
      for (final set in asMaps(exercise['sets'])) {
        if (set['done'] == true) {
          total +=
              (set['reps'] as num).toDouble() *
              (set['weight'] as num).toDouble();
        }
      }
    }
  }
  return total;
}
