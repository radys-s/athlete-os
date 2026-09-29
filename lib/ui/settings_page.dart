import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../sync.dart';
import 'common.dart';
import 'login.dart';

class SettingsPage extends StatelessWidget {
  final AppController app;
  const SettingsPage(this.app, {super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Úroveň detailu', style: Theme.of(context).textTheme.titleLarge),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Simple', label: Text('Simple')),
          ButtonSegment(value: 'Standard', label: Text('Standard')),
          ButtonSegment(value: 'Advanced', label: Text('Advanced')),
        ],
        selected: {app.mode},
        onSelectionChanged: (v) => app.setPreferences(newMode: v.first),
      ),
      const SizedBox(height: 16),
      Text('Uspořádání', style: Theme.of(context).textTheme.titleLarge),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Přehledný', label: Text('Přehledný')),
          ButtonSegment(value: 'Detailní', label: Text('Detailní')),
        ],
        selected: {app.layout},
        onSelectionChanged: (v) => app.setPreferences(newLayout: v.first),
      ),
      const SizedBox(height: 20),
      Text('Účet a záloha', style: Theme.of(context).textTheme.titleLarge),
      if (!CloudSync.configured)
        const Text(
          'Cloud zatím není nastaven. Tréninky se ukládají jen do tohoto zařízení.',
        ),
      if (CloudSync.configured && app.user == null) EmailCodeLogin(app),
      if (app.user != null) ...[
        Text(app.user!.email ?? 'Přihlášený uživatel'),
        if (app.pendingImport) ...[
          const Text(
            'Na zařízení už jsou tréninky. Potvrď jejich přidání k tomuto účtu.',
          ),
          FilledButton(
            onPressed: () async {
              if (await confirmDialog(
                context,
                title: 'Přidat místní tréninky k účtu?',
                body: 'Po potvrzení se tyto záznamy zálohují a synchronizují.',
                confirmLabel: 'Přidat',
              )) {
                await app.confirmImport();
              }
            },
            child: const Text('Přidat místní data k účtu'),
          ),
        ],
        FilledButton.tonal(
          onPressed: app.sync,
          child: const Text('Synchronizovat'),
        ),
        TextButton(onPressed: app.signOut, child: const Text('Odhlásit se')),
      ],
      if (app.syncError != null) Text(app.syncError!),
      for (final remote in app.conflicts)
        Card(
          child: Column(
            children: [
              const ListTile(
                title: Text('Konflikt synchronizace'),
                subtitle: Text(
                  'Změna tohoto záznamu existuje také na druhém zařízení.',
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => app.resolveConflict(remote, keepLocal: true),
                    child: const Text('Ponechat toto zařízení'),
                  ),
                  TextButton(
                    onPressed: () => app.resolveConflict(remote, keepLocal: false),
                    child: const Text('Převzít cloud'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}
