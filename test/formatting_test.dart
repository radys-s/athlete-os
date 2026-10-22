import 'package:athlete_os/models.dart';
import 'package:athlete_os/ui/workout_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatNumber uses Czech comma and trims noise', () {
    expect(formatNumber(42.5), '42,5');
    expect(formatNumber(40.0), '40');
    expect(formatNumber(1.25), '1,25');
    expect(formatNumber(20.200000000000003), '20,2');
    expect(formatNumber(double.nan), '–');
  });

  test('czechCount picks the right plural', () {
    expect(czechCount(1, 'cvik', 'cviky', 'cviků'), '1 cvik');
    expect(czechCount(3, 'cvik', 'cviky', 'cviků'), '3 cviky');
    expect(czechCount(0, 'cvik', 'cviky', 'cviků'), '0 cviků');
    expect(czechCount(12, 'cvik', 'cviky', 'cviků'), '12 cviků');
  });

  test('search ignores diacritics and matches aliases', () {
    final squat = {'name': 'Back squat', 'aliases': 'dřep s činkou, dřepy'};
    expect(exerciseMatches(squat, 'drep'), isTrue);
    expect(exerciseMatches(squat, 'DŘEP činkou'), isTrue);
    expect(exerciseMatches(squat, 'bench'), isFalse);
  });

  test('work sets are numbered without warm-ups', () {
    final sets = [
      WorkoutSet(target: 8, reps: 8, weight: 0, kind: 'warmup'),
      WorkoutSet(target: 8, reps: 8, weight: 0, kind: 'warmup'),
      WorkoutSet(target: 8, reps: 8, weight: 0),
      WorkoutSet(target: 8, reps: 8, weight: 0),
    ];
    expect(setNumber(sets, 1), 2);
    expect(setNumber(sets, 2), 1);
    expect(setNumber(sets, 3), 2);
  });
}
