class AppFailure implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppFailure(this.message, {this.code, this.details});

  @override
  String toString() => code != null ? '[$code] $message' : message;
}

class CameraFailure extends AppFailure {
  const CameraFailure(super.message, {super.code, super.details});
}

class RecordingFailure extends AppFailure {
  const RecordingFailure(super.message, {super.code, super.details});
}

class WebmValidationFailure extends AppFailure {
  const WebmValidationFailure(super.message, {super.code, super.details});
}

class WikimediaAuthFailure extends AppFailure {
  const WikimediaAuthFailure(super.message, {super.code, super.details});
}

class WikimediaUploadFailure extends AppFailure {
  const WikimediaUploadFailure(super.message, {super.code, super.details});
}
