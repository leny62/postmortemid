import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

final _fileStamp = DateFormat('yyyyMMdd_HHmmss_SSS');

/// Stage folder names the pilot analysis reads: L for live, then P0 or P1.
String stageFolder(TimePoint t) => t == TimePoint.t0 ? 'L' : t.code;

const fieldImageColumns = [
  'file',
  'identity',
  'stage',
  'modality',
  'burst',
  'captured_at',
  'quality_passed',
  'quality_issues',
  'width',
  'height',
  'brightness',
  'sharpness',
  'device_model',
];

const fieldAnimalColumns = [
  'identity',
  'linkage_status',
  'slaughter_time',
  'head_washed',
  'nose_condition',
  'notes',
  'device_model',
];

/// A kept field photo as it appears in exports and uploads.
class FieldPhoto {
  FieldPhoto.fromRow(Map<String, Object?> r)
    : imageId = r['image_id'] as int,
      sourcePath = r['path'] as String,
      identity = r['study_code'] as String,
      stage = stageFolder(TimePoint.fromCode(r['time_point'] as String)),
      modality = r['modality'] as String,
      name =
          '${_fileStamp.format(DateTime.parse(r['captured_at'] as String))}_${r['image_id']}.jpg',
      _row = r;

  final int imageId;
  final String sourcePath;
  final String identity;
  final String stage;
  final String modality;

  /// File name, ordered by capture time; the pilot reads the time from it if EXIF is missing.
  final String name;
  final Map<String, Object?> _row;

  /// Path in the pilot layout, such as PM-A01/L/muzzle/20261113_094012_345_17.jpg.
  String get file => p.posix.join(identity, stage, modality, name);

  Map<String, Object?> get log => {
    'file': file,
    'identity': identity,
    'stage': stage,
    'modality': modality,
    'burst': _row['session_id'],
    'captured_at': _row['captured_at'],
    'quality_passed': _row['quality_passed'],
    'quality_issues': _row['quality_issues'],
    'width': _row['width'],
    'height': _row['height'],
    'brightness': _row['brightness'],
    'sharpness': _row['sharpness'],
    'device_model': _row['device_model'],
  };
}

/// The animal's field log without the ear tag, for exports and uploads.
Map<String, Object?> fieldAnimalLog(Animal a, String deviceModel) => {
  'identity': a.studyCode,
  'linkage_status': a.linkageStatus.name,
  'slaughter_time': a.fieldLog.slaughterTime?.toIso8601String(),
  'head_washed': switch (a.fieldLog.headWashed) {
    true => 'yes',
    false => 'no',
    null => null,
  },
  'nose_condition': a.fieldLog.noseCondition?.name,
  'notes': a.fieldLog.notes,
  'device_model': deviceModel,
};
