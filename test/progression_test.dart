import 'package:athlete_os/progression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final exercise = <String, dynamic>{
    'targets': [12, 10, 8],
    'weight': 40.0,
    'step': 2.5,
  };
  test(
    'offers the configured step only after all target sets are complete',
    () {
      final result = evaluateProgression(exercise, [
        {'done': true, 'reps': 12, 'weight': 40},
        {'done': true, 'reps': 10, 'weight': 40},
        {'done': true, 'reps': 8, 'weight': 40},
      ]);
      expect(result.completed, isTrue);
      expect(result.suggestedWeight, 42.5);
    },
  );
  test('holds the goal when a set is missed or incomplete', () {
    final missed = evaluateProgression(exercise, [
      {'done': true, 'reps': 12, 'weight': 40},
      {'done': true, 'reps': 9, 'weight': 40},
      {'done': true, 'reps': 8, 'weight': 40},
    ]);
    final incomplete = evaluateProgression(exercise, [
      {'done': true, 'reps': 12, 'weight': 40},
      {'done': true, 'reps': 10, 'weight': 40},
      {'done': false, 'reps': 8, 'weight': 40},
    ]);
    expect(missed.completed, isFalse);
    expect(missed.suggestedWeight, 40);
    expect(incomplete.completed, isFalse);
    expect(incomplete.suggestedWeight, 40);
  });
  test(
    'does not recommend a heavier plan after using less than target weight',
    () {
      final result = evaluateProgression(exercise, [
        {'done': true, 'reps': 12, 'weight': 40},
        {'done': true, 'reps': 10, 'weight': 35},
        {'done': true, 'reps': 8, 'weight': 40},
      ]);
      expect(result.completed, isFalse);
      expect(result.suggestedWeight, 40);
    },
  );
  test('does not recommend load when the plan has no starting weight', () {
    final result = evaluateProgression(
      {
        'targets': [12],
        'weight': 0.0,
        'step': 2.5,
      },
      [
        {'done': true, 'reps': 12, 'weight': 0.0},
      ],
    );
    expect(result.completed, isFalse);
    expect(result.suggestedWeight, 0);
  });
  test('one rep max estimate is withheld outside the supported range', () {
    expect(estimatedOneRepMax(100, 5), closeTo(116.67, .01));
    expect(estimatedOneRepMax(100, 15), isNull);
  });
}
