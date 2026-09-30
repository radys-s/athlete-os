import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'workout_page.dart';

/// Úprava dokončeného tréninku. Pracuje s kopií; uloží se až tlačítkem.
class HistoryDetailPage extends StatefulWidget {
  final AppController app;
  final Workout session;
  const HistoryDetailPage({
    required this.app,
    required this.session,
    super.key,
  });

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  late final Workout draft = widget.session.copy();
  late final TextEditingController note = TextEditingController(
    text: draft.note,
  );
  bool saving = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    draft.note = note.text.trim();
    try {
      await widget.app.saveEditedSession(draft);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, 'Uložení se nezdařilo: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: Text(draft.planName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Text(formatDateTime(draft.finishedAt ?? draft.startedAt)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Poznámka k tréninku'),
          ),
          const SizedBox(height: 12),
          for (final exercise in draft.exercises)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exerciseName(exercise.exerciseId, app.customExercises),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextFormField(
                      initialValue: exercise.note,
                      decoration: const InputDecoration(
                        labelText: 'Poznámka ke cviku',
                      ),
                      onChanged: (v) => exercise.note = v,
                    ),
                    for (var j = 0; j < exercise.sets.length; j++)
                      SetRow(
                        key: ObjectKey(exercise.sets[j]),
                        index: j,
                        set: exercise.sets[j],
                        measurement: exercise.measurement,
                        showRir: app.mode != 'Simple',
                        onChanged: () {},
                        onDone: (done) =>
                            setState(() => exercise.sets[j].done = done),
                        onRemove: () =>
                            setState(() => exercise.sets.removeAt(j)),
                      ),
                    TextButton.icon(
                      onPressed: () {
                        final last = exercise.workSets.lastOrNull;
                        setState(
                          () => exercise.sets.add(
                            WorkoutSet(
                              target: last?.target ?? 10,
                              reps:
                                  exercise.measurement == MeasurementType.timed
                                  ? 0
                                  : last?.reps ?? 10,
                              seconds:
                                  exercise.measurement == MeasurementType.timed
                                  ? last?.seconds ?? 30
                                  : 0,
                              weight: last?.weight ?? 0,
                              done: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Přidat sérii'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Ukládám…' : 'Uložit změny'),
          ),
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Zahodit změny'),
          ),
        ],
      ),
    );
  }
}
