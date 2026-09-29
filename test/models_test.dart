import 'package:athlete_os/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy plan without item ids keeps working and round-trips', () {
    final legacy = {
      'id': 'p1',
      'name': 'Legacy',
      'futureField': {'a': 1},
      'exercises': [
        {
          'exerciseId': 'squat',
          'targets': [12, 10, 8],
          'weight': 60,
          'step': 2.5,
          'ruleType': 'fixed',
        },
      ],
    };
    final plan = Plan.fromJson(legacy);
    expect(plan.exercises.single.id, 'squat');
    expect(plan.exercises.single.weight, 60.0);
    final json = plan.toJson();
    expect(json['futureField'], {'a': 1});
    expect(Plan.fromJson(json).toJson(), json);
  });

  test('legacy session links rule to the plan item by exercise id', () {
    final session = Workout.fromJson({
      'id': 's1',
      'planId': 'p1',
      'planName': 'Legacy',
      'startedAt': '2026-09-20T10:00:00Z',
      'finishedAt': '2026-09-20T11:00:00Z',
      'exercises': [
        {
          'exerciseId': 'squat',
          'targets': [12],
          'rule': {'exerciseId': 'squat', 'weight': 60, 'step': 2.5, 'targets': [12]},
          'sets': [
            {'target': 12, 'reps': 12, 'weight': 60, 'rir': null, 'done': true},
          ],
        },
      ],
      'proposals': [
        {
          'id': 'x',
          'exerciseId': 'squat',
          'planId': 'p1',
          'currentWeight': 60,
          'ruleWeight': 60,
          'suggestedWeight': 62.5,
          'eligible': true,
          'reason': 'ok',
          'status': 'pending',
        },
      ],
    });
    expect(session.exercises.single.planExerciseId, 'squat');
    expect(session.exercises.single.bestDoneWeight, 60);
    expect(session.proposals.single.planExerciseId, isNull);
    expect(session.proposals.single.statusLabel, 'Čeká na rozhodnutí');
  });

  test('plan validation reports the first problem', () {
    final plan = Plan(id: 'p', name: ' ');
    expect(plan.validate(), 'Doplň název plánu.');
    plan.name = 'A';
    expect(plan.validate(), 'Přidej alespoň jeden cvik.');
    plan.exercises.add(
      PlanExercise(id: 'i', exerciseId: 'x', ruleType: 'repRange', rangeMin: 10, rangeMax: 8),
    );
    expect(plan.validate(), 'Rozsah opakování je neplatný.');
  });
}
