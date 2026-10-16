class CameraInfo {
  final String id;
  final String lensFacing; // 'back', 'front', 'external'
  final int sensorOrientation;
  final List<ResolutionSize> resolutions;

  const CameraInfo({
    required this.id,
    required this.lensFacing,
    required this.sensorOrientation,
    required this.resolutions,
  });

  factory CameraInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawRes = map['resolutions'] as List<dynamic>? ?? [];
    final resList = rawRes.map((r) {
      final rMap = r as Map<dynamic, dynamic>;
      return ResolutionSize(
        width: rMap['width'] as int? ?? 1280,
        height: rMap['height'] as int? ?? 720,
      );
    }).toList();

    return CameraInfo(
      id: map['id']?.toString() ?? '0',
      lensFacing: map['lensFacing']?.toString() ?? 'back',
      sensorOrientation: map['sensorOrientation'] as int? ?? 0,
      resolutions: resList,
    );
  }

  bool get isBack => lensFacing.toLowerCase() == 'back';
  bool get isFront => lensFacing.toLowerCase() == 'front';
}

class ResolutionSize {
  final int width;
  final int height;

  const ResolutionSize({required this.width, required this.height});

  String get label => '${width}x$height';

  @override
  String toString() => label;
}

class DeviceCodecCapabilities {
  final bool supportsWebmContainer;
  final bool hasVp8Encoder;
  final bool hasVp9Encoder;
  final bool hasOpusEncoder;
  final bool hasVorbisEncoder;
  final List<String> videoEncoders;
  final List<String> audioEncoders;
  final String androidVersion;
  final int sdkInt;
  final String deviceModel;

  const DeviceCodecCapabilities({
    required this.supportsWebmContainer,
    required this.hasVp8Encoder,
    required this.hasVp9Encoder,
    required this.hasOpusEncoder,
    required this.hasVorbisEncoder,
    required this.videoEncoders,
    required this.audioEncoders,
    required this.androidVersion,
    required this.sdkInt,
    required this.deviceModel,
  });

  factory DeviceCodecCapabilities.fromMap(Map<dynamic, dynamic> map) {
    return DeviceCodecCapabilities(
      supportsWebmContainer: map['supportsWebmContainer'] as bool? ?? true,
      hasVp8Encoder: map['hasVp8Encoder'] as bool? ?? false,
      hasVp9Encoder: map['hasVp9Encoder'] as bool? ?? false,
      hasOpusEncoder: map['hasOpusEncoder'] as bool? ?? false,
      hasVorbisEncoder: map['hasVorbisEncoder'] as bool? ?? false,
      videoEncoders:
          (map['videoEncoders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      audioEncoders:
          (map['audioEncoders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      androidVersion: map['androidVersion']?.toString() ?? 'Unknown',
      sdkInt: map['sdkInt'] as int? ?? 0,
      deviceModel: map['deviceModel']?.toString() ?? 'Android Device',
    );
  }

  bool get isCommonsReady =>
      supportsWebmContainer && (hasVp8Encoder || hasVp9Encoder);
}

class WebmValidationResult {
  final bool isValidWebm;
  final bool hasEbmlHeader;
  final String docType;
  final String? videoMime;
  final String? audioMime;
  final int width;
  final int height;
  final int frameRate;
  final int durationUs;
  final int fileSizeBytes;
  final bool isCommonsCompliant;
  final String diagnostics;

  const WebmValidationResult({
    required this.isValidWebm,
    required this.hasEbmlHeader,
    required this.docType,
    this.videoMime,
    this.audioMime,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.durationUs,
    required this.fileSizeBytes,
    required this.isCommonsCompliant,
    required this.diagnostics,
  });

  factory WebmValidationResult.fromMap(Map<dynamic, dynamic> map) {
    return WebmValidationResult(
      isValidWebm: map['isValidWebm'] as bool? ?? false,
      hasEbmlHeader: map['hasEbmlHeader'] as bool? ?? false,
      docType: map['docType']?.toString() ?? 'UNKNOWN',
      videoMime: map['videoMime']?.toString(),
      audioMime: map['audioMime']?.toString(),
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      frameRate: map['frameRate'] as int? ?? 0,
      durationUs: (map['durationUs'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      isCommonsCompliant: map['isCommonsCompliant'] as bool? ?? false,
      diagnostics: map['diagnostics']?.toString() ?? '',
    );
  }

  double get durationSeconds => durationUs / 1000000.0;
  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    }
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class RecordingConfig {
  final int width;
  final int height;
  final int fps;
  final int bitRate;
  final String videoCodec; // 'VP8' or 'VP9'
  final bool audioEnabled;

  const RecordingConfig({
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.bitRate = 2500000,
    this.videoCodec = 'VP8',
    this.audioEnabled = true,
  });

  RecordingConfig copyWith({
    int? width,
    int? height,
    int? fps,
    int? bitRate,
    String? videoCodec,
    bool? audioEnabled,
  }) {
    return RecordingConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      bitRate: bitRate ?? this.bitRate,
      videoCodec: videoCodec ?? this.videoCodec,
      audioEnabled: audioEnabled ?? this.audioEnabled,
    );
  }
}
