import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'exercise_picker.dart';

class WorkoutPage extends StatefulWidget {
  final AppController app;
  const WorkoutPage(this.app, {super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  Timer? ticker;
  bool finishing = false;

  Workout get workout => widget.app.active!;

  @override
  void initState() {
    super.initState();
    if (workout.restEnd != null) _startTicker();
  }

  void _startTicker() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final end = widget.app.active?.restEnd;
      if (end != null && DateTime.now().isAfter(end)) {
        widget.app.active?.restEnd = null;
        widget.app.touchActive();
        ticker?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void startRest() {
    workout.restEnd = DateTime.now().toUtc().add(
      Duration(seconds: workout.restSeconds),
    );
    widget.app.touchActive();
    _startTicker();
    setState(() {});
  }

  void _changeRestSeconds(int delta) {
    workout.restSeconds = (workout.restSeconds + delta).clamp(15, 300);
    widget.app.touchActive();
    setState(() {});
  }

  WorkoutExercise? _previous(String exerciseId) => widget.app.sessions
      .expand((s) => s.exercises)
      .where(
        (e) =>
            e.exerciseId == exerciseId &&
            e.sets.any((s) => s.done && s.kind == 'work'),
      )
      .firstOrNull;

  Future<void> _finish() async {
    setState(() => finishing = true);
    try {
      final done = workout.exercises.expand((e) => e.sets).where((s) => s.done);
      final invalid = done.any(
        (s) =>
            s.reps < 1 ||
            s.weight < 0 ||
            (s.rir != null && (s.rir! < 0 || s.rir! > 10)),
      );
      if (invalid) {
        toast(context, 'Oprav opakování, váhu nebo RIR u dokončené série.');
        return;
      }
      if (!workout.exercises.any(
        (exercise) => exercise.workSets.any((set) => set.done),
      )) {
        toast(
          context,
          'Zapiš alespoň jednu pracovní sérii, nebo trénink zruš.',
        );
        return;
      }
      final incomplete = workout.exercises
          .expand((e) => e.workSets)
          .any((s) => !s.done);
      if (incomplete &&
          !await confirmDialog(
            context,
            title: 'Nedokončené série',
            body: 'Dokončit trénink i s nedokončenými sériemi?',
            confirmLabel: 'Dokončit',
          )) {
        return;
      }
      await widget.app.finish();
      if (mounted) toast(context, 'Trénink uložen. Návrhy najdeš v historii.');
    } catch (error) {
      if (mounted) toast(context, 'Trénink se nepodařilo dokončit: $error');
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  Future<void> _discard() async {
    if (await confirmDialog(
      context,
      title: 'Zrušit trénink?',
      body: 'Rozepsaný trénink se smaže a do historie se nezapíše.',
      confirmLabel: 'Zrušit trénink',
    )) {
      await widget.app.discardActive();
    }
  }

  Future<void> _addExercise() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ExercisePicker(app: widget.app)),
    );
    if (id == null || !mounted) return;
    try {
      await widget.app.addExerciseToActive(id);
    } on StateError catch (error) {
      if (mounted) toast(context, error.message);
    } catch (_) {
      if (mounted) {
        toast(context, 'Cvik zatím není uložený. Zkus uložení znovu.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final w = app.active;
    if (w == null) return const Center(child: Text('Žádný aktivní trénink'));
    final remaining = w.restEnd?.difference(DateTime.now()).inSeconds ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(w.planName, style: Theme.of(context).textTheme.headlineSmall),
        Text('Začátek: ${formatTime(w.startedAt)}'),
        TextFormField(
          key: ValueKey('note-${w.id}'),
          initialValue: w.note,
          maxLines: 2,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Poznámka k tréninku'),
          onChanged: (value) {
            w.note = value;
            app.touchActive();
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    remaining > 0
                        ? 'Odpočinek ${remaining}s'
                        : 'Čas na další sérii',
                  ),
                ),
                IconButton(
                  tooltip: 'Kratší pauza',
                  onPressed: () => _changeRestSeconds(-15),
                  icon: const Icon(Icons.remove),
                ),
                Text('${w.restSeconds}s'),
                IconButton(
                  tooltip: 'Delší pauza',
                  onPressed: () => _changeRestSeconds(15),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Spustit pauzu',
                  onPressed: startRest,
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        ),
        for (final exercise in w.exercises)
          _ExerciseCard(
            key: ValueKey(
              '${w.id}-${exercise.planExerciseId ?? exercise.exerciseId}',
            ),
            app: app,
            exercise: exercise,
            previous: _previous(exercise.exerciseId),
            onSetDone: startRest,
          ),
        OutlinedButton.icon(
          onPressed: finishing ? null : _addExercise,
          icon: const Icon(Icons.add),
          label: const Text('Přidat cvik do tréninku'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: finishing ? null : _finish,
          icon: const Icon(Icons.check),
          label: const Text('Dokončit trénink'),
        ),
        TextButton.icon(
          onPressed: finishing ? null : _discard,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Zrušit trénink'),
        ),
      ],
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  final AppController app;
  final WorkoutExercise exercise;
  final WorkoutExercise? previous;
  final VoidCallback onSetDone;
  const _ExerciseCard({
    super.key,
    required this.app,
    required this.exercise,
    required this.previous,
    required this.onSetDone,
  });

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final exercise = widget.exercise;
    final previous = widget.previous;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exerciseName(exercise.exerciseId, app.customExercises),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              previous == null
                  ? 'První záznam'
                  : 'Minule: ${previous.workSets.where((s) => s.done).map((s) => '${fmtNum(s.weight)} kg × ${s.reps}').join(' · ')}',
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: exercise.note,
              decoration: const InputDecoration(labelText: 'Poznámka ke cviku'),
              onChanged: (v) {
                exercise.note = v;
                app.touchActive();
              },
            ),
            const SizedBox(height: 4),
            for (var j = 0; j < exercise.sets.length; j++)
              SetRow(
                key: ObjectKey(exercise.sets[j]),
                index: j,
                set: exercise.sets[j],
                showRir: app.mode != 'Simple',
                onChanged: app.touchActive,
                onDone: (done) {
                  setState(() => exercise.sets[j].done = done);
                  app.touchActive();
                  if (done) widget.onSetDone();
                },
                onRemove:
                    exercise.sets[j].kind == 'work' &&
                        exercise.workSets.length <= 1
                    ? null
                    : () {
                        setState(() => exercise.sets.removeAt(j));
                        app.touchActive();
                      },
              ),
            TextButton.icon(
              onPressed: () {
                final lastWork = exercise.workSets.lastOrNull;
                setState(
                  () => exercise.sets.add(
                    WorkoutSet(
                      target: lastWork?.target ?? 10,
                      reps: lastWork?.target ?? 10,
                      weight: lastWork?.weight ?? 0,
                    ),
                  ),
                );
                app.touchActive();
              },
              icon: const Icon(Icons.add),
              label: const Text('Přidat pracovní sérii'),
            ),
          ],
        ),
      ),
    );
  }
}

class SetRow extends StatelessWidget {
  final int index;
  final WorkoutSet set;
  final bool showRir;
  final VoidCallback onChanged;
  final ValueChanged<bool> onDone;
  final VoidCallback? onRemove;
  const SetRow({
    super.key,
    required this.index,
    required this.set,
    required this.showRir,
    required this.onChanged,
    required this.onDone,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                set.kind == 'warmup'
                    ? 'R ${index + 1}'
                    : '${index + 1}. / ${set.target}',
              ),
            ),
            Expanded(
              child: TextFormField(
                initialValue: fmtNum(set.weight),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'kg'),
                onChanged: (v) {
                  set.weight = parseNum(v) ?? 0;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 68,
              child: TextFormField(
                initialValue: '${set.reps}',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'reps'),
                onChanged: (v) {
                  set.reps = int.tryParse(v) ?? 0;
                  onChanged();
                },
              ),
            ),
            Semantics(
              label: 'Dokončeno série ${index + 1}',
              child: Checkbox(
                value: set.done,
                onChanged: (value) => onDone(value == true),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const SizedBox(width: 52),
            if (showRir)
              SizedBox(
                width: 64,
                child: TextFormField(
                  initialValue: set.rir?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'RIR'),
                  onChanged: (v) {
                    set.rir = int.tryParse(v);
                    onChanged();
                  },
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Odebrat sérii',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    ),
  );
}
