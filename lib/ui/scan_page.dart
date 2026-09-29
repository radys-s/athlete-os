import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_controller.dart';
import '../models.dart';
import '../sync.dart';
import 'exercise_picker.dart';

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
