import 'dart:convert';

import 'package:flutter/services.dart';

import 'biometric_encoder.dart';
import 'lbp_encoder.dart';
import 'quality.dart';
import 'verifier.dart';

const manifestAsset = 'assets/model/manifest.json';

/// Encoder, thresholds and quality limits exported by the research pipeline
/// (ml/scripts/export_app_manifest.py). Replacing this file changes the model
/// and thresholds without changing app code (NFR7).
class ModelManifest {
  const ModelManifest({
    required this.encoder,
    required this.thresholds,
    required this.quality,
    required this.enrolmentImages,
    required this.status,
    required this.calibration,
  });

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    final enc = json['encoder'] as Map<String, dynamic>;
    final thr = json['thresholds'] as Map<String, dynamic>;
    final BiometricEncoder encoder = switch (enc['type']) {
      'lbp' => LbpEncoder(
        modelVersion: enc['model_version'] as String,
        size: enc['size'] as int,
        grid: enc['grid'] as int,
      ),
      final other => throw FormatException('unsupported encoder type $other'),
    };
    return ModelManifest(
      encoder: encoder,
      thresholds: Thresholds(
        version: thr['version'] as String,
        tauFar1: (thr['tau_far1'] as num).toDouble(),
        tauFar01: (thr['tau_far01'] as num).toDouble(),
      ),
      quality: QualityThresholds.fromJson(json['quality'] as Map<String, dynamic>),
      enrolmentImages: json['enrolment_images'] as int,
      status: json['status'] as String,
      calibration: json['calibration'] as String,
    );
  }

  static Future<ModelManifest> load([AssetBundle? bundle]) async {
    final text = await (bundle ?? rootBundle).loadString(manifestAsset);
    return ModelManifest.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  final BiometricEncoder encoder;
  final Thresholds thresholds;
  final QualityThresholds quality;
  final int enrolmentImages;

  /// Short human-readable statement of what this model is and is not.
  final String status;

  /// Where the thresholds came from.
  final String calibration;
}
