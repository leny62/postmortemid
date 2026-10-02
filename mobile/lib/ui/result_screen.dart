import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../biometrics/verifier.dart';
import '../capture/capture_controller.dart';
import '../data/models.dart';
import 'theme.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.outcome,
    required this.isResearchModel,
    required this.calibration,
  });

  final VerificationOutcome outcome;
  final bool isResearchModel;
  final String calibration;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [VerificationResultView(outcome: outcome), const SizedBox(height: 16), _caveats()],
      ),
    );
  }

  Widget _caveats() {
    final postMortem = outcome.timePoint != TimePoint.t0;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isResearchModel)
              const _Note(
                'This is the initial model, trained only on public images of live cattle.',
              )
            else
              const _Note(
                'This result comes from the LBP fallback encoder, not the research model.',
              ),
            _Note(calibration),
            if (postMortem)
              const _Note(
                'Post-mortem verification has not been evaluated yet. This score is not evidence that the muzzle identifies the animal after death.',
              ),
            const _Note('This result supports a person\'s decision. It is not a final identity decision.'),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class VerificationResultView extends StatelessWidget {
  const VerificationResultView({super.key, required this.outcome});

  final VerificationOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final r = outcome.record;
    final d = r.decision;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: d.color.withValues(alpha: 0.12),
            border: Border.all(color: d.color, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(d.icon, color: d.color, size: 48),
              const SizedBox(height: 8),
              Text(d.label, style: text.headlineMedium?.copyWith(color: d.color)),
              const SizedBox(height: 4),
              Text(d.explanation, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Similarity ${r.similarity.toStringAsFixed(3)}', style: text.titleLarge),
        const SizedBox(height: 8),
        ScoreScale(score: r.similarity, tauFar1: r.tauFar1, tauFar01: r.tauFar01),
        const SizedBox(height: 16),
        _Detail('Claimed animal', outcome.studyCode),
        _Detail('Query time point', '${outcome.timePoint.code}, ${outcome.timePoint.label}'),
        _Detail('Threshold FAR 1%', r.tauFar1.toStringAsFixed(3)),
        _Detail('Threshold FAR 0.1%', r.tauFar01.toStringAsFixed(3)),
        _Detail('Model', r.modelVersion),
        _Detail('Threshold file', r.thresholdVersion),
        _Detail('App', r.appVersion),
        _Detail('Time', DateFormat('d MMM yyyy, HH:mm').format(r.createdAt)),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

/// Bar showing the three decision bands and where the score falls.
class ScoreScale extends StatelessWidget {
  const ScoreScale({super.key, required this.score, required this.tauFar1, required this.tauFar01});

  final double score;
  final double tauFar1;
  final double tauFar01;

  @override
  Widget build(BuildContext context) {
    // Zoom the bar around the thresholds; the full -1..1 cosine range would squeeze the bands.
    final span = (tauFar01 - tauFar1).abs().clamp(0.02, 1.0);
    final lo = (tauFar1 - 2 * span).clamp(-1.0, 1.0);
    final hi = (tauFar01 + 2 * span).clamp(-1.0, 1.0);
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                height: 14,
                child: Row(
                  children: [
                    _band(Decision.noMatch, pos(tauFar1)),
                    _band(Decision.review, pos(tauFar01) - pos(tauFar1)),
                    _band(Decision.match, 1 - pos(tauFar01)),
                  ],
                ),
              ),
              Positioned(
                left: (pos(score) * w - 2).clamp(0, w - 4),
                top: 6,
                child: Container(width: 4, height: 30, color: Colors.black87),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _band(Decision d, double fraction) => Expanded(
    flex: (fraction * 1000).round().clamp(1, 1000),
    child: Container(color: d.color.withValues(alpha: 0.7)),
  );
}
