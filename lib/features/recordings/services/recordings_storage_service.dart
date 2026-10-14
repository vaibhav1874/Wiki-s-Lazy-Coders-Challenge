import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';
import 'package:wiki_lazy_coders/features/camera/services/native_camera_service.dart';
import 'package:wiki_lazy_coders/features/recordings/models/recording_item.dart';

class RecordingsStorageService {
  final NativeCameraService _cameraService;

  RecordingsStorageService({NativeCameraService? cameraService})
      : _cameraService = cameraService ?? NativeCameraService();

  Future<Directory> getRecordingsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(docsDir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir;
  }

  /// Loads all local recordings and validates each WebM container.
  Future<List<RecordingItem>> loadRecordings() async {
    final dir = await getRecordingsDirectory();
    final entities = await dir.list().toList();
    final items = <RecordingItem>[];

    for (final entity in entities) {
      if (entity is File && entity.path.toLowerCase().endsWith('.webm')) {
        final stat = await entity.stat();
        WebmValidationResult val;
        try {
          val = await _cameraService.validateWebm(entity.path);
        } catch (_) {
          val = WebmValidationResult(
            isValidWebm: false,
            hasEbmlHeader: false,
            docType: 'UNKNOWN',
            width: 0,
            height: 0,
            frameRate: 0,
            durationUs: 0,
            fileSizeBytes: stat.size,
            isCommonsCompliant: false,
            diagnostics: 'Validation error',
          );
        }

        items.add(
          RecordingItem(
            filePath: entity.path,
            fileName: p.basename(entity.path),
            recordedAt: stat.modified,
            fileSizeBytes: stat.size,
            durationSeconds: val.durationSeconds,
            validation: val,
          ),
        );
      }
    }

    // Sort newest first
    items.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return items;
  }

  /// Deletes a recording file.
  Future<void> deleteRecording(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Shares a recording via Android Sharesheet.
  Future<void> shareRecording(String filePath) async {
    final xFile = XFile(filePath, mimeType: 'video/webm');
    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        text: 'Recorded with Wiki WebM Camera',
      ),
    );
  }
}
