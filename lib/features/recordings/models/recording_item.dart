import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';

class RecordingItem {
  final String filePath;
  final String fileName;
  final DateTime recordedAt;
  final int fileSizeBytes;
  final double durationSeconds;
  final WebmValidationResult validation;

  const RecordingItem({
    required this.filePath,
    required this.fileName,
    required this.recordedAt,
    required this.fileSizeBytes,
    required this.durationSeconds,
    required this.validation,
  });

  String get fileSizeFormatted => validation.fileSizeFormatted;

  bool get isCommonsCompliant => validation.isCommonsCompliant;
}
