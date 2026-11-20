import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/privacy/field_consent.dart';
import 'package:postmortemid/privacy/privacy_policy.dart';
import 'package:postmortemid/ui/field_study_screen.dart';
import 'package:postmortemid/ui/privacy_screen.dart';
import 'package:postmortemid/ui/theme.dart';

import 'support.dart';

Widget wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  group('field consent day', () {
    test('formats the local date', () {
      expect(consentDay(DateTime(2026, 11, 9, 23, 59)), '2026-11-09');
    });

    test('is needed until recorded, then again the next day', () {
      final now = DateTime(2026, 11, 20, 8);
      expect(consentNeeded(null, now), isTrue);
      expect(consentNeeded('2026-11-20', now), isFalse);
      expect(consentNeeded('2026-11-19', now), isTrue);
    });
  });

  late Directory tmp;
  late AppServices services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pmid_privacy');
    services = await testServices(tmp, const {});
  });

  tearDown(() => tmp.delete(recursive: true));

  testWidgets('privacy screen shows every provision and the limits', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(const PrivacyScreen()));

    for (final p in privacyProvisions) {
      expect(find.text(p.title), findsOneWidget);
      expect(find.text(p.keptBy), findsOneWidget);
    }
    expect(find.text('Limits'), findsOneWidget);
    expect(find.text('Open-source licences'), findsOneWidget);
    expect(find.text(privacyPolicyVersion), findsOneWidget);
  });

  testWidgets('adding an animal waits for all consent statements', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(FieldStudyScreen(services: services)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    await tester.tap(find.text('Add animal'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Before you collect today'), findsOneWidget);

    final agree = find.widgetWithText(FilledButton, 'Agree');
    expect(tester.widget<FilledButton>(agree).onPressed, isNull);
    for (final statement in fieldConsentStatements) {
      await tester.tap(find.text(statement));
      await tester.pump();
    }
    expect(tester.widget<FilledButton>(agree).onPressed, isNotNull);

    await tester.tap(agree);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final recorded = await tester.runAsync(() => services.repository.setting(fieldConsentKey));
    expect(recorded, consentDay(DateTime.now()));
  });

  testWidgets('declining consent keeps the collector out of Add animal', (tester) async {
    await tester.pumpWidget(wrap(FieldStudyScreen(services: services)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    await tester.tap(find.text('Add animal'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Before you collect today'), findsNothing);
    final recorded = await tester.runAsync(() => services.repository.setting(fieldConsentKey));
    expect(recorded, isNull);
  });
}
