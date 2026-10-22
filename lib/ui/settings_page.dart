import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../csv_export.dart';
import '../models.dart';
import '../sync.dart';
import 'common.dart';
import 'login.dart';

class SettingsPage extends StatelessWidget {
  final AppController app;
  const SettingsPage(this.app, {super.key});

  static String _stamp() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _saveFile(
    BuildContext context, {
    required String name,
    required String content,
    required String mime,
  }) async {
    try {
      final target = await FilePicker.saveFile(
        fileName: name,
        bytes: utf8.encode(content),
        mimeType: mime,
        dialogTitle: 'Uložit soubor',
      );
      if (context.mounted && target != null) toast(context, 'Uloženo: $name');
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Soubor se nepodařilo uložit: ${errorText(error)}');
      }
    }
  }

  Future<void> _backupToFile(BuildContext context) async {
    try {
      final backup = await app.exportBackup();
      if (!context.mounted) return;
      await _saveFile(
        context,
        name: 'athlete-os-zaloha-${_stamp()}.json',
        content: backup,
        mime: 'application/json',
      );
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Zálohu se nepodařilo vytvořit: ${errorText(error)}');
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    await _saveFile(
      context,
      name: 'athlete-os-serie-${_stamp()}.csv',
      content: sessionsToCsv(
        app.sessions,
        (id) => exerciseName(id, app.customExercises),
      ),
      mime: 'text/csv',
    );
  }

  Future<void> _restoreFromFile(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) return;
      final source = utf8.decode(await picked.first.readAsBytes());
      final count = await app.importBackup(source);
      if (context.mounted) toast(context, 'Obnoveno $count záznamů.');
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Obnova se nezdařila: ${errorText(error)}');
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    if (!await confirmDialog(
      context,
      title: 'Smazat účet?',
      body: 'Účet i všechna data v cloudu se trvale smažou a stejně tak data v tomto zařízení. Nejdřív si ulož zálohu do souboru.',
      confirmLabel: 'Smazat vše',
    )) {
      return;
    }
    try {
      await app.deleteAccount();
      if (context.mounted) toast(context, 'Účet a data byly smazány.');
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Účet se nepodařilo smazat: ${errorText(error)}');
      }
    }
  }

  Future<void> _wipeDevice(BuildContext context) async {
    if (!await confirmDialog(
      context,
      title: 'Smazat data v zařízení?',
      body: 'Tréninky a plány v tomto zařízení se trvale smažou. Cloudová kopie zůstane. Nejdřív si ulož zálohu.',
      confirmLabel: 'Smazat',
    )) {
      return;
    }
    try {
      await app.wipeLocalData();
      if (context.mounted) toast(context, 'Data v zařízení byla smazána.');
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Smazání se nezdařilo: ${errorText(error)}');
      }
    }
  }

  Future<void> _copyBackup(BuildContext context) async {
    try {
      final backup = await app.exportBackup();
      await Clipboard.setData(ClipboardData(text: backup));
      if (context.mounted) {
        toast(context, 'Záloha je ve schránce. Ulož ji do soukromého souboru.');
      }
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Zálohu se nepodařilo vytvořit: ${errorText(error)}');
      }
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final input = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Obnovit zálohu'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Obnova funguje jen v prázdné instalaci. Záznamy zůstávají místní, dokud nenastavíš cloud.',
              ),
              TextField(
                controller: input,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'JSON záloha'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  input.text = data?.text ?? '';
                },
                icon: const Icon(Icons.content_paste),
                label: const Text('Vložit ze schránky'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Zpět'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('Obnovit'),
          ),
        ],
      ),
    );
    input.dispose();
    if (source == null || !context.mounted) return;
    try {
      final count = await app.importBackup(source);
      if (context.mounted) toast(context, 'Obnoveno $count záznamů.');
    } catch (error) {
      if (context.mounted) {
        toast(context, 'Obnova se nezdařila: ${errorText(error)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Úroveň detailu', style: Theme.of(context).textTheme.titleLarge),
      SegmentedButton<String>(
        showSelectedIcon: false,
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
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'Přehledný', label: Text('Přehledný')),
          ButtonSegment(value: 'Detailní', label: Text('Detailní')),
          ButtonSegment(value: 'Soustředěný', label: Text('Soustředěný')),
        ],
        selected: {app.layout},
        onSelectionChanged: (v) => app.setPreferences(newLayout: v.first),
      ),
      const SizedBox(height: 20),
      Text('Ruční záloha', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Záloha obsahuje tréninky a poznámky. Ulož ji do souboru a měj ji mimo telefon; data v prohlížeči nejsou trvalá záloha.',
      ),
      FilledButton.icon(
        onPressed: () => _backupToFile(context),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Uložit zálohu do souboru'),
      ),
      OutlinedButton.icon(
        onPressed: () => _restoreFromFile(context),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Obnovit ze souboru'),
      ),
      OutlinedButton.icon(
        onPressed: () => _exportCsv(context),
        icon: const Icon(Icons.table_chart_outlined),
        label: const Text('Export sérií (CSV)'),
      ),
      OutlinedButton.icon(
        onPressed: () => _copyBackup(context),
        icon: const Icon(Icons.copy_all_outlined),
        label: const Text('Kopírovat zálohu do schránky'),
      ),
      TextButton.icon(
        onPressed: () => _restoreBackup(context),
        icon: const Icon(Icons.restore),
        label: const Text('Obnovit ze zálohy'),
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
                try {
                  await app.confirmImport();
                } catch (error) {
                  if (context.mounted) {
                    toast(
                      context,
                      'Propojení se nezdařilo: ${errorText(error)}',
                    );
                  }
                }
              }
            },
            child: const Text('Přidat místní data k účtu'),
          ),
        ],
        FilledButton.tonal(
          onPressed: app.sync,
          child: const Text('Synchronizovat'),
        ),
        TextButton(
          onPressed: () async {
            if (await confirmDialog(
              context,
              title: 'Odhlásit se?',
              body: 'Data v zařízení se zamknou, dokud se znovu nepřihlásíš ke stejnému účtu.',
              confirmLabel: 'Odhlásit',
            )) {
              await app.signOut();
            }
          },
          child: const Text('Odhlásit se'),
        ),
        TextButton(
          onPressed: () => _deleteAccount(context),
          child: const Text('Smazat účet a data'),
        ),
      ],
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => _wipeDevice(context),
        child: const Text('Smazat data v tomto zařízení'),
      ),
      if (app.syncError != null) Text(app.syncError!),
      for (final remote in app.conflicts)
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text('Konflikt: ${_conflictLabel(remote)}'),
                subtitle: const Text(
                  'Změna tohoto záznamu existuje také na druhém zařízení.',
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        app.resolveConflict(remote, keepLocal: true),
                    child: const Text('Ponechat toto zařízení'),
                  ),
                  TextButton(
                    onPressed: () =>
                        app.resolveConflict(remote, keepLocal: false),
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

String _conflictLabel(Map<String, dynamic> remote) {
  final payload = remote['payload'];
  final title = payload is Map
      ? '${payload['name'] ?? payload['planName'] ?? ''}'
      : '';
  final kind = switch (remote['kind']) {
    'plan' => 'plán',
    'session' => 'trénink',
    'active' => 'rozepsaný trénink',
    'exercise' => 'cvik',
    'settings' => 'nastavení',
    _ => 'záznam',
  };
  return title.isEmpty ? kind : '$kind „$title“';
}
