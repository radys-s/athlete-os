import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'common.dart';

class OnboardingPage extends StatefulWidget {
  final AppController app;
  const OnboardingPage(this.app, {super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int step = 0;
  String mode = 'Standard';
  String layout = 'Přehledný';
  String goal = 'Síla a svaly';
  bool saving = false;

  Future<void> finish() async {
    setState(() => saving = true);
    try {
      await widget.app.setPreferences(
        newMode: mode,
        newLayout: layout,
        newGoal: goal,
        finishOnboarding: true,
      );
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        toast(context, 'Nastavení se nepodařilo uložit. Zkus to znovu.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                'ATHLETE OS · ${step + 1}/3',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 24),
              if (step == 0) ...[
                const Icon(Icons.fitness_center, size: 64),
                const SizedBox(height: 24),
                Text(
                  'Tvůj trénink. Tvůj progres.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Zapisuj série, připrav si vlastní plán a porovnej výkon s minulým tréninkem. Začít můžeš i bez účtu a připojení.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Návrhy další váhy vycházejí z tvého pravidla. Vždy rozhoduješ ty.',
                ),
              ],
              if (step == 1) ...[
                Text(
                  'Kolik údajů chceš vidět?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                for (final item in const [
                  ('Simple', 'Začínám · váha a opakování'),
                  ('Standard', 'Trénuji pravidelně · navíc RIR a návrhy'),
                  ('Advanced', 'Chci detail · navíc objem a odhad 1RM'),
                ])
                  ListTile(
                    selected: mode == item.$1,
                    title: Text(item.$1),
                    subtitle: Text(item.$2),
                    trailing: Icon(
                      mode == item.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: saving ? null : () => setState(() => mode = item.$1),
                  ),
                const Text('Režim kdykoliv změníš. Historie zůstane stejná.'),
              ],
              if (step == 2) ...[
                Text(
                  'Nastav si svůj přehled',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: goal,
                  decoration: const InputDecoration(labelText: 'Hlavní cíl'),
                  items:
                      const [
                            'Síla a svaly',
                            'Pravidelný pohyb',
                            'Udržet kondici',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => goal = v!),
                ),
                const SizedBox(height: 20),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Přehledný', label: Text('Přehledný')),
                    ButtonSegment(value: 'Detailní', label: Text('Detailní')),
                    ButtonSegment(
                      value: 'Soustředěný',
                      label: Text('Soustředěný'),
                    ),
                  ],
                  selected: {layout},
                  onSelectionChanged: (v) => setState(() => layout = v.first),
                ),
                const SizedBox(height: 12),
                Text(
                  layout == 'Přehledný'
                      ? 'Stručné karty a navigace dole.'
                      : layout == 'Detailní'
                      ? 'Podrobný přehled plánů a navigace nahoře.'
                      : 'Jen Trénink, Historie a Progres. Nastavení otevřeš ozubeným kolem.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Data se ukládají do tohoto zařízení. Zálohu si můžeš uložit v Nastavení.',
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: saving
                    ? null
                    : () {
                        if (step < 2) {
                          setState(() => step++);
                        } else {
                          finish();
                        }
                      },
                child: Text(
                  saving
                      ? 'Ukládám…'
                      : step == 2
                      ? 'Začít trénovat'
                      : 'Pokračovat',
                ),
              ),
              if (step > 0)
                TextButton(
                  onPressed: saving ? null : () => setState(() => step--),
                  child: const Text('Zpět'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
