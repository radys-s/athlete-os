import 'package:athlete_os/app_controller.dart';
import 'package:athlete_os/database.dart';
import 'package:athlete_os/models.dart';
import 'package:athlete_os/store.dart';
import 'package:athlete_os/ui/shell.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('failed preferences save does not complete first-run setup', () async {
    final db = AthleteDatabase(NativeDatabase.memory());
    final app = AppController(_FailSettingsStore(db));
    await app.initialize();
    try {
      await expectLater(
        app.setPreferences(newMode: 'Simple', finishOnboarding: true),
        throwsStateError,
      );
      expect(app.mode, 'Standard');
      expect(app.onboardingComplete, false);
    } finally {
      app.dispose();
      await db.close();
    }
  });

  testWidgets('account lock hides a settings route opened from focus layout', (
    tester,
  ) async {
    builtInExercises = [];
    final db = AthleteDatabase(NativeDatabase.memory());
    final app = AppController(LocalStore(db));
    await app.initialize();
    try {
      await app.setPreferences(
        newLayout: 'Soustředěný',
        finishOnboarding: true,
      );
      await tester.pumpWidget(AthleteApp(app));
      await tester.tap(find.byTooltip('Nastavení'));
      await tester.pumpAndSettle();
      expect(find.text('Uložit zálohu do souboru'), findsOneWidget);
      app.locked = true;
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Uložit zálohu do souboru'), findsNothing);
      expect(find.text('Data tohoto účtu jsou zamčená'), findsOneWidget);
      await expectLater(app.exportBackup(), throwsStateError);
    } finally {
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await db.close();
    }
  });
  testWidgets('first run completes short setup and persists preferences', (
    tester,
  ) async {
    builtInExercises = [];
    final db = AthleteDatabase(NativeDatabase.memory());
    final app = AppController(LocalStore(db));
    await app.initialize();
    try {
      await tester.pumpWidget(AthleteApp(app));
      expect(find.text('ATHLETE OS · 1/3'), findsOneWidget);
      await tester.tap(find.text('Pokračovat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jednoduchý'));
      await tester.tap(find.text('Pokračovat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detailní'));
      await tester.tap(find.text('Začít trénovat'));
      await tester.pumpAndSettle();
      expect(find.text('Volný trénink bez plánu'), findsOneWidget);
      expect(app.mode, 'Simple');
      expect(app.layout, 'Detailní');
      await app.reload();
      expect(app.onboardingComplete, true);
      expect((await app.store.get('settings'))!['onboardingComplete'], true);
    } finally {
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await db.close();
    }
  });
}

class _FailSettingsStore extends LocalStore {
  _FailSettingsStore(super.database);
  @override
  Future<void> put(
    String kind,
    Map<String, dynamic> data, {
    bool dirty = true,
    bool reviveDeleted = true,
  }) {
    if (kind == 'settings') throw StateError('disk full');
    return super.put(kind, data, dirty: dirty, reviveDeleted: reviveDeleted);
  }
}
