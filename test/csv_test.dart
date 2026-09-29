import 'package:athlete_os/csv_export.dart';
import 'package:athlete_os/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV has header, escapes text and lists every set', () {
    final workout = Workout(
      id: 'w',
      planName: 'Push, "A"',
      startedAt: DateTime.utc(2026, 9, 1, 10),
      finishedAt: DateTime.utc(2026, 9, 1, 11),
      exercises: [
        WorkoutExercise(
          exerciseId: 'bench',
          sets: [
            WorkoutSet(
              target: 8,
              reps: 8,
              weight: 60,
              done: true,
              kind: 'warmup',
            ),
            WorkoutSet(target: 8, reps: 7, weight: 80, rir: 2, done: true),
          ],
        ),
      ],
    );
    final lines = sessionsToCsv([workout], (id) => 'Bench').split('\r\n');
    expect(lines.length, 3);
    expect(lines.first.startsWith('date,workout,exercise'), isTrue);
    expect(lines[1], contains('"Push, ""A"""'));
    expect(lines[1], contains(',warmup,'));
    expect(lines[2], contains(',80.0,2,1,'));
  });
}
