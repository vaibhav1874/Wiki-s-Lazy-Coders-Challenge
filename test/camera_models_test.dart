import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';
import 'package:wiki_lazy_coders/features/recordings/models/recording_item.dart';

void main() {
  group('Camera Models Tests', () {
    test('CameraInfo.fromMap parses camera properties correctly', () {
      final map = {
        'id': '0',
        'lensFacing': 'back',
        'sensorOrientation': 90,
        'resolutions': [
          {'width': 1920, 'height': 1080},
          {'width': 1280, 'height': 720},
        ],
      };

      final info = CameraInfo.fromMap(map);
      expect(info.id, '0');
      expect(info.isBack, isTrue);
      expect(info.isFront, isFalse);
      expect(info.sensorOrientation, 90);
      expect(info.resolutions.length, 2);
      expect(info.resolutions.first.label, '1920x1080');
    });

    test('DeviceCodecCapabilities.fromMap parses capabilities correctly', () {
      final map = {
        'supportsWebmContainer': true,
        'hasVp8Encoder': true,
        'hasVp9Encoder': false,
        'hasOpusEncoder': false,
        'hasVorbisEncoder': true,
        'videoEncoders': ['video/x-vnd.on2.vp8'],
        'audioEncoders': ['audio/vorbis'],
        'androidVersion': '14',
        'sdkInt': 34,
        'deviceModel': 'Pixel 8',
      };

      final caps = DeviceCodecCapabilities.fromMap(map);
      expect(caps.supportsWebmContainer, isTrue);
      expect(caps.hasVp8Encoder, isTrue);
      expect(caps.hasVorbisEncoder, isTrue);
      expect(caps.isCommonsReady, isTrue);
      expect(caps.deviceModel, 'Pixel 8');
    });

    test(
      'WebmValidationResult calculates duration and file size correctly',
      () {
        final map = {
          'isValidWebm': true,
          'hasEbmlHeader': true,
          'docType': 'webm',
          'videoMime': 'video/x-vnd.on2.vp8',
          'audioMime': 'audio/vorbis',
          'width': 1280,
          'height': 720,
          'frameRate': 30,
          'durationUs': 5500000,
          'fileSizeBytes': 2500000,
          'isCommonsCompliant': true,
          'diagnostics': 'Valid WebM VP8 Vorbis',
        };

        final result = WebmValidationResult.fromMap(map);
        expect(result.isValidWebm, isTrue);
        expect(result.isCommonsCompliant, isTrue);
        expect(result.durationSeconds, 5.5);
        expect(result.fileSizeFormatted, contains('MB'));
      },
    );

    test('RecordingConfig copyWith updates fields properly', () {
      const config = RecordingConfig();
      expect(config.width, 1280);
      expect(config.height, 720);
      expect(config.fps, 30);
      expect(config.videoCodec, 'VP8');
      expect(config.audioEnabled, isTrue);

      final updated = config.copyWith(width: 1920, height: 1080, fps: 60);
      expect(updated.width, 1920);
      expect(updated.height, 1080);
      expect(updated.fps, 60);
      expect(updated.videoCodec, 'VP8');
    });

    test('RecordingItem computes duration and compliance', () {
      const val = WebmValidationResult(
        isValidWebm: true,
        hasEbmlHeader: true,
        docType: 'webm',
        width: 1280,
        height: 720,
        frameRate: 30,
        durationUs: 3000000,
        fileSizeBytes: 1024 * 1024,
        isCommonsCompliant: true,
        diagnostics: 'OK',
      );

      final item = RecordingItem(
        filePath: '/data/recordings/test.webm',
        fileName: 'test.webm',
        recordedAt: DateTime(2026, 10, 16),
        fileSizeBytes: 1024 * 1024,
        durationSeconds: 3.0,
        validation: val,
      );

      expect(item.isCommonsCompliant, isTrue);
      expect(item.fileSizeFormatted, contains('1.00 MB'));
    });
  });
}
