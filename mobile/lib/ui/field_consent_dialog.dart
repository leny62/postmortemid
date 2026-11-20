import 'package:flutter/material.dart';

import '../privacy/privacy_policy.dart';
import 'privacy_screen.dart';

/// Returns true when the collector ticks every statement and agrees.
class FieldConsentDialog extends StatefulWidget {
  const FieldConsentDialog({super.key});

  @override
  State<FieldConsentDialog> createState() => _FieldConsentDialogState();
}

class _FieldConsentDialogState extends State<FieldConsentDialog> {
  final _ticked = List.filled(fieldConsentStatements.length, false);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Before you collect today'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fieldConsentStatements.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ticked[i],
              onChanged: (v) => setState(() => _ticked[i] = v ?? false),
              title: Text(fieldConsentStatements[i]),
            ),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyScreen())),
            child: const Text('Read the privacy notice'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
      FilledButton(
        onPressed: _ticked.every((t) => t) ? () => Navigator.pop(context, true) : null,
        child: const Text('Agree'),
      ),
    ],
  );
}
