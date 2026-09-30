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
  MeasurementType? selectedMeasurement;

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
    final availableTypes = app.sessions
        .expand((s) => s.exercises)
        .where((e) => e.exerciseId == selected)
        .map((e) => e.measurement)
        .toSet()
        .toList();
    if (!availableTypes.contains(selectedMeasurement)) {
      selectedMeasurement = availableTypes.first;
    }
    final measurement = selectedMeasurement!;
    final points = <FlSpot>[];
    double? bestValue;
    double bestE1rm = 0;
    final ordered = [...app.sessions]
      ..sort(
        (a, b) => (a.finishedAt ?? a.startedAt).compareTo(
          b.finishedAt ?? b.startedAt,
        ),
      );
    for (final session in ordered) {
      final matching = session.exercises.where(
        (e) => e.exerciseId == selected && e.measurement == measurement,
      );
      double? sessionBest;
      for (final exercise in matching) {
        final value = bestCompletedMeasurement(exercise);
        if (value == null) continue;
        if (sessionBest == null ||
            (measurement == MeasurementType.assisted
                ? value < sessionBest
                : value > sessionBest)) {
          sessionBest = value;
        }
        if (bestValue == null ||
            (measurement == MeasurementType.assisted
                ? value < bestValue
                : value > bestValue)) {
          bestValue = value;
        }
        if (measurement == MeasurementType.weighted) {
          for (final set in exercise.workSets.where((s) => s.done)) {
            final estimate = estimatedOneRepMax(set.weight, set.reps);
            if (estimate != null && estimate > bestE1rm) bestE1rm = estimate;
          }
        }
      }
      if (sessionBest != null) {
        points.add(FlSpot(points.length.toDouble(), sessionBest));
      }
    }
    final metricLabel = switch (measurement) {
      MeasurementType.weighted => 'Nejvyšší dokončená váha',
      MeasurementType.bodyweight => 'Nejvíce opakování v sérii',
      MeasurementType.assisted => 'Nejnižší dopomoc (nižší je lepší)',
      MeasurementType.timed => 'Nejdelší dokončená série',
    };
    final unit = switch (measurement) {
      MeasurementType.weighted || MeasurementType.assisted => 'kg',
      MeasurementType.bodyweight => 'opakování',
      MeasurementType.timed => 's',
    };
    final muscles = <String, int>{};
    for (final session in app.sessions) {
      for (final exercise in session.exercises) {
        final muscle = exerciseMuscle(exercise.exerciseId, app.customExercises);
        muscles[muscle] =
            (muscles[muscle] ?? 0) +
            exercise.workSets.where((s) => s.done).length;
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
        if (availableTypes.length > 1)
          DropdownButtonFormField<MeasurementType>(
            key: ValueKey('$selected-$measurement'),
            initialValue: measurement,
            decoration: const InputDecoration(
              labelText: 'Typ měření (historie se neslučuje)',
            ),
            items: availableTypes
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (m) => setState(() => selectedMeasurement = m),
          ),
        const SizedBox(height: 20),
        Text(metricLabel, style: Theme.of(context).textTheme.titleMedium),
        Text(
          bestValue == null
              ? 'Žádná dokončená série'
              : '${fmtNum(bestValue)} $unit',
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
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
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
          Text(
            'Pokročilé metriky',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Objem sérií s váhou: ${completedVolume(app.sessions.map((s) => s.toJson()).toList()).toStringAsFixed(0)} kg × opakování',
          ),
          if (measurement == MeasurementType.weighted)
            Text(
              'Nejvyšší odhad 1RM: ${bestE1rm.toStringAsFixed(1)} kg (Epley, 1–10 opakování)',
            ),
          const SizedBox(height: 12),
          Text(
            'Dokončené série podle primární skupiny',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final entry in muscles.entries)
            Text('${entry.key}: ${entry.value}'),
        ],
      ],
    );
  }
}
