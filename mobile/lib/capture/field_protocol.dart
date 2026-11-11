import '../data/models.dart';

/// One photo set in the abattoir protocol: when, what, and how many accepted photos.
class ShotSet {
  const ShotSet(this.timePoint, this.modality, this.target);

  final TimePoint timePoint;
  final Modality modality;
  final int target;

  String get label =>
      '${timePoint == TimePoint.t0 ? 'Alive' : 'After slaughter'}, '
      '${modality.label.toLowerCase()}';
}

/// Live muzzle has six photos so three can form the template and three remain as
/// live-to-live queries. P0 is photographed at head inspection, before skinning.
const fieldProtocol = [
  ShotSet(TimePoint.t0, Modality.muzzle, 6),
  ShotSet(TimePoint.t0, Modality.face, 4),
  ShotSet(TimePoint.p0, Modality.muzzle, 5),
  ShotSet(TimePoint.p0, Modality.face, 3),
];

final fieldCodePattern = RegExp(r'^PM-([A-Z])(\d{2,3})$');

/// Next free code for a site, such as PM-A07 after PM-A06.
String nextFieldCode(String site, Iterable<String> existing) {
  var highest = 0;
  for (final code in existing) {
    final m = fieldCodePattern.firstMatch(code);
    if (m != null && m.group(1) == site) {
      final n = int.parse(m.group(2)!);
      if (n > highest) highest = n;
    }
  }
  return 'PM-$site${(highest + 1).toString().padLeft(2, '0')}';
}
