import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'exercise_picker.dart';

class PlanEditor extends StatefulWidget {
  final AppController app;
  final Plan? original;
  const PlanEditor({required this.app, this.original, super.key});

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late final Plan plan = widget.original?.copy() ?? Plan.create();
  late final TextEditingController name = TextEditingController(text: plan.name);

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
    setState(() => plan.exercises.add(PlanExercise(id: newId(), exerciseId: id)));
  }

  void move(int from, int to) => setState(() {
    final moved = plan.exercises.removeAt(from);
    plan.exercises.insert(to, moved);
  });

  Future<void> save() async {
    plan.name = name.text.trim();
    final error = plan.validate();
    if (error != null) {
      toast(context, error);
      return;
    }
    await widget.app.savePlan(plan);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = plan.exercises;
    return Scaffold(
      appBar: AppBar(title: const Text('Tréninkový plán')),
      body: ListView(
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
              title: exerciseName(items[i].exerciseId, widget.app.customExercises),
              onUp: i == 0 ? null : () => move(i, i - 1),
              onDown: i == items.length - 1 ? null : () => move(i, i + 1),
              onRemove: () => setState(() => items.removeAt(i)),
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
    );
  }
}

class _ItemEditor extends StatefulWidget {
  final PlanExercise item;
  final String title;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;
  const _ItemEditor({
    super.key,
    required this.item,
    required this.title,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
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
  });

  @override
  Widget build(BuildContext context) {
    final range = item.ruleType == 'repRange';
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
            DropdownButtonFormField<String>(
              initialValue: item.ruleType,
              decoration: const InputDecoration(labelText: 'Pravidlo progrese'),
              items: const [
                DropdownMenuItem(value: 'fixed', child: Text('Pevné cíle sérií')),
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
            if (range)
              Wrap(
                spacing: 12,
                children: [
                  SizedBox(
                    width: 125,
                    child: TextField(
                      controller: rangeMin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Od opakování'),
                      onChanged: (v) => item.rangeMin = int.tryParse(v) ?? 0,
                    ),
                  ),
                  SizedBox(
                    width: 125,
                    child: TextField(
                      controller: rangeMax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Do opakování'),
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
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Váha (kg)'),
                    onChanged: (v) => item.weight = parseNum(v) ?? 0,
                  ),
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Cíle sérií (např. 12, 10, 8)',
                ),
                onChanged: (value) {
                  final parsed = value
                      .split(',')
                      .map((s) => int.tryParse(s.trim()))
                      .toList();
                  if (parsed.isNotEmpty && parsed.every((n) => n != null && n > 0)) {
                    setState(() => item.targets = parsed.cast<int>());
                  }
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
