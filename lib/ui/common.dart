import 'package:flutter/material.dart';

/// 42.5 -> "42.5", 40.0 -> "40".
String fmtNum(num value) {
  final d = value.toDouble();
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
}

double? parseNum(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

void toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Zpět'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

String formatDateTime(DateTime value) {
  final l = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}. ${l.month}. ${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String formatTime(DateTime value) {
  final l = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}
