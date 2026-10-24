import 'models.dart';
import 'progression.dart';

/// Main goals offered in onboarding and settings. Stored as the label itself.
const goals = ['Síla a svaly', 'Pravidelný pohyb', 'Udržet kondici'];

/// One headline for the Progress page, worded for the chosen goal.
class GoalSummary {
  final String title;
  final String value;
  final String detail;
  const GoalSummary(this.title, this.value, this.detail);
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime _weekStart(DateTime t) {
  final d = _day(t);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

DateTime _when(Workout w) => w.finishedAt ?? w.startedAt;

GoalSummary goalSummary(String goal, List<Workout> sessions, DateTime now) {
  final ordered = [...sessions]..sort((a, b) => _when(a).compareTo(_when(b)));
  final today = _day(now);
  final monthAgo = DateTime(today.year, today.month, today.day - 27);
  return switch (goal) {
    'Pravidelný pohyb' => _regularity(ordered, now),
    'Udržet kondici' => _consistency(ordered, today, monthAgo),
    _ => _strength(ordered, monthAgo),
  };
}

/// Workouts this week and how many weeks in a row had at least one.
GoalSummary _regularity(List<Workout> ordered, DateTime now) {
  final weeks = ordered.map((w) => _weekStart(_when(w))).toSet();
  final current = _weekStart(now);
  final thisWeek = ordered.where((w) => _weekStart(_when(w)) == current).length;
  // A streak still counts while the current week has no workout yet.
  var week = weeks.contains(current)
      ? current
      : DateTime(current.year, current.month, current.day - 7);
  var streak = 0;
  while (weeks.contains(week)) {
    streak++;
    week = DateTime(week.year, week.month, week.day - 7);
  }
  return GoalSummary(
    'Pravidelný pohyb',
    '${czechCount(thisWeek, 'trénink', 'tréninky', 'tréninků')} tento týden',
    streak == 0
        ? 'Jeden trénink týdně stačí, aby série začala.'
        : 'Trénuješ ${czechCount(streak, 'týden', 'týdny', 'týdnů')} v řadě.',
  );
}

/// Average workouts per week over the last 28 days and the gap since the last.
GoalSummary _consistency(
  List<Workout> ordered,
  DateTime today,
  DateTime monthAgo,
) {
  final recent = ordered.where((w) => !_day(_when(w)).isBefore(monthAgo));
  final perWeek = recent.length / 4;
  final String detail;
  if (ordered.isEmpty) {
    detail = 'Zatím žádný trénink.';
  } else {
    // Whole calendar days; UTC dates keep a DST change from shortening one.
    final last = _day(_when(ordered.last));
    final gap = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
    detail = switch (gap) {
      <= 0 => 'Poslední trénink byl dnes.',
      1 => 'Poslední trénink byl včera.',
      _ => 'Poslední trénink byl před $gap dny.',
    };
  }
  return GoalSummary(
    'Udržet kondici · posledních 28 dní',
    // "2 tréninky" for whole numbers, genitive "0,5 tréninku" otherwise.
    perWeek % 1 == 0
        ? 'Ø ${czechCount(perWeek.round(), 'trénink', 'tréninky', 'tréninků')} týdně'
        : 'Ø ${formatNumber(perWeek)} tréninku týdně',
    detail,
  );
}

/// Exercises whose best completed weight was beaten in the last 28 days.
GoalSummary _strength(List<Workout> ordered, DateTime monthAgo) {
  final best = <String, double>{};
  var records = 0;
  for (final session in ordered) {
    final recent = !_day(_when(session)).isBefore(monthAgo);
    final beaten = <String>{};
    for (final exercise in session.exercises) {
      if (exercise.measurement != MeasurementType.weighted) continue;
      final value = bestCompletedMeasurement(exercise);
      if (value == null) continue;
      final previous = best[exercise.exerciseId];
      if (previous == null || value > previous) {
        best[exercise.exerciseId] = value;
        if (previous != null && recent) beaten.add(exercise.exerciseId);
      }
    }
    records += beaten.length;
  }
  return GoalSummary(
    'Síla a svaly · posledních 28 dní',
    czechCount(records, 'osobní rekord', 'osobní rekordy', 'osobních rekordů'),
    records == 0
        ? 'Rekord je, když překonáš svou nejvyšší dokončenou váhu.'
        : 'Překonaná nejvyšší dokončená váha u cviku.',
  );
}
