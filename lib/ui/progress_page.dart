import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../progression.dart';
import 'common.dart';

class ProgressPage extends StatefulWidget {
  final AppController app;
  const ProgressPage(this.app, {super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ids = app.sessions
        .expand((s) => s.exercises)
        .map((e) => e.exerciseId)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const Center(child: Text('Grafy se objeví po prvním tréninku.'));
    }
    selected = ids.contains(selected) ? selected : ids.first;
    final points = <FlSpot>[];
    double bestWeight = 0;
    double bestE1rm = 0;
    final ordered = [...app.sessions]
      ..sort(
        (a, b) => (a.finishedAt ?? a.startedAt).compareTo(
          b.finishedAt ?? b.startedAt,
        ),
      );
    for (final session in ordered) {
      final matching = session.exercises.where((e) => e.exerciseId == selected);
      if (matching.isEmpty) continue;
      double maxWeight = 0;
      for (final set in matching.first.sets.where((s) => s.done)) {
        if (set.weight > maxWeight) maxWeight = set.weight;
        if (set.weight > bestWeight) bestWeight = set.weight;
        final estimate = estimatedOneRepMax(set.weight, set.reps);
        if (estimate != null && estimate > bestE1rm) bestE1rm = estimate;
      }
      points.add(FlSpot(points.length.toDouble(), maxWeight));
    }
    final muscles = <String, int>{};
    for (final session in app.sessions) {
      for (final exercise in session.exercises) {
        final muscle = exerciseMuscle(exercise.exerciseId, app.customExercises);
        muscles[muscle] =
            (muscles[muscle] ?? 0) + exercise.sets.where((s) => s.done).length;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Cvik'),
          items: ids
              .map(
                (id) => DropdownMenuItem(
                  value: id,
                  child: Text(exerciseName(id, app.customExercises)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => selected = v),
        ),
        const SizedBox(height: 20),
        Text(
          'Nejvyšší dokončená váha',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${fmtNum(bestWeight)} kg',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minY: 0,
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: false,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        if (app.mode == 'Advanced') ...[
          const SizedBox(height: 22),
          Text('Pokročilé metriky', style: Theme.of(context).textTheme.titleLarge),
          Text(
            'Celkový objem dokončených sérií: ${completedVolume(app.sessions.map((s) => s.toJson()).toList()).toStringAsFixed(0)} kg × opakování',
          ),
          Text(
            'Nejvyšší odhad 1RM: ${bestE1rm.toStringAsFixed(1)} kg (Epley, 1–10 opakování)',
          ),
          const SizedBox(height: 12),
          Text(
            'Dokončené série podle primární skupiny',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final entry in muscles.entries) Text('${entry.key}: ${entry.value}'),
        ],
      ],
    );
  }
}
