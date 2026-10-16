enum UploadStatus {
  idle,
  fetchingToken,
  checkingDuplicate,
  uploading,
  verifying,
  completed,
  failed,
}

class UploadProgressState {
  final UploadStatus status;
  final double progress; // 0.0 to 1.0
  final int bytesSent;
  final int totalBytes;
  final String statusMessage;
  final String? filePageUrl;
  final String? errorMessage;
  final List<String> warnings;

  const UploadProgressState({
    required this.status,
    this.progress = 0.0,
    this.bytesSent = 0,
    this.totalBytes = 0,
    this.statusMessage = '',
    this.filePageUrl,
    this.errorMessage,
    this.warnings = const [],
  });

  bool get isCompleted => status == UploadStatus.completed;
  bool get isFailed => status == UploadStatus.failed;
  bool get isUploading => status == UploadStatus.uploading || status == UploadStatus.fetchingToken || status == UploadStatus.verifying;

  String get progressPercentage => '${(progress * 100).toInt()}%';
}
