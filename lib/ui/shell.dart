import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'history_page.dart';
import 'login.dart';
import 'plans_page.dart';
import 'progress_page.dart';
import 'settings_page.dart';
import 'workout_page.dart';
import 'common.dart';
import 'onboarding.dart';
import 'superset_editor.dart';

class AthleteApp extends StatelessWidget {
  final AppController controller;
  const AthleteApp(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Athlete OS',
    debugShowCheckedModeBanner: false,
    theme: athleteTheme(),
    builder: (context, child) => ListenableBuilder(
      listenable: controller,
      builder: (_, _) => Stack(
        children: [
          Visibility(
            visible: !controller.locked,
            maintainState: true,
            child: child ?? const SizedBox(),
          ),
          if (controller.locked)
            Scaffold(body: SafeArea(child: LockedPage(controller))),
        ],
      ),
    ),
    home: AppShell(controller),
  );
}

ThemeData athleteTheme() => ThemeData(
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
);

/// Shown instead of a blank screen when startup fails (e.g. the browser
/// refuses persistent storage in a private window).
class StartupErrorApp extends StatelessWidget {
  final Object error;
  const StartupErrorApp(this.error, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: athleteTheme(),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 54),
                const SizedBox(height: 16),
                Text(
                  'Aplikaci se nepodařilo spustit',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Zařízení nebo prohlížeč nepovolil trvalé úložiště. '
                  'V prohlížeči zavři anonymní okno a otevři aplikaci v běžném okně; '
                  'na iPhonu ji přidej na plochu. Data se do paměti "na oko" ukládat nebudou, '
                  'aby o ně nikdo nepřišel.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
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
  String? _shownActiveId;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (!app.locked && !app.onboardingComplete) return OnboardingPage(app);
        // A workout started from History ("Zopakovat") opens the workout tab.
        final activeId = app.active?.id;
        if (activeId != null && _shownActiveId == null) tab = 0;
        _shownActiveId = activeId;
        final focusLayout = app.layout == 'Soustředěný';
        if (focusLayout && tab == 3) tab = 0;
        final navigation = NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.fitness_center),
              label: 'Trénink',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Historie',
            ),
            const NavigationDestination(
              icon: Icon(Icons.show_chart),
              label: 'Progres',
            ),
            if (!focusLayout)
              const NavigationDestination(
                icon: Icon(Icons.tune),
                label: 'Nastavení',
              ),
          ],
        );
        final pages = <Widget>[
          app.active == null
              ? PlansPage(app)
              : WorkoutPage(app, key: ValueKey(app.active!.id)),
          HistoryPage(app),
          ProgressPage(app),
          SettingsPage(app),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(['Trénink', 'Historie', 'Progres', 'Nastavení'][tab]),
            backgroundColor: const Color(0xFF101411),
            actions: [
              if (focusLayout && !app.locked)
                IconButton(
                  tooltip: 'Nastavení',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Nastavení')),
                        body: ListenableBuilder(
                          listenable: app,
                          builder: (_, _) => SettingsPage(app),
                        ),
                      ),
                    ),
                  ),
                ),
              if (app.activeSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text('Ukládám…')),
                ),
              if (app.syncError != null)
                IconButton(
                  tooltip: app.syncError,
                  icon: const Icon(Icons.cloud_off),
                  onPressed: () => app.sync(),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (!app.locked && app.layout == 'Detailní') navigation,
                if (!app.locked && tab == 0 && app.active != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SupersetEditor(app),
                      ),
                    ),
                  ),
                if (!app.locked && app.otherActiveWorkouts.isNotEmpty)
                  MaterialBanner(
                    content: Text(
                      'Další rozepsané tréninky: ${app.otherActiveWorkouts.length}. Záznamy z obou zařízení zůstávají uložené.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          final id = await showDialog<String>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: const Text('Vyber rozepsaný trénink'),
                              children: [
                                for (final w in [
                                  if (app.active != null) app.active!,
                                  ...app.otherActiveWorkouts,
                                ])
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, w.id),
                                    child: Text(
                                      '${w.planName} · ${formatDateTime(w.startedAt)}',
                                    ),
                                  ),
                              ],
                            ),
                          );
                          if (id != null) await app.selectActiveWorkout(id);
                        },
                        child: const Text('Vybrat trénink'),
                      ),
                    ],
                  ),
                if (app.saveError != null)
                  MaterialBanner(
                    content: Text(app.saveError!),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          try {
                            await app.flushActive();
                          } catch (_) {
                            // The banner remains until the save succeeds.
                          }
                        },
                        child: const Text('Uložit znovu'),
                      ),
                    ],
                  ),
                Expanded(child: app.locked ? LockedPage(app) : pages[tab]),
              ],
            ),
          ),
          bottomNavigationBar: app.locked || app.layout == 'Detailní'
              ? null
              : navigation,
        );
      },
    );
  }
}
