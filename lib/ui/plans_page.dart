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
        style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 2),
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
      if (app.plans.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text('Začni vytvořením prvního tréninkového plánu.'),
          ),
        ),
      for (final plan in app.plans) _PlanCard(app: app, plan: plan),
    ],
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
          Text('${plan.exercises.length} cviků'),
          if (app.layout == 'Detailní')
            for (final item in plan.exercises)
              Text(
                '${exerciseName(item.exerciseId, app.customExercises)} · '
                '${item.targets.join(' / ')} · ${fmtNum(item.weight)} kg',
              ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await app.startPlan(plan);
                    } on StateError catch (e) {
                      if (context.mounted) toast(context, e.message);
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
