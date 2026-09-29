import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'scan_page.dart';

class ExercisePicker extends StatefulWidget {
  final AppController app;
  const ExercisePicker({required this.app, super.key});

  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  String query = '';
  String muscleFilter = 'Vše';
  String equipmentFilter = 'Vše';

  static const muscles = [
    'Hrudník',
    'Záda',
    'Nohy',
    'Ramena',
    'Paže',
    'Střed těla',
    'Ostatní',
  ];
  static const equipment = [
    'Činka',
    'Jednoručky',
    'Stroj',
    'Kladka',
    'Vlastní váha',
    'Jiné',
  ];

  Future<void> createCustom() async {
    final name = TextEditingController();
    String muscle = 'Ostatní';
    String tool = 'Jiné';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Vlastní cvik'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Název'),
              ),
              DropdownButton<String>(
                value: muscle,
                isExpanded: true,
                items: muscles
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => update(() => muscle = v!),
              ),
              DropdownButton<String>(
                value: tool,
                isExpanded: true,
                items: equipment
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => update(() => tool = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vytvořit'),
            ),
          ],
        ),
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      await widget.app.saveExercise(name.text, muscle, tool);
      if (mounted) setState(() {});
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercises = [...builtInExercises, ...widget.app.customExercises]
        .where(
          (e) =>
              (e['name'] as String).toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (muscleFilter == 'Vše' || e['muscle'] == muscleFilter) &&
              (equipmentFilter == 'Vše' || e['equipment'] == equipmentFilter),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Vybrat cvik')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Hledat cvik',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final muscle in ['Vše', ...muscles])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(muscle),
                      selected: muscleFilter == muscle,
                      onSelected: (_) => setState(() => muscleFilter = muscle),
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final tool in ['Vše', ...equipment])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tool),
                      selected: equipmentFilter == tool,
                      onSelected: (_) => setState(() => equipmentFilter = tool),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final exercise in exercises)
                  ListTile(
                    title: Text(exercise['name'] as String),
                    subtitle: Text(
                      '${exercise['muscle']} · ${exercise['equipment'] ?? 'Jiné'}',
                    ),
                    onTap: () =>
                        Navigator.pop(context, exercise['id'] as String),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: createCustom,
                  icon: const Icon(Icons.add),
                  label: const Text('Vlastní cvik'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final id = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScanPage(app: widget.app),
                      ),
                    );
                    if (id != null && context.mounted) {
                      Navigator.pop(context, id);
                    }
                  },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Sken stroje'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
