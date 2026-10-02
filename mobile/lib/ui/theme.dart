import 'package:flutter/material.dart';

import '../biometrics/verifier.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2F5D50));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

extension DecisionStyle on Decision {
  Color get color => switch (this) {
    Decision.match => const Color(0xFF1B7F3B),
    Decision.review => const Color(0xFFB26A00),
    Decision.noMatch => const Color(0xFFB3261E),
  };

  IconData get icon => switch (this) {
    Decision.match => Icons.check_circle,
    Decision.review => Icons.help,
    Decision.noMatch => Icons.cancel,
  };

  String get explanation => switch (this) {
    Decision.match => 'Score is at or above the strict threshold (FAR 0.1%).',
    Decision.review => 'Score is between the two thresholds. A person should review this case.',
    Decision.noMatch => 'Score is below the FAR 1% threshold.',
  };
}
