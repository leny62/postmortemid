import 'package:flutter/material.dart';

import '../privacy/policy_provision.dart';
import '../privacy/privacy_policy.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy and consent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Privacy notice', style: text.titleLarge),
          Text(privacyPolicyVersion, style: text.bodySmall),
          const SizedBox(height: 16),
          for (final p in privacyProvisions) _ProvisionCard(p),
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Limits', style: text.titleMedium),
                  const SizedBox(height: 8),
                  for (final limit in privacyLimits)
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $limit')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(context: context, applicationName: 'PostMortemID'),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Open-source licences'),
          ),
          const SizedBox(height: 16),
          Text(
            'Questions or complaints: ALU Research Ethics Committee, $ethicsContact',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ProvisionCard extends StatelessWidget {
  const _ProvisionCard(this.provision);

  final PolicyProvision provision;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(provision.title, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(provision.promise),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provision.keptBy,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
