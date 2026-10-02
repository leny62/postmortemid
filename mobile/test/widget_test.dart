import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postmortemid/biometrics/quality.dart';
import 'package:postmortemid/biometrics/verifier.dart';
import 'package:postmortemid/capture/capture_controller.dart';
import 'package:postmortemid/data/models.dart';
import 'package:postmortemid/main.dart';
import 'package:postmortemid/ui/capture_panel.dart';
import 'package:postmortemid/ui/history_screen.dart';
import 'package:postmortemid/ui/result_screen.dart';
import 'package:postmortemid/ui/theme.dart';

import 'support.dart';

VerificationOutcome outcome(double score, Decision decision, {TimePoint tp = TimePoint.t0}) =>
    VerificationOutcome(
      studyCode: 'PM-0001',
      timePoint: tp,
      record: VerificationRecord(
        templateId: 1,
        queryImageId: 1,
        similarity: score,
        tauFar1: 0.80,
        tauFar01: 0.90,
        decision: decision,
        modelVersion: 'test-encoder-v0',
        thresholdVersion: 'test-thresholds-v0',
        appVersion: '0.1.0+test',
        createdAt: DateTime(2026, 10, 2, 9, 30),
      ),
    );

Widget wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

void main() {
  late Directory tmp;
  late AppServices services;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pmid_widget');
    services = await testServices(tmp, const {});
  });

  tearDown(() => tmp.delete(recursive: true));

  testWidgets('home shows prototype status and the three actions', (tester) async {
    await tester.pumpWidget(PostMortemIdApp(services: services));
    expect(find.text('PostMortemID'), findsOneWidget);
    expect(find.text('Test build.'), findsOneWidget);
    expect(find.text('test-encoder-v0'), findsOneWidget);
    expect(find.text('test-thresholds-v0'), findsOneWidget);
    for (final action in ['Enrol', 'Verify', 'History']) {
      expect(find.text(action), findsOneWidget);
    }
  });

  testWidgets('enrol screen validates the study code', (tester) async {
    await tester.pumpWidget(PostMortemIdApp(services: services));
    await tester.tap(find.text('Enrol'));
    await tester.pumpAndSettle();
    expect(find.text('Enrol animal'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'cow 12');
    await tester.tap(find.text('Start enrolment'));
    await tester.pump();
    expect(find.text('Use the format PM-0000'), findsOneWidget);
  });

  testWidgets('history and verify screens open from home', (tester) async {
    await tester.pumpWidget(PostMortemIdApp(services: services));
    await tester.tap(find.text('History'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('No verification results yet.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('No enrolled animals yet. Enrol an animal first.'), findsOneWidget);
  });

  for (final (score, decision) in [
    (0.93, Decision.match),
    (0.85, Decision.review),
    (0.42, Decision.noMatch),
  ]) {
    testWidgets('result view shows ${decision.label} with score and versions', (tester) async {
      await tester.pumpWidget(
        wrap(Scaffold(body: VerificationResultView(outcome: outcome(score, decision)))),
      );
      expect(find.text(decision.label), findsOneWidget);
      expect(find.text('Similarity ${score.toStringAsFixed(3)}'), findsOneWidget);
      expect(find.text('test-encoder-v0'), findsOneWidget);
      expect(find.text('test-thresholds-v0'), findsOneWidget);
      expect(find.byIcon(decision.icon), findsOneWidget);
    });
  }

  testWidgets('post-mortem result warns that post-mortem use is not evaluated', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrap(
        ResultScreen(
          outcome: outcome(0.95, Decision.match, tp: TimePoint.p0),
          isResearchModel: false,
          calibration: 'Test thresholds.',
        ),
      ),
    );
    expect(find.textContaining('LBP fallback encoder'), findsOneWidget);
    expect(find.textContaining('Post-mortem verification has not been evaluated'), findsOneWidget);
  });

  testWidgets('a failed quality check explains the problem in plain words', (tester) async {
    final item = CaptureItem('${tmp.path}/missing.jpg')
      ..state = ItemState.failed
      ..issues = const [QualityIssue.blurry, QualityIssue.tooDark];
    await tester.pumpWidget(wrap(Scaffold(body: CaptureItemTile(item: item))));
    expect(find.text('Please capture again'), findsOneWidget);
    expect(find.textContaining('too blurry'), findsOneWidget);
    expect(find.textContaining('too dark'), findsOneWidget);
  });

  testWidgets('an image that fails after analysis shows its message beside the thumbnail', (
    tester,
  ) async {
    final item = CaptureItem('${tmp.path}/missing.jpg');
    final rebuild = ValueNotifier(0);
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: ValueListenableBuilder(
            valueListenable: rebuild,
            builder: (_, _, _) => CaptureItemTile(item: item, onRemove: () {}),
          ),
        ),
      ),
    );
    item
      ..state = ItemState.failed
      ..issues = const [QualityIssue.blurry];
    rebuild.value++;
    await tester.pump();
    expect(tester.takeException(), isNull);
    final message = tester.getTopLeft(find.textContaining('too blurry'));
    final title = tester.getTopLeft(find.text('Please capture again'));
    expect(message.dx, greaterThan(56));
    expect(message.dy, greaterThan(title.dy));
  });

  testWidgets('history tile shows animal, decision, score and model', (tester) async {
    final o = outcome(0.85, Decision.review, tp: TimePoint.p0);
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: HistoryTile(
            entry: HistoryEntry(
              record: o.record,
              studyCode: o.studyCode,
              timePoint: o.timePoint,
              queryPath: '${tmp.path}/missing.jpg',
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('PM-0001'), findsOneWidget);
    expect(find.textContaining('P0'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.textContaining('Score 0.850'), findsOneWidget);
    expect(find.textContaining('test-encoder-v0'), findsOneWidget);
  });
}
