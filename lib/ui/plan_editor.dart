import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'exercise_picker.dart';
import 'superset_editor.dart';

class PlanEditor extends StatefulWidget {
  final AppController app;
  final Plan? original;
  const PlanEditor({required this.app, this.original, super.key});

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final Plan plan = widget.original?.copy() ?? Plan.create();
  late final TextEditingController name = TextEditingController(
    text: plan.name,
  );
  late final String _initial = _snapshot();

  /// Plan items whose typed targets could not be parsed.
  final Set<String> _invalidTargets = {};

  String _snapshot() => jsonEncode({...plan.toJson(), 'name': name.text});

  bool get _changed => _snapshot() != _initial;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> addExercise() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ExercisePicker(app: widget.app)),
    );
    if (id == null || !mounted) return;
    if (plan.exercises.any((item) => item.exerciseId == id)) {
      toast(context, 'Cvik už je v tomto plánu.');
      return;
    }
    setState(
      () => plan.exercises.add(
        PlanExercise(
          id: newId(),
          exerciseId: id,
          measurement: exerciseMeasurement(id, widget.app.customExercises),
          targets:
              exerciseMeasurement(id, widget.app.customExercises) ==
                  MeasurementType.timed
              ? [30, 30, 30]
              : null,
        ),
      ),
    );
  }

  void move(int from, int to) => setState(() {
    final moved = plan.exercises.removeAt(from);
    plan.exercises.insert(to, moved);
  });

  bool saving = false;

  Future<void> save() async {
    if (saving) return;
    plan.name = name.text.trim();
    _invalidTargets.retainAll(plan.exercises.map((e) => e.id));
    final error = _invalidTargets.isNotEmpty
        ? 'Oprav cíle sérií – zadej čísla oddělená čárkou.'
        : plan.validate();
    if (error != null) {
      toast(context, error);
      return;
    }
    setState(() => saving = true);
    try {
      await widget.app.savePlan(plan);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        toast(context, 'Plán se nepodařilo uložit: ${errorText(error)}');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = plan.exercises;
    return PopScope(
      // Text fields edit the plan without setState, so canPop cannot track
      // changes; decide on each back gesture instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave =
            saving ||
            !_changed ||
            await confirmDialog(
              context,
              title: 'Zahodit změny?',
              body: 'Úpravy plánu nejsou uložené.',
              confirmLabel: 'Zahodit',
            );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Tréninkový plán')),
        body: AbsorbPointer(
          absorbing: saving,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Název plánu'),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < items.length; i++)
                _ItemEditor(
                  key: ValueKey(items[i].id),
                  item: items[i],
                  title: exerciseName(
                    items[i].exerciseId,
                    widget.app.customExercises,
                  ),
                  onUp: i == 0 ? null : () => move(i, i - 1),
                  onDown: i == items.length - 1 ? null : () => move(i, i + 1),
                  onRemove: () => setState(() {
                    _invalidTargets.remove(items[i].id);
                    items.removeAt(i);
                    dropLoneSupersets([for (final e in items) e.extra]);
                  }),
                  onTargetsValid: (valid) => valid
                      ? _invalidTargets.remove(items[i].id)
                      : _invalidTargets.add(items[i].id),
                ),
              SupersetEditor(
                widget.app,
                plan: plan,
                onChanged: () => setState(() {}),
              ),
              OutlinedButton.icon(
                onPressed: addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Přidat cvik'),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: save, child: const Text('Uložit plán')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemEditor extends StatefulWidget {
  final PlanExercise item;
  final String title;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;
  final ValueChanged<bool> onTargetsValid;
  const _ItemEditor({
    super.key,
    required this.item,
    required this.title,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
    required this.onTargetsValid,
  });

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  PlanExercise get item => widget.item;
  late final weight = TextEditingController(text: fmtNum(item.weight));
  late final step = TextEditingController(text: fmtNum(item.step));
  late final rangeMin = TextEditingController(text: '${item.rangeMin}');
  late final rangeMax = TextEditingController(text: '${item.rangeMax}');
  late final targets = TextEditingController(text: item.targets.join(', '));
  String? targetsError;

  @override
  void dispose() {
    weight.dispose();
    step.dispose();
    rangeMin.dispose();
    rangeMax.dispose();
    targets.dispose();
    super.dispose();
  }

  void _setSeriesCount(int count) => setState(() {
    if (count > item.targets.length) {
      item.targets = [
        ...item.targets,
        ...List.filled(count - item.targets.length, item.targets.last),
      ];
    } else {
      item.targets = item.targets.sublist(0, count);
    }
    targets.text = item.targets.join(', ');
    targetsError = null;
    widget.onTargetsValid(true);
  });

  @override
  Widget build(BuildContext context) {
    final range =
        item.measurement == MeasurementType.weighted &&
        item.ruleType == 'repRange';
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
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Posunout nahoru',
                  onPressed: widget.onUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Posunout dolů',
                  onPressed: widget.onDown,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Odebrat cvik',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(item.measurement.label),
            if (item.measurement != MeasurementType.weighted)
              const Text(
                'Cíle nastav ručně. Automatická progrese váhy se nepoužívá.',
              ),
            if (item.measurement == MeasurementType.weighted)
              DropdownButtonFormField<String>(
                initialValue: item.ruleType,
                decoration: const InputDecoration(
                  labelText: 'Pravidlo progrese',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'fixed',
                    child: Text('Pevné cíle sérií'),
                  ),
                  DropdownMenuItem(
                    value: 'repRange',
                    child: Text('Rozsah opakování'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  item.ruleType = value ?? 'fixed';
                  if (item.ruleType == 'repRange') item.syncTargetsToRange();
                  targets.text = item.targets.join(', ');
                }),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Počet sérií: ${item.targets.length}'),
                IconButton(
                  tooltip: 'Odebrat sérii',
                  onPressed: item.targets.length <= 1
                      ? null
                      : () => _setSeriesCount(item.targets.length - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Přidat sérii',
                  onPressed: item.targets.length >= 12
                      ? null
                      : () => _setSeriesCount(item.targets.length + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Row(
              children: [
                Text('Rozcvičovací série: ${item.warmupSets}'),
                IconButton(
                  tooltip: 'Odebrat rozcvičovací sérii',
                  onPressed: item.warmupSets == 0
                      ? null
                      : () => setState(() => item.warmupSets--),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  tooltip: 'Přidat rozcvičovací sérii',
                  onPressed: item.warmupSets >= 5
                      ? null
                      : () => setState(() => item.warmupSets++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (item.warmupSets > 0)
              Text(
                item.measurement == MeasurementType.weighted
                    ? 'Rozcvičovací váha je jen orientační a lze ji v tréninku změnit.'
                    : 'Rozcvičovací cíle lze v tréninku změnit.',
              ),
            if (range)
              Wrap(
                spacing: 12,
                children: [
                  SizedBox(
                    width: 125,
                    child: TextField(
                      controller: rangeMin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Od opakování',
                      ),
                      onChanged: (v) => item.rangeMin = int.tryParse(v) ?? 0,
                    ),
                  ),
                  SizedBox(
                    width: 125,
                    child: TextField(
                      controller: rangeMax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Do opakování',
                      ),
                      onChanged: (v) {
                        item.rangeMax = int.tryParse(v) ?? 0;
                        if (item.rangeMax >= 1) item.syncTargetsToRange();
                        targets.text = item.targets.join(', ');
                      },
                    ),
                  ),
                ],
              ),
            Wrap(
              spacing: 12,
              children: [
                if (item.measurement != MeasurementType.timed)
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: item.measurement.weightLabel,
                      ),
                      onChanged: (v) => item.weight =
                          item.measurement == MeasurementType.bodyweight &&
                              v.trim().isEmpty
                          ? 0
                          : parseNum(v) ?? double.nan,
                    ),
                  ),
                if (item.measurement == MeasurementType.weighted)
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: step,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Krok (kg)'),
                      onChanged: (v) => item.step = parseNum(v) ?? 0,
                    ),
                  ),
              ],
            ),
            if (!range)
              TextField(
                controller: targets,
                decoration: InputDecoration(
                  labelText: item.measurement == MeasurementType.timed
                      ? 'Cíle sérií v sekundách (např. 30, 30, 30)'
                      : 'Cíle sérií (např. 12, 10, 8)',
                  errorText: targetsError,
                ),
                onChanged: (value) {
                  final parsed = value
                      .split(',')
                      .map((s) => int.tryParse(s.trim()))
                      .toList();
                  final valid =
                      parsed.length <= 12 &&
                      parsed.every((n) => n != null && n > 0);
                  setState(() {
                    if (valid) item.targets = parsed.cast<int>();
                    targetsError = valid
                        ? null
                        : 'Zadej 1 až 12 kladných čísel oddělených čárkou.';
                  });
                  widget.onTargetsValid(valid);
                },
              )
            else
              Text('Cíle: ${item.targets.join(' / ')} opakování'),
          ],
        ),
      ),
    );
  }
}
