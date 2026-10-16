import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wiki_lazy_coders/core/errors/failures.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';

class NativeCameraService {
  static const MethodChannel _channel = MethodChannel(
    'org.wikimedia.wikilazycoders/camera',
  );

  /// Queries Android MediaCodec and MediaRecorder hardware/software capabilities.
  Future<DeviceCodecCapabilities> getDeviceCapabilities() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceCapabilities',
      );
      if (res == null) {
        throw const CameraFailure(
          'Null response received from camera capabilities inquiry.',
        );
      }
      return DeviceCodecCapabilities.fromMap(res);
    } on PlatformException catch (e) {
      throw CameraFailure(
        'Failed to query camera capabilities: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Lists available camera devices on the hardware.
  Future<List<CameraInfo>> getAvailableCameras() async {
    try {
      final res = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'getAvailableCameras',
      );
      if (res == null || res.isEmpty) {
        return [];
      }
      return res.map((m) => CameraInfo.fromMap(m)).toList();
    } on PlatformException catch (e) {
      throw CameraFailure('Failed to list cameras: ${e.message}', code: e.code);
    }
  }

  /// Starts live camera preview and returns the Flutter TextureRegistry ID.
  Future<int> startPreview({
    String? cameraId,
    int width = 1280,
    int height = 720,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startPreview',
        {'cameraId': cameraId, 'width': width, 'height': height},
      );
      final textureId = res?['textureId'] as int? ?? -1;
      if (textureId < 0) {
        throw const CameraFailure(
          'Failed to obtain a valid texture ID for camera preview.',
        );
      }
      return textureId;
    } on PlatformException catch (e) {
      throw CameraFailure('Camera preview failed: ${e.message}', code: e.code);
    }
  }

  /// Stops camera preview and frees hardware resources.
  Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod<bool>('stopPreview');
    } on PlatformException catch (e) {
      throw CameraFailure(
        'Failed to stop camera preview: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Starts direct WebM recording using MediaRecorder OutputFormat.WEBM.
  Future<String> startRecording({
    required RecordingConfig config,
    String? customFileName,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory(p.join(directory.path, 'recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = customFileName ?? 'wiki_webm_$timestamp.webm';
      final outputPath = p.join(recordingsDir.path, fileName);

      await _channel.invokeMethod<bool>('startRecording', {
        'outputPath': outputPath,
        'width': config.width,
        'height': config.height,
        'fps': config.fps,
        'bitRate': config.bitRate,
        'videoCodec': config.videoCodec,
        'audioEnabled': config.audioEnabled,
      });

      return outputPath;
    } on PlatformException catch (e) {
      throw RecordingFailure(
        'Failed to start recording: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Stops current recording and returns the output file path and validation result.
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'stopRecording',
      );
      if (res == null) {
        throw const RecordingFailure('Stop recording returned null response.');
      }
      final filePath = res['filePath']?.toString() ?? '';
      final valMap = res['validation'] as Map<dynamic, dynamic>? ?? {};
      final validation = WebmValidationResult.fromMap(valMap);

      return {'filePath': filePath, 'validation': validation};
    } on PlatformException catch (e) {
      throw RecordingFailure(
        'Failed to stop recording cleanly: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Validates any local file path using native EBML byte inspection and MediaExtractor.
  Future<WebmValidationResult> validateWebm(String filePath) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'validateWebm',
        {'filePath': filePath},
      );
      if (res == null) {
        throw const WebmValidationFailure('Validation returned null result.');
      }
      return WebmValidationResult.fromMap(res);
    } on PlatformException catch (e) {
      throw WebmValidationFailure(
        'WebM validation failed: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Generates a genuine EBML WebM test sample for container verification testing.
  Future<String> createSampleWebm(String filePath) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createSampleWebm',
        {'filePath': filePath},
      );
      return res?['filePath']?.toString() ?? filePath;
    } on PlatformException catch (e) {
      throw WebmValidationFailure(
        'Failed to generate sample WebM: ${e.message}',
        code: e.code,
      );
    }
  }

  /// Captures a high-resolution still photograph using Camera2 STILL_CAPTURE.
  Future<String> takePhoto() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(p.join(dir.path, 'photos'));
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = p.join(photosDir.path, 'IMG_$timestamp.jpg');

      final res = await _channel.invokeMethod<String>('takePhoto', {
        'outputPath': filePath,
      });
      return res ?? filePath;
    } on PlatformException catch (e) {
      throw CameraFailure(
        'Failed to take photograph: ${e.message}',
        code: e.code,
      );
    }
  }
}
