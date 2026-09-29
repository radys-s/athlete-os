import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_controller.dart';
import 'models.dart';
import 'sync.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await loadCatalog();
    if (CloudSync.configured) {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    }
    final controller = AppController();
    await controller.initialize();
    runApp(AthleteApp(controller));
  } catch (error) {
    runApp(StartupErrorApp(error));
  }
}
