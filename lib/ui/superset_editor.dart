import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import '../supersets.dart';
import 'common.dart';

class SupersetEditor extends StatelessWidget {
  final AppController app;
  final Plan? plan;
  final VoidCallback? onChanged;
  const SupersetEditor(this.app, {this.plan, this.onChanged, super.key});

  List<(String, String, String?)> get items => plan != null
      ? plan!.exercises
            .map((e) => (e.id, e.exerciseId, e.extra['supersetId'] as String?))
            .toList()
      : (app.active?.exercises ?? [])
            .map((e) => (e.exerciseId, e.exerciseId, supersetId(e)))
            .toList();

  Future<void> edit(BuildContext context) async {
    final choices = items;
    if (choices.length < 2) return;
    String first = choices[0].$1, second = choices[1].$1;
    final pair = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Spojit do supersetu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Střídej cviky. Pauza začne až po dokončení kola.'),
              for (final index in [0, 1])
                DropdownButtonFormField<String>(
                  initialValue: index == 0 ? first : second,
                  decoration: InputDecoration(
                    labelText: index == 0 ? 'První cvik' : 'Druhý cvik',
                  ),
                  items: choices
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.$1,
                          child: Text(exerciseName(e.$2, app.customExercises)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    if (index == 0) {
                      first = v!;
                    } else {
                      second = v!;
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Zpět'),
            ),
            FilledButton(
              onPressed: first == second
                  ? null
                  : () => Navigator.pop(ctx, (first, second)),
              child: const Text('Spojit'),
            ),
          ],
        ),
      ),
    );
    if (pair == null || !context.mounted) return;
    try {
      if (app.locked) throw StateError('Účet je zamčený.');
      if (plan != null) {
        final a = plan!.exercises.firstWhere((e) => e.id == pair.$1);
        final b = plan!.exercises.firstWhere((e) => e.id == pair.$2);
        final groups = {a.extra['supersetId'], b.extra['supersetId']}
          ..remove(null);
        final group = newId();
        for (final e in plan!.exercises) {
          if (e == a || e == b || groups.contains(e.extra['supersetId'])) {
            e.extra['supersetId'] = group;
          }
        }
        onChanged?.call();
      } else {
        final workout = app.active;
        if (workout == null) return;
        await app.linkSuperset(
          workout.exercises.firstWhere((e) => e.exerciseId == pair.$1),
          workout.exercises.firstWhere((e) => e.exerciseId == pair.$2),
        );
      }
    } catch (_) {
      if (context.mounted) {
        toast(context, 'Superset se nepodařilo uložit. Zkus uložení znovu.');
      }
    }
  }

  Future<void> unlink(BuildContext context, String group) async {
    try {
      if (app.locked) throw StateError('Účet je zamčený.');
      if (plan != null) {
        for (final e in plan!.exercises) {
          if (e.extra['supersetId'] == group) e.extra.remove('supersetId');
        }
        onChanged?.call();
      } else {
        final members =
            app.active?.exercises
                .where((e) => supersetId(e) == group)
                .toList() ??
            [];
        for (final e in members) {
          e.extra.remove('supersetId');
        }
        app.touchActive();
        app.notifyListeners();
        await app.flushActive();
      }
    } catch (_) {
      if (context.mounted) {
        toast(context, 'Změna čeká na uložení. Zkus to znovu.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<String>>{};
    for (final e in items) {
      if (e.$3 != null) {
        (groups[e.$3!] ??= []).add(exerciseName(e.$2, app.customExercises));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups.entries.where((e) => e.value.length > 1))
          Row(
            children: [
              Expanded(child: Text('Superset: ${group.value.join(' + ')}')),
              IconButton(
                tooltip: 'Rozpojit superset',
                onPressed: () => unlink(context, group.key),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
        if (items.length > 1)
          TextButton.icon(
            onPressed: () => edit(context),
            icon: const Icon(Icons.link),
            label: const Text('Spojit cviky do supersetu'),
          ),
      ],
    );
  }
}
