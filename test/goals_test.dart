import 'package:athlete_os/goals.dart';
import 'package:athlete_os/models.dart';
import 'package:flutter_test/flutter_test.dart';

Workout _workout(DateTime day, {double weight = 60}) => Workout(
  id: '$day',
  planName: 'Plán',
  startedAt: day,
  finishedAt: day,
  exercises: [
    WorkoutExercise(
      exerciseId: 'squat',
      sets: [WorkoutSet(target: 5, reps: 5, weight: weight, done: true)],
    ),
  ],
);

void main() {
  // Saturday; the week started on Monday 19. 10.
  final now = DateTime(2026, 10, 24, 18);

  test('regularity counts this week and the weekly streak', () {
    final summary = goalSummary('Pravidelný pohyb', [
      _workout(DateTime(2026, 10, 20)),
      _workout(DateTime(2026, 10, 22)),
      _workout(DateTime(2026, 10, 14)),
      _workout(DateTime(2026, 10, 6)),
      _workout(DateTime(2026, 9, 22)), // gap week 28. 9. breaks the streak
    ], now);
    expect(summary.value, '2 tréninky tento týden');
    expect(summary.detail, 'Trénuješ 3 týdny v řadě.');
  });

  test('regularity streak survives an empty current week', () {
    final summary = goalSummary('Pravidelný pohyb', [
      _workout(DateTime(2026, 10, 15)),
    ], now);
    expect(summary.value, '0 tréninků tento týden');
    expect(summary.detail, 'Trénuješ 1 týden v řadě.');
  });

  test('consistency averages the last 28 days and reports the gap', () {
    final summary = goalSummary('Udržet kondici', [
      _workout(DateTime(2026, 10, 21)),
      _workout(DateTime(2026, 10, 10)),
      _workout(DateTime(2026, 9, 1)), // outside the window
    ], now);
    expect(summary.value, 'Ø 0,5 tréninku týdně');
    expect(summary.detail, 'Poslední trénink byl před 3 dny.');
  });

  test('consistency uses whole-number plurals and survives DST', () {
    // Clocks moved forward on 29. 3. 2026 in Prague.
    final summary = goalSummary('Udržet kondici', [
      for (final day in [3, 10, 17, 24, 29]) _workout(DateTime(2026, 3, day)),
      _workout(DateTime(2026, 3, 29, 1)),
      _workout(DateTime(2026, 3, 29, 2)),
      _workout(DateTime(2026, 3, 29, 3)),
    ], DateTime(2026, 3, 30, 0, 30));
    expect(summary.value, 'Ø 2 tréninky týdně');
    expect(summary.detail, 'Poslední trénink byl včera.');
  });

  test('strength counts weight records beaten in the last 28 days', () {
    final summary = goalSummary('Síla a svaly', [
      _workout(DateTime(2026, 8, 1), weight: 60),
      _workout(DateTime(2026, 8, 20), weight: 70), // record, but too old
      _workout(DateTime(2026, 10, 5), weight: 65),
      _workout(DateTime(2026, 10, 12), weight: 72.5),
      _workout(DateTime(2026, 10, 19), weight: 75),
    ], now);
    expect(summary.value, '2 osobní rekordy');
  });

  test('a first workout is not a record and unknown goal falls back', () {
    final summary = goalSummary('něco jiného', [
      _workout(DateTime(2026, 10, 20)),
    ], now);
    expect(summary.value, '0 osobních rekordů');
    expect(
      goalSummary('Udržet kondici', [], now).detail,
      'Zatím žádný trénink.',
    );
  });
}
