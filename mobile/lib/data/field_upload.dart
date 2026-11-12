import 'dart:io';

import 'field_records.dart';
import 'local_repository.dart';
import 'upload_client.dart';

const uploadUrlKey = 'upload_url';
const uploadTokenKey = 'upload_token';

class UploadResult {
  const UploadResult(this.uploaded, this.remaining, [this.error]);

  final int uploaded;
  final int remaining;
  final String? error;
}

/// Sends every field photo not yet on the server, then the logs of the
/// photographed animals. Stops at the first failure; the rest stay queued.
Future<UploadResult> uploadPending(
  LocalRepository repo,
  UploadClient client,
  String deviceModel, {
  void Function(int done, int total)? onProgress,
}) async {
  final pending = (await repo.fieldImages(notUploaded: true)).map(FieldPhoto.fromRow).toList();
  var done = 0;
  try {
    for (final photo in pending) {
      await client.putPhoto(photo.file, File(photo.sourcePath), photo.log);
      await repo.markUploaded(photo.imageId);
      done++;
      onProgress?.call(done, pending.length);
    }
    // Includes animals excluded after their photos went up, so the server learns of it.
    final photographed = (await repo.collectedCounts()).keys.toSet();
    for (final animal in await repo.allAnimals()) {
      if (!photographed.contains(animal.id)) continue;
      final log = fieldAnimalLog(animal, deviceModel)..remove('identity');
      await client.putAnimal(animal.studyCode, log);
    }
  } on UploadException catch (e) {
    return UploadResult(done, pending.length - done, e.message);
  }
  return UploadResult(done, 0);
}
