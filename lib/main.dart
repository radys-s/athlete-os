import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_controller.dart';
import 'models.dart';
import 'progression.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadCatalog();
  if (CloudSync.configured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  }
  final controller = AppController();
  await controller.initialize();
  runApp(AthleteApp(controller));
}

class AthleteApp extends StatelessWidget {
  final AppController controller;
  const AthleteApp(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Athlete OS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB6F36A),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF101411),
      cardTheme: CardThemeData(
        color: const Color(0xFF1B221D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    home: AppShell(controller),
  );
}

class AppShell extends StatefulWidget {
  final AppController app;
  const AppShell(this.app, {super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final pages = <Widget>[
          app.active == null
              ? PlansPage(app)
              : WorkoutPage(app, key: ValueKey(app.active!['id'])),
          HistoryPage(app),
          ProgressPage(app),
          SettingsPage(app),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(['Trénink', 'Historie', 'Progres', 'Nastavení'][tab]),
            backgroundColor: const Color(0xFF101411),
            actions: [
              if (app.syncError != null)
                IconButton(
                  tooltip: app.syncError,
                  icon: const Icon(Icons.cloud_off),
                  onPressed: () => app.sync(),
                ),
            ],
          ),
          body: SafeArea(child: app.locked ? LockedPage(app) : pages[tab]),
          bottomNavigationBar: app.locked ? null : NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.fitness_center),
                label: 'Trénink',
              ),
              NavigationDestination(
                icon: Icon(Icons.history),
                label: 'Historie',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart),
                label: 'Progres',
              ),
              NavigationDestination(icon: Icon(Icons.tune), label: 'Nastavení'),
            ],
          ),
        );
      },
    );
  }
}

class LockedPage extends StatefulWidget {
  final AppController app;
  const LockedPage(this.app, {super.key});

  @override
  State<LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends State<LockedPage> {
  final email = TextEditingController();
  final code = TextEditingController();
  bool sent = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (sent) {
        await widget.app.verifyEmailCode(email.text.trim(), code.text.trim());
      } else {
        await widget.app.signIn(email.text.trim());
        if (mounted) setState(() => sent = true);
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Přihlášení selhalo: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.lock_outline, size: 54),
      const SizedBox(height: 16),
      Text('Data tohoto účtu jsou zamčená',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Přihlas se ke stejnému účtu. Historie zůstává uložená na zařízení.',
        textAlign: TextAlign.center),
      const SizedBox(height: 20),
      TextField(controller: email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail')),
      if (sent) TextField(controller: code, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Kód z e-mailu')),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12),
      FilledButton(onPressed: busy || !CloudSync.configured ? null : submit,
        child: Text(sent ? 'Ověřit kód' : 'Poslat kód')),
    ]),
  ));
}

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
      if (app.plans.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text('Začni vytvořením prvního tréninkového plánu.'),
          ),
        ),
      for (final plan in app.plans)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${asMaps(plan['exercises']).length} cviků'),
                if (app.layout == 'Detailní')
                  for (final item in asMaps(plan['exercises']))
                    Text(
                      '${exerciseName(item['exerciseId'] as String, app.customExercises)} · '
                      '${(item['targets'] as List).join(' / ')} · ${item['weight']} kg',
                    ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => app.startPlan(plan),
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
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Archivovat plán?'),
                              content: const Text(
                                'Historie tréninků zůstane zachována.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Zpět'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Archivovat'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) await app.archivePlan(plan);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'copy', child: Text('Kopírovat')),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text('Archivovat'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class PlanEditor extends StatefulWidget {
  final AppController app;
  final Map<String, dynamic>? original;
  const PlanEditor({required this.app, this.original, super.key});
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  late Map<String, dynamic> plan;
  late TextEditingController name;
  @override
  void initState() {
    super.initState();
    plan = widget.original == null
        ? {
            'id': widget.app.store.newId(),
            'name': '',
            'exercises': <Map<String, dynamic>>[],
          }
        : deepCopy(widget.original!);
    name = TextEditingController(text: plan['name'] as String);
  }

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
    if (id == null) return;
    final items = asMaps(plan['exercises']);
    if (items.any((item) => item['exerciseId'] == id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cvik už je v tomto plánu.')),
        );
      }
      return;
    }
    items.add({
      'exerciseId': id,
      'targets': [12, 10, 8],
      'weight': 0.0,
      'step': 2.5,
      'ruleType': 'fixed',
      'rangeMin': 8,
      'rangeMax': 12,
    });
    setState(() => plan['exercises'] = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = asMaps(plan['exercises']);
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
            Card(
              key: ValueKey(items[i]['exerciseId']),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exerciseName(
                              items[i]['exerciseId'] as String,
                              widget.app.customExercises,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Posunout nahoru',
                          onPressed: i == 0
                              ? null
                              : () {
                                  final moved = items.removeAt(i);
                                  items.insert(i - 1, moved);
                                  setState(() => plan['exercises'] = items);
                                },
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Posunout dolů',
                          onPressed: i == items.length - 1
                              ? null
                              : () {
                                  final moved = items.removeAt(i);
                                  items.insert(i + 1, moved);
                                  setState(() => plan['exercises'] = items);
                                },
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          onPressed: () {
                            items.removeAt(i);
                            setState(() => plan['exercises'] = items);
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: items[i]['ruleType'] as String? ?? 'fixed',
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
                        items[i]['ruleType'] = value;
                        if (value == 'repRange') {
                          items[i]['targets'] = List<int>.filled(
                            (items[i]['targets'] as List).length,
                            (items[i]['rangeMax'] as num?)?.toInt() ?? 12,
                          );
                        }
                        plan['exercises'] = items;
                      }),
                    ),
                    Text(
                      'Cíle: ${(items[i]['targets'] as List).join(' / ')} opakování',
                    ),
                    Row(
                      children: [
                        Text(
                          'Počet sérií: ${(items[i]['targets'] as List).length}',
                        ),
                        IconButton(
                          tooltip: 'Odebrat sérii',
                          onPressed: (items[i]['targets'] as List).length <= 1
                              ? null
                              : () => setState(() {
                                  (items[i]['targets'] as List).removeLast();
                                  plan['exercises'] = items;
                                }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Přidat sérii',
                          onPressed: () => setState(() {
                            final targets = items[i]['targets'] as List;
                            targets.add(targets.last);
                            plan['exercises'] = items;
                          }),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    if (items[i]['ruleType'] == 'repRange')
                      Wrap(
                        spacing: 12,
                        children: [
                          SizedBox(
                            width: 125,
                            child: TextFormField(
                              initialValue: '${items[i]['rangeMin'] ?? 8}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Od opakování',
                              ),
                              onChanged: (v) =>
                                  items[i]['rangeMin'] = int.tryParse(v) ?? 0,
                            ),
                          ),
                          SizedBox(
                            width: 125,
                            child: TextFormField(
                              initialValue: '${items[i]['rangeMax'] ?? 12}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Do opakování',
                              ),
                              onChanged: (v) {
                                final value = int.tryParse(v) ?? 0;
                                items[i]['rangeMax'] = value;
                                items[i]['targets'] = List<int>.filled(
                                  (items[i]['targets'] as List).length,
                                  value,
                                );
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
                          child: TextFormField(
                            initialValue: '${items[i]['weight']}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Váha (kg)',
                            ),
                            onChanged: (v) {
                              items[i]['weight'] =
                                  double.tryParse(v.replaceAll(',', '.')) ?? 0;
                              plan['exercises'] = items;
                            },
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextFormField(
                            initialValue: '${items[i]['step']}',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Krok (kg)',
                            ),
                            onChanged: (v) {
                              items[i]['step'] =
                                  double.tryParse(v.replaceAll(',', '.')) ?? 0;
                              plan['exercises'] = items;
                            },
                          ),
                        ),
                      ],
                    ),
                    if (items[i]['ruleType'] != 'repRange')
                      TextFormField(
                        initialValue: (items[i]['targets'] as List).join(', '),
                        decoration: const InputDecoration(
                          labelText: 'Cíle sérií (např. 12, 10, 8)',
                        ),
                        onChanged: (value) {
                          final targets = value
                              .split(',')
                              .map((s) => int.tryParse(s.trim()))
                              .toList();
                          if (targets.isNotEmpty &&
                              targets.every((n) => n != null && n > 0)) {
                            items[i]['targets'] = targets.cast<int>();
                            plan['exercises'] = items;
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: addExercise,
            icon: const Icon(Icons.add),
            label: const Text('Přidat cvik'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty ||
                  items.isEmpty ||
                  items.any(
                    (item) =>
                        (item['targets'] as List).isEmpty ||
                        (item['step'] as num) <= 0 ||
                        (item['weight'] as num) < 0 ||
                        (item['ruleType'] == 'repRange' &&
                            ((item['rangeMin'] as num?) == null ||
                                (item['rangeMax'] as num?) == null ||
                                (item['rangeMin'] as num) < 1 ||
                                (item['rangeMax'] as num) <
                                    (item['rangeMin'] as num))),
                  )) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Doplň název, cvik a platné cíle.'),
                  ),
                );
                return;
              }
              plan['name'] = name.text.trim();
              plan['exercises'] = items;
              await widget.app.savePlan(plan);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Uložit plán'),
          ),
        ],
      ),
    );
  }
}

class WorkoutPage extends StatefulWidget {
  final AppController app;
  const WorkoutPage(this.app, {super.key});
  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  Timer? ticker;
  DateTime? restEnd;
  int restSeconds = 90;
  bool finishing = false;
  @override
  void initState() {
    super.initState();
    final workout = widget.app.active;
    restSeconds = (workout?['restSeconds'] as num?)?.toInt() ?? 90;
    restEnd = DateTime.tryParse(workout?['restEnd'] as String? ?? '');
    if (restEnd != null) _startTicker();
  }

  void _startTicker() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (restEnd != null && DateTime.now().isAfter(restEnd!)) {
        restEnd = null;
        widget.app.active?.remove('restEnd');
        unawaited(widget.app.saveActive());
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
    restEnd = DateTime.now().add(Duration(seconds: restSeconds));
    widget.app.active?['restEnd'] = restEnd!.toIso8601String();
    widget.app.active?['restSeconds'] = restSeconds;
    unawaited(widget.app.saveActive());
    _startTicker();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.app.active;
    if (workout == null) {
      return const Center(child: Text('Žádný aktivní trénink'));
    }
    final exercises = asMaps(workout['exercises']);
    final remaining = restEnd?.difference(DateTime.now()).inSeconds ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          workout['planName'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          'Začátek: ${DateTime.parse(workout['startedAt'] as String).toLocal().hour.toString().padLeft(2, '0')}:${DateTime.parse(workout['startedAt'] as String).toLocal().minute.toString().padLeft(2, '0')}',
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
                  onPressed: () => setState(
                    () => restSeconds = (restSeconds - 15).clamp(15, 300),
                  ),
                  icon: const Icon(Icons.remove),
                ),
                Text('${restSeconds}s'),
                IconButton(
                  onPressed: () => setState(
                    () => restSeconds = (restSeconds + 15).clamp(15, 300),
                  ),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  onPressed: startRest,
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < exercises.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exerciseName(
                      exercises[i]['exerciseId'] as String,
                      widget.app.customExercises,
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      final previous = widget.app.sessions
                          .expand((s) => asMaps(s['exercises']))
                          .where(
                            (e) =>
                                e['exerciseId'] == exercises[i]['exerciseId'],
                          )
                          .firstOrNull;
                      if (previous == null) return const Text('První záznam');
                      final sets = asMaps(previous['sets']);
                      return Text(
                        'Minule: ${sets.map((s) => '${s['weight']} kg × ${s['reps']}').join(' · ')}',
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  for (var j = 0; j < asMaps(exercises[i]['sets']).length; j++)
                    Builder(
                      builder: (context) {
                        final sets = asMaps(exercises[i]['sets']);
                        final set = sets[j];
                        return Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text('${j + 1}. / ${set['target']}'),
                            ),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('${workout['id']}-$i-$j-weight'),
                                initialValue: '${set['weight']}',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'kg',
                                ),
                                onChanged: (v) {
                                  set['weight'] =
                                      double.tryParse(v.replaceAll(',', '.')) ??
                                      0;
                                  exercises[i]['sets'] = sets;
                                  workout['exercises'] = exercises;
                                  widget.app.saveActive();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: TextFormField(
                                key: ValueKey('${workout['id']}-$i-$j-reps'),
                                initialValue: '${set['reps']}',
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'reps',
                                ),
                                onChanged: (v) {
                                  set['reps'] = int.tryParse(v) ?? 0;
                                  exercises[i]['sets'] = sets;
                                  workout['exercises'] = exercises;
                                  widget.app.saveActive();
                                },
                              ),
                            ),
                            if (widget.app.mode != 'Simple') ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 48,
                                child: TextFormField(
                                  key: ValueKey('${workout['id']}-$i-$j-rir'),
                                  initialValue: set['rir']?.toString() ?? '',
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'RIR',
                                  ),
                                  onChanged: (v) {
                                    set['rir'] = int.tryParse(v);
                                    exercises[i]['sets'] = sets;
                                    workout['exercises'] = exercises;
                                    widget.app.saveActive();
                                  },
                                ),
                              ),
                            ],
                            Checkbox(
                              value: set['done'] == true,
                              onChanged: (value) {
                                setState(() {
                                  set['done'] = value;
                                  exercises[i]['sets'] = sets;
                                  workout['exercises'] = exercises;
                                });
                                widget.app.saveActive();
                                if (value == true) startRest();
                              },
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: finishing
              ? null
              : () async {
                  setState(() => finishing = true);
                  try {
                    final invalid = exercises
                        .expand((e) => asMaps(e['sets']))
                        .where((s) => s['done'] == true)
                        .any(
                          (s) =>
                              (s['reps'] as num) < 1 ||
                              (s['weight'] as num) < 0 ||
                              (s['rir'] != null &&
                                  ((s['rir'] as num) < 0 ||
                                      (s['rir'] as num) > 10)),
                        );
                    if (invalid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Oprav opakování, váhu nebo RIR u dokončené série.',
                          ),
                        ),
                      );
                      return;
                    }
                    final incomplete = exercises
                        .expand((e) => asMaps(e['sets']))
                        .any((s) => s['done'] != true);
                    if (incomplete) {
                      final proceed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Nedokončené série'),
                          content: const Text(
                            'Dokončit trénink i s nedokončenými sériemi?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Zpět'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Dokončit'),
                            ),
                          ],
                        ),
                      );
                      if (proceed != true) return;
                    }
                    await widget.app.finish();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Trénink uložen. Návrhy najdeš v historii.',
                          ),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Trénink se nepodařilo dokončit: $error',
                          ),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => finishing = false);
                  }
                },
          icon: const Icon(Icons.check),
          label: const Text('Dokončit trénink'),
        ),
      ],
    );
  }
}

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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session['planName'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        DateTime.parse(session['finishedAt'] as String)
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                      ),
                      for (final exercise in asMaps(session['exercises']))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${exercise['weightPr'] == true ? '🏆 PR · ' : ''}${exerciseName(exercise['exerciseId'] as String, app.customExercises)}: ${asMaps(exercise['sets']).where((s) => s['done'] == true).map((s) => '${s['weight']} kg × ${s['reps']}').join(' · ')}',
                          ),
                        ),
                      if (app.mode != 'Simple')
                        for (final proposal in asMaps(session['proposals']))
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${exerciseName(proposal['exerciseId'] as String, app.customExercises)}: ${proposal['reason']}',
                                ),
                                if (proposal['eligible'] == true &&
                                    proposal['status'] == 'pending')
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilledButton(
                                        onPressed: () => app.decideProposal(
                                          session['id'] as String,
                                          proposal['id'] as String,
                                          accept: true,
                                        ),
                                        child: Text(
                                          'Potvrdit ${proposal['suggestedWeight']} kg',
                                        ),
                                      ),
                                      OutlinedButton(
                                        onPressed: () async {
                                          final input = TextEditingController(
                                            text:
                                                '${proposal['suggestedWeight']}',
                                          );
                                          final chosen = await showDialog<double>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Upravit další váhu',
                                              ),
                                              content: TextField(
                                                controller: input,
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    ),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'kg',
                                                    ),
                                              ),
                                              actions: [
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        ctx,
                                                        double.tryParse(
                                                          input.text.replaceAll(
                                                            ',',
                                                            '.',
                                                          ),
                                                        ),
                                                      ),
                                                  child: const Text('Uložit'),
                                                ),
                                              ],
                                            ),
                                          );
                                          input.dispose();
                                          if (chosen != null && chosen >= 0) {
                                            await app.decideProposal(
                                              session['id'] as String,
                                              proposal['id'] as String,
                                              accept: true,
                                              chosenWeight: chosen,
                                            );
                                          }
                                        },
                                        child: const Text('Upravit'),
                                      ),
                                      TextButton(
                                        onPressed: () => app.decideProposal(
                                          session['id'] as String,
                                          proposal['id'] as String,
                                          accept: false,
                                        ),
                                        child: const Text('Ponechat'),
                                      ),
                                    ],
                                  )
                                else if (proposal['status'] != 'pending')
                                  Text('Rozhodnutí: ${proposal['status']}'),
                              ],
                            ),
                          ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: app.active != null
                            ? null
                            : () => app.startFromSession(session),
                        icon: const Icon(Icons.replay),
                        label: const Text('Zopakovat trénink'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Smazat trénink?'),
                              content: const Text(
                                'Záznam se odstraní také ze synchronizovaných zařízení.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Zpět'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Smazat'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await app.deleteSession(session['id'] as String);
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Smazat záznam'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
}

class ProgressPage extends StatefulWidget {
  final AppController app;
  const ProgressPage(this.app, {super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ids = app.sessions
        .expand((s) => asMaps(s['exercises']))
        .map((e) => e['exerciseId'] as String)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return const Center(child: Text('Grafy se objeví po prvním tréninku.'));
    }
    selected = ids.contains(selected) ? selected : ids.first;
    final points = <FlSpot>[];
    double bestWeight = 0;
    double bestE1rm = 0;
    final ordered = [...app.sessions]
      ..sort(
        (a, b) =>
            (a['finishedAt'] as String).compareTo(b['finishedAt'] as String),
      );
    for (final session in ordered) {
      final matching = asMaps(session['exercises'])
          .where((e) => e['exerciseId'] == selected);
      if (matching.isEmpty) continue;
      double maxWeight = 0;
      for (final set in asMaps(
        matching.first['sets'],
      ).where((s) => s['done'] == true)) {
        final weight = (set['weight'] as num).toDouble();
        if (weight > maxWeight) maxWeight = weight;
        if (weight > bestWeight) bestWeight = weight;
        final estimate = estimatedOneRepMax(
          weight,
          (set['reps'] as num).toInt(),
        );
        if (estimate != null && estimate > bestE1rm) bestE1rm = estimate;
      }
      points.add(FlSpot(points.length.toDouble(), maxWeight));
    }
    final muscles = <String, int>{};
    for (final session in app.sessions) {
      for (final exercise in asMaps(session['exercises'])) {
        final muscle = exerciseMuscle(
          exercise['exerciseId'] as String,
          app.customExercises,
        );
        muscles[muscle] =
            (muscles[muscle] ?? 0) +
            asMaps(exercise['sets']).where((s) => s['done'] == true).length;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Cvik'),
          items: ids
              .map(
                (id) => DropdownMenuItem(
                  value: id,
                  child: Text(exerciseName(id, app.customExercises)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => selected = v),
        ),
        const SizedBox(height: 20),
        Text(
          'Nejvyšší dokončená váha',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${bestWeight.toStringAsFixed(1)} kg',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minY: 0,
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: false,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        if (app.mode == 'Advanced') ...[
          const SizedBox(height: 22),
          Text(
            'Pokročilé metriky',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Celkový objem dokončených sérií: ${completedVolume(app.sessions).toStringAsFixed(0)} kg × opakování',
          ),
          Text(
            'Nejvyšší odhad 1RM: ${bestE1rm.toStringAsFixed(1)} kg (Epley, 1–10 opakování)',
          ),
          const SizedBox(height: 12),
          Text(
            'Dokončené série podle primární skupiny',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final entry in muscles.entries)
            Text('${entry.key}: ${entry.value}'),
        ],
      ],
    );
  }
}

class ScanPage extends StatefulWidget {
  final AppController app;
  const ScanPage({required this.app, super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool busy = false;
  String? error;
  List<String> suggestions = [];
  Future<void> scan() async {
    if (scanApiUrl.isEmpty || widget.app.user == null) {
      setState(
        () => error = 'Sken vyžaduje nastavený server a přihlášení. Použij hledání cviku.',
      );
      return;
    }
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (photo == null) return;
    setState(() {
      busy = true;
      error = null;
      suggestions = [];
    });
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$scanApiUrl/v1/machine-scan'),
      );
      request.headers['Authorization'] =
          'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}';
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode != 200) {
        throw Exception('Server vrátil ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final valid = builtInExercises.map((e) => e['id']).toSet();
      suggestions = (data['exercise_ids'] as List<dynamic>)
          .whereType<String>()
          .where((id) => valid.contains(id))
          .take(3)
          .toList();
      if (suggestions.isEmpty) {
        error = 'Stroj se nepodařilo určit. Vyber cvik ručně.';
      }
    } catch (_) {
      error = 'Sken není dostupný. Vyber cvik ručně.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Machine Scan')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.camera_alt_outlined, size: 62),
        const SizedBox(height: 16),
        Text(
          'Vyfoť stroj',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Fotografie se odešle našemu serveru a externímu poskytovateli obrazové AI. '
          'Nepřidá se do historie tréninků. Návrh cviku vždy potvrdíš ty.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : scan,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Vyfotit a odeslat'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, textAlign: TextAlign.center),
          ),
        for (final id in suggestions)
          Card(
            child: ListTile(
              title: Text(exerciseName(id, widget.app.customExercises)),
              trailing: const Icon(Icons.add),
              onTap: () => Navigator.pop(context, id),
            ),
          ),
        TextButton(
          onPressed: () async {
            final id = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => ExercisePicker(app: widget.app),
              ),
            );
            if (id != null && context.mounted) Navigator.pop(context, id);
          },
          child: const Text('Vybrat ručně'),
        ),
      ],
    ),
  );
}

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
          'Cloud zatím není nastaven. Tréninky se ukládají jen do telefonu.',
        ),
      if (CloudSync.configured && app.user == null)
        FilledButton(
          onPressed: () async {
            final email = TextEditingController();
            final submitted = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Přihlášení e-mailem'),
                content: TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Poslat odkaz'),
                  ),
                ],
              ),
            );
            if (submitted == true) {
              try {
                await app.signIn(email.text.trim());
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Otevři přihlašovací odkaz v e-mailu.'),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Přihlášení se nezdařilo.')),
                  );
                }
              }
            }
            email.dispose();
          },
          child: const Text('Přihlásit se'),
        ),
      if (app.user != null) ...[
        Text(app.user!.email ?? 'Přihlášený uživatel'),
        if (app.pendingImport) ...[
          const Text('Na zařízení už jsou tréninky. Potvrď jejich přidání k tomuto účtu.'),
          FilledButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Přidat místní tréninky k účtu?'),
                  content: const Text('Po potvrzení se tyto záznamy zálohují a synchronizují.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Zpět')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Přidat')),
                  ],
                ));
              if (confirmed == true) await app.confirmImport();
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
      FutureBuilder<List<Map<String, dynamic>>>(
        future: app.cloud.conflicts(),
        builder: (context, snapshot) {
          final conflicts = snapshot.data ?? [];
          return Column(
            children: [
              for (final remote in conflicts)
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
                            onPressed: () async {
                              await app.store.resolveConflict(
                                remote['id'] as String,
                                keepLocal: true,
                                remote: remote,
                              );
                              await app.sync();
                            },
                            child: const Text('Ponechat tento telefon'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await app.store.resolveConflict(
                                remote['id'] as String,
                                keepLocal: false,
                                remote: remote,
                              );
                              await app.reload();
                            },
                            child: const Text('Převzít cloud'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class ExercisePicker extends StatefulWidget {
  final AppController app;
  const ExercisePicker({required this.app, super.key});
  @override
  State<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<ExercisePicker> {
  String query = '';
  Future<void> createCustom() async {
    final name = TextEditingController();
    String muscle = 'Ostatní';
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
                items:
                    [
                          'Hrudník',
                          'Záda',
                          'Nohy',
                          'Ramena',
                          'Paže',
                          'Střed těla',
                          'Ostatní',
                        ]
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                onChanged: (v) => update(() => muscle = v!),
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
      await widget.app.saveExercise(name.text, muscle);
      if (mounted) setState(() {});
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercises = [...builtInExercises, ...widget.app.customExercises]
        .where(
          (e) =>
              (e['name'] as String).toLowerCase().contains(query.toLowerCase()),
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
          Expanded(
            child: ListView(
              children: [
                for (final exercise in exercises)
                  ListTile(
                    title: Text(exercise['name'] as String),
                    subtitle: Text(exercise['muscle'] as String),
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
