import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models.dart';
import 'common.dart';
import 'history_detail.dart';

class HistoryPage extends StatelessWidget {
  final AppController app;
  const HistoryPage(this.app, {super.key});

  @override
  Widget build(BuildContext context) => app.sessions.isEmpty
      ? const Center(child: Text('Po prvním tréninku se zde objeví historie.'))
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final session in app.sessions)
              _SessionCard(app: app, session: session),
          ],
        );
}

class _SessionCard extends StatelessWidget {
  final AppController app;
  final Workout session;
  const _SessionCard({required this.app, required this.session});

  Future<void> _decide(
    BuildContext context,
    Proposal proposal, {
    required bool accept,
    double? chosen,
  }) async {
    final error = await app.decideProposal(
      session.id,
      proposal.id,
      accept: accept,
      chosenWeight: chosen,
    );
    if (error != null && context.mounted) toast(context, error);
  }

  Future<void> _edit(BuildContext context, Proposal proposal) async {
    final input = TextEditingController(text: fmtNum(proposal.suggestedWeight));
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upravit další váhu'),
        content: TextField(
          controller: input,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Zpět'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseNum(input.text)),
            child: const Text('Uložit'),
          ),
        ],
      ),
    );
    input.dispose();
    if (chosen != null && chosen >= 0 && context.mounted) {
      await _decide(context, proposal, accept: true, chosen: chosen);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(session.planName, style: Theme.of(context).textTheme.titleLarge),
          Text(formatDateTime(session.finishedAt ?? session.startedAt)),
          if (session.note.trim().isNotEmpty) Text(session.note),
          for (final exercise in session.exercises)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${exercise.weightPr ? '🏆 PR · ' : ''}'
                '${exerciseName(exercise.exerciseId, app.customExercises)}: '
                '${exercise.workSets.where((s) => s.done).map((s) => '${fmtNum(s.weight)} kg × ${s.reps}').join(' · ')}'
                '${exercise.note.trim().isEmpty ? '' : ' · 📝 ${exercise.note}'}',
              ),
            ),
          if (app.mode != 'Simple')
            for (final proposal in session.proposals)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${exerciseName(proposal.exerciseId, app.customExercises)}: ${proposal.reason}',
                    ),
                    if (proposal.eligible && proposal.status == 'pending')
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _decide(context, proposal, accept: true),
                            child: Text(
                              'Potvrdit ${fmtNum(proposal.suggestedWeight)} kg',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => _edit(context, proposal),
                            child: const Text('Upravit'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _decide(context, proposal, accept: false),
                            child: const Text('Ponechat'),
                          ),
                        ],
                      )
                    else if (proposal.status != 'pending')
                      Text('Rozhodnutí: ${proposal.statusLabel}'),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryDetailPage(app: app, session: session),
              ),
            ),
            icon: const Icon(Icons.edit_note),
            label: const Text('Detail a úprava'),
          ),
          OutlinedButton.icon(
            onPressed: app.active != null
                ? null
                : () => app.startFromSession(session),
            icon: const Icon(Icons.replay),
            label: const Text('Zopakovat trénink'),
          ),
          TextButton.icon(
            onPressed: () async {
              if (await confirmDialog(
                context,
                title: 'Smazat trénink?',
                body: 'Záznam se odstraní také ze synchronizovaných zařízení.',
                confirmLabel: 'Smazat',
              )) {
                await app.deleteSession(session.id);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Smazat záznam'),
          ),
        ],
      ),
    ),
  );
}
