import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'plan_editor.dart';

class PlansPage extends StatelessWidget {
  final AppController app;
  const PlansPage(this.app, {super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'TVŮJ TRÉNINK',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(letterSpacing: 2),
      ),
      const SizedBox(height: 8),
      Text(
        'Připrav se. Zapiš výkon. Posuň se dál.',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlanEditor(app: app)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nový plán'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            await app.startQuickWorkout();
          } catch (error) {
            if (context.mounted) {
              toast(
                context,
                'Trénink se nepodařilo uložit: ${errorText(error)}',
              );
            }
          }
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('Volný trénink bez plánu'),
      ),
      if (app.plans.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text('Můžeš začít hned, nebo si vytvořit plán.'),
          ),
        ),
      for (final plan in app.plans) _PlanCard(app: app, plan: plan),
      if (app.archivedPlans.isNotEmpty)
        Align(
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ArchivedPlansPage(app)),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text('Archiv plánů (${app.archivedPlans.length})'),
          ),
        ),
    ],
  );
}

class ArchivedPlansPage extends StatelessWidget {
  final AppController app;
  const ArchivedPlansPage(this.app, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Archiv plánů')),
    body: ListenableBuilder(
      listenable: app,
      builder: (context, _) => app.archivedPlans.isEmpty
          ? const Center(child: Text('Archiv je prázdný.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final plan in app.archivedPlans)
                  ListTile(
                    title: Text(plan.name),
                    subtitle: Text(
                      czechCount(
                        plan.exercises.length,
                        'cvik',
                        'cviky',
                        'cviků',
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await app.restorePlan(plan);
                          if (context.mounted) {
                            toast(context, 'Plán „${plan.name}“ je zpět.');
                          }
                        } catch (error) {
                          if (context.mounted) {
                            toast(
                              context,
                              'Plán se nepodařilo obnovit: ${errorText(error)}',
                            );
                          }
                        }
                      },
                      child: const Text('Obnovit'),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  final AppController app;
  final Plan plan;
  const _PlanCard({required this.app, required this.plan});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan.name, style: Theme.of(context).textTheme.titleLarge),
          Text(czechCount(plan.exercises.length, 'cvik', 'cviky', 'cviků')),
          if (app.layout == 'Detailní')
            for (final item in plan.exercises)
              Text(
                '${exerciseName(item.exerciseId, app.customExercises)} · '
                '${_planItemSummary(item)}',
              ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await app.startPlan(plan);
                    } catch (error) {
                      if (context.mounted) {
                        toast(
                          context,
                          'Trénink se nepodařilo spustit: ${errorText(error)}',
                        );
                      }
                    }
                  },
                  child: const Text('Začít trénink'),
                ),
              ),
              IconButton(
                tooltip: 'Upravit',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlanEditor(app: app, original: plan),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Další akce s plánem',
                onSelected: (action) async {
                  try {
                    if (action == 'copy') {
                      await app.duplicatePlan(plan);
                    } else if (context.mounted &&
                        await confirmDialog(
                          context,
                          title: 'Archivovat plán?',
                          body: 'Historie tréninků zůstane zachována.',
                          confirmLabel: 'Archivovat',
                        )) {
                      await app.archivePlan(plan);
                    }
                  } catch (error) {
                    if (context.mounted) {
                      toast(
                        context,
                        'Plán se nepodařilo uložit: ${errorText(error)}',
                      );
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('Kopírovat')),
                  PopupMenuItem(value: 'archive', child: Text('Archivovat')),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _planItemSummary(PlanExercise item) {
  final targets = item.targets.join(' / ');
  return switch (item.measurement) {
    MeasurementType.timed => '$targets s',
    MeasurementType.bodyweight =>
      item.weight > 0 ? '$targets · +${fmtNum(item.weight)} kg' : targets,
    MeasurementType.assisted => '$targets · dopomoc ${fmtNum(item.weight)} kg',
    MeasurementType.weighted => '$targets · ${fmtNum(item.weight)} kg',
  };
}
