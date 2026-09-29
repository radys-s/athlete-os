import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'history_page.dart';
import 'login.dart';
import 'plans_page.dart';
import 'progress_page.dart';
import 'settings_page.dart';
import 'workout_page.dart';

class AthleteApp extends StatelessWidget {
  final AppController controller;
  const AthleteApp(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Athlete OS',
    debugShowCheckedModeBanner: false,
    theme: athleteTheme(),
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

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
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
          bottomNavigationBar: app.locked
              ? null
              : NavigationBar(
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
                    NavigationDestination(
                      icon: Icon(Icons.tune),
                      label: 'Nastavení',
                    ),
                  ],
                ),
        );
      },
    );
  }
}
