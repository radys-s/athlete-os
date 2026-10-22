import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../app_controller.dart';
import '../sync.dart';
import 'common.dart';

/// E-mail one-time-code login shared by the locked screen and Settings.
class EmailCodeLogin extends StatefulWidget {
  final AppController app;
  const EmailCodeLogin(this.app, {super.key});

  @override
  State<EmailCodeLogin> createState() => _EmailCodeLoginState();
}

class _EmailCodeLoginState extends State<EmailCodeLogin> {
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (sent) {
        await widget.app.verifyEmailCode(email.text.trim(), code.text.trim());
      } else {
        await widget.app.signIn(email.text.trim());
        if (mounted) setState(() => sent = true);
      }
    } catch (e) {
      final reason = e is AuthException ? e.message : errorText(e);
      if (mounted) setState(() => error = 'Přihlášení selhalo: $reason');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: email,
        enabled: !sent,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail'),
      ),
      if (sent) ...[
        const SizedBox(height: 8),
        const Text('Poslali jsme ti kód. Opiš ho z e-mailu.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    sent = false;
                    code.clear();
                    error = null;
                  }),
            child: const Text('Změnit e-mail nebo poslat znovu'),
          ),
        ),
        TextField(
          controller: code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Kód z e-mailu'),
        ),
      ],
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy || !CloudSync.configured ? null : submit,
        child: Text(sent ? 'Ověřit kód' : 'Poslat kód'),
      ),
    ],
  );
}

class LockedPage extends StatelessWidget {
  final AppController app;
  const LockedPage(this.app, {super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.lock_outline, size: 54),
          const SizedBox(height: 16),
          Text(
            'Data tohoto účtu jsou zamčená',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Přihlas se ke stejnému účtu. Historie zůstává uložená na zařízení.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          EmailCodeLogin(app),
        ],
      ),
    ),
  );
}
