import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../supersets.dart';
import '../workout_controls.dart';
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

  WorkoutExercise? _previous(WorkoutExercise current) => widget.app.sessions
      .expand((s) => s.exercises)
      .where(
        (e) =>
            e.exerciseId == current.exerciseId &&
            e.measurement == current.measurement &&
            e.sets.any((s) => s.done && s.kind == 'work'),
      )
      .firstOrNull;

  Future<void> _finish() async {
    setState(() => finishing = true);
    try {
      final error = workout.validateCompleted();
      if (error != null) {
        toast(context, error);
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

  Future<void> _editExercise(WorkoutExercise exercise, String action) async {
    try {
      if (action == 'replace') {
        if (exercise.sets.any((set) => set.done)) {
          toast(
            context,
            'Cvik má dokončené série. Alternativu přidej jako nový cvik.',
          );
          return;
        }
        final id = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => ExercisePicker(app: widget.app)),
        );
        if (id == null || !mounted) return;
        await widget.app.replaceActiveExercise(exercise, id);
      } else if (action == 'remove') {
        final hasCompleted = exercise.sets.any((set) => set.done);
        if (hasCompleted &&
            !await confirmDialog(
              context,
              title: 'Odebrat cvik i se sériemi?',
              body: 'Dokončené série tohoto cviku se smažou z rozepsaného tréninku.',
              confirmLabel: 'Odebrat cvik',
            )) {
          return;
        }
        if (!mounted) return;
        await widget.app.removeActiveExercise(
          exercise,
          discardCompletedSets: hasCompleted,
        );
      } else {
        await widget.app.moveActiveExercise(exercise, action == 'up' ? -1 : 1);
      }
    } on StateError catch (error) {
      if (mounted) toast(context, error.message);
    } catch (_) {
      if (mounted) toast(context, 'Změna čeká na uložení. Zkus uložení znovu.');
    } finally {
      if (mounted) setState(() {});
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
            previous: _previous(exercise),
            onSetDone: () {
              if (shouldRestAfterSet(w, exercise)) startRest();
            },
            onAction: finishing
                ? null
                : (action) => _editExercise(exercise, action),
            canMoveUp: w.exercises.first != exercise,
            canMoveDown: w.exercises.last != exercise,
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
  final ValueChanged<String>? onAction;
  final bool canMoveUp;
  final bool canMoveDown;
  const _ExerciseCard({
    super.key,
    required this.app,
    required this.exercise,
    required this.previous,
    required this.onSetDone,
    required this.onAction,
    required this.canMoveUp,
    required this.canMoveDown,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    exerciseName(exercise.exerciseId, app.customExercises),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('controls-${exercise.exerciseId}'),
                  tooltip: 'Upravit cvik v tréninku',
                  enabled: widget.onAction != null,
                  onSelected: widget.onAction,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'replace',
                      child: Text('Nahradit cvik'),
                    ),
                    PopupMenuItem(
                      value: 'up',
                      enabled: widget.canMoveUp,
                      child: const Text('Posunout nahoru'),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: widget.canMoveDown,
                      child: const Text('Posunout dolů'),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Odebrat cvik'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              previous == null
                  ? 'První záznam'
                  : 'Minule: ${previous.workSets.where((s) => s.done).map((s) => setMeasurementLabel(s, exercise.measurement)).join(' · ')}',
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
                measurement: exercise.measurement,
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
                      reps: exercise.measurement == MeasurementType.timed
                          ? 0
                          : lastWork?.target ?? 10,
                      seconds: exercise.measurement == MeasurementType.timed
                          ? lastWork?.target ?? 30
                          : 0,
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

class SetRow extends StatefulWidget {
  final int index;
  final MeasurementType measurement;
  final WorkoutSet set;
  final bool showRir;
  final VoidCallback onChanged;
  final ValueChanged<bool> onDone;
  final VoidCallback? onRemove;
  const SetRow({
    super.key,
    required this.index,
    this.measurement = MeasurementType.weighted,
    required this.set,
    required this.showRir,
    required this.onChanged,
    required this.onDone,
    required this.onRemove,
  });

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late String weightText = fmtNum(widget.set.weight);
  late String repsText = '${widget.set.reps}';
  late String secondsText = '${widget.set.seconds}';
  late String rirText = widget.set.rir?.toString() ?? '';
  bool validate = false;

  String? get weightError {
    if (widget.measurement == MeasurementType.bodyweight &&
        weightText.trim().isEmpty) {
      return null;
    }
    final value = parseNum(weightText);
    return value == null || !value.isFinite || value < 0
        ? 'Zadej váhu ≥ 0'
        : null;
  }

  String? get repsError {
    final value = int.tryParse(repsText);
    return value == null || value < 1 ? 'Alespoň 1' : null;
  }

  String? get rirError {
    if (rirText.trim().isEmpty) return null;
    final value = int.tryParse(rirText);
    return value == null || value < 0 || value > 10 ? 'RIR 0 až 10' : null;
  }

  String? get secondsError =>
      (int.tryParse(secondsText) ?? 0) < 1 ? 'Alespoň 1 s' : null;
  bool get valid => widget.measurement == MeasurementType.timed
      ? secondsError == null
      : weightError == null && repsError == null && rirError == null;

  void edited() {
    setState(() => validate = true);
    if (!valid && widget.set.done) widget.onDone(false);
    widget.onChanged();
  }

  void toggleDone(bool done) {
    setState(() => validate = true);
    if (!done || valid) widget.onDone(done);
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final index = widget.index;
    return Padding(
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
              if (widget.measurement != MeasurementType.timed)
                Expanded(
                  child: TextFormField(
                    initialValue: weightText,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: widget.measurement.weightLabel,
                      errorText: validate ? weightError : null,
                    ),
                    onChanged: (v) {
                      weightText = v;
                      final value = parseNum(v);
                      set.weight = value != null && value.isFinite ? value : 0;
                      edited();
                    },
                  ),
                ),
              const SizedBox(width: 8),
              SizedBox(
                width: 68,
                child: TextFormField(
                  initialValue: widget.measurement == MeasurementType.timed
                      ? secondsText
                      : repsText,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.measurement == MeasurementType.timed
                        ? 'sekundy'
                        : 'reps',
                    errorText: validate
                        ? (widget.measurement == MeasurementType.timed
                              ? secondsError
                              : repsError)
                        : null,
                  ),
                  onChanged: (v) {
                    if (widget.measurement == MeasurementType.timed) {
                      secondsText = v;
                      set.seconds = int.tryParse(v) ?? 0;
                    } else {
                      repsText = v;
                      set.reps = int.tryParse(v) ?? 0;
                    }
                    edited();
                  },
                ),
              ),
              Semantics(
                label: 'Dokončeno série ${index + 1}',
                child: Checkbox(
                  value: set.done,
                  onChanged: (value) => toggleDone(value == true),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 52),
              if (widget.showRir && widget.measurement != MeasurementType.timed)
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    initialValue: rirText,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'RIR',
                      errorText: validate ? rirError : null,
                    ),
                    onChanged: (v) {
                      rirText = v;
                      set.rir = int.tryParse(v);
                      edited();
                    },
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Odebrat sérii',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
