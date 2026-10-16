import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wiki_lazy_coders/core/errors/failures.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_metadata.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_task.dart';
import 'package:wiki_lazy_coders/features/upload/services/wikimedia_upload_service.dart';

void main() {
  group('UploadMetadata Tests', () {
    test('sanitizedFilename strips invalid MediaWiki characters and ensures .webm extension', () {
      final metadata = UploadMetadata(
        title: 'My Video #1: Testing [WebM] / Commons?',
        description: 'Test description',
        date: DateTime(2026, 10, 16),
        author: 'User:Vaibhav',
        license: CommonsLicense.ccBySa4,
        hasConfirmedRights: true,
      );

      final filename = metadata.sanitizedFilename;
      expect(filename, 'My Video _1_ Testing _WebM_ _ Commons?.webm');
      expect(filename.endsWith('.webm'), isTrue);
      expect(filename.contains('#'), isFalse);
      expect(filename.contains('['), isFalse);
      expect(filename.contains(']'), isFalse);
      expect(filename.contains('/'), isFalse);
      expect(filename.contains(':'), isFalse);
    });

    test('sanitizedFilename strips existing .webm before appending', () {
      final metadata = UploadMetadata(
        title: 'nature_stream.webm',
        description: 'Nature recording',
        date: DateTime(2026, 10, 16),
        author: 'Vaibhav',
        license: CommonsLicense.cc0,
        hasConfirmedRights: true,
      );

      expect(metadata.sanitizedFilename, 'nature_stream.webm');
    });

    test('generateWikitext formats valid Commons {{Information}} template', () {
      final metadata = UploadMetadata(
        title: 'Sunset over river',
        description: 'A beautiful sunset recorded in WebM format',
        date: DateTime(2026, 10, 16),
        author: 'Vaibhav',
        license: CommonsLicense.ccBySa4,
        latitude: 12.9716,
        longitude: 77.5946,
        categories: ['Sunsets', 'Rivers in India'],
        hasConfirmedRights: true,
      );

      final wikitext = metadata.generateWikitext();

      expect(wikitext, contains('== {{int:filedesc}} =='));
      expect(wikitext, contains('{{Information'));
      expect(
        wikitext,
        contains(
          '|description={{en|1=A beautiful sunset recorded in WebM format}}',
        ),
      );
      expect(wikitext, contains('|date=2026-10-16'));
      expect(wikitext, contains('|source={{own}}'));
      expect(wikitext, contains('|author=[[User:Vaibhav|Vaibhav]]'));
      expect(wikitext, contains('{{Location|12.9716|77.5946}}'));
      expect(wikitext, contains('== {{int:license-header}} =='));
      expect(wikitext, contains('{{self|cc-by-sa-4.0}}'));
      expect(wikitext, contains('[[Category:Sunsets]]'));
      expect(wikitext, contains('[[Category:Rivers in India]]'));
    });
  });

  group('UploadProgressState Tests', () {
    test('computes status flags and percentage accurately', () {
      const state = UploadProgressState(
        status: UploadStatus.uploading,
        progress: 0.654,
        bytesSent: 654000,
        totalBytes: 1000000,
        statusMessage: 'Uploading chunk...',
      );

      expect(state.isUploading, isTrue);
      expect(state.isCompleted, isFalse);
      expect(state.isFailed, isFalse);
      expect(state.progressPercentage, '65%');
    });

    test('completed state checks', () {
      const state = UploadProgressState(
        status: UploadStatus.completed,
        progress: 1.0,
        filePageUrl: 'https://commons.wikimedia.org/wiki/File:Test.webm',
      );

      expect(state.isCompleted, isTrue);
      expect(state.isUploading, isFalse);
      expect(state.progressPercentage, '100%');
    });
  });

  group('WikimediaUploadService API Client Tests', () {
    test('fetchCsrfToken parses valid token correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['action'], 'query');
        expect(request.url.queryParameters['meta'], 'tokens');
        expect(request.headers['Authorization'], 'Bearer test-token-123');

        return http.Response(
          jsonEncode({
            'batchcomplete': '',
            'query': {
              'tokens': {'csrftoken': 'b7c2518e9d2984+\\'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = WikimediaUploadService(httpClient: mockClient);
      final token = await service.fetchCsrfToken('test-token-123');

      expect(token, 'b7c2518e9d2984+\\');
    });

    test('fetchCsrfToken throws on anonymous or empty token', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'query': {
              'tokens': {'csrftoken': '+\\'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = WikimediaUploadService(httpClient: mockClient);
      expect(
        () => service.fetchCsrfToken('test-token-123'),
        throwsA(isA<WikimediaUploadFailure>()),
      );
    });

    test(
      'checkFileExists returns true if file exists and false if missing',
      () async {
        final mockClient = MockClient((request) async {
          final title = request.url.queryParameters['titles'];
          if (title == 'File:ExistingFile.webm') {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '123456': {
                      'pageid': 123456,
                      'ns': 6,
                      'title': 'File:ExistingFile.webm',
                    },
                  },
                },
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '-1': {
                      'ns': 6,
                      'title': 'File:NewFile.webm',
                      'missing': '',
                    },
                  },
                },
              }),
              200,
            );
          }
        });

        final service = WikimediaUploadService(httpClient: mockClient);
        final exists = await service.checkFileExists(
          'ExistingFile.webm',
          'token',
        );
        final notExists = await service.checkFileExists(
          'NewFile.webm',
          'token',
        );

        expect(exists, isTrue);
        expect(notExists, isFalse);
      },
    );

    test(
      'uploadRecording detects duplicate file and aborts before upload',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('webm_test');
        final tempFile = File('${tempDir.path}/test_duplicate.webm');
        await tempFile.writeAsBytes(List.filled(1024, 0));

        final mockClient = MockClient((request) async {
          // Return existing page
          return http.Response(
            jsonEncode({
              'query': {
                'pages': {
                  '999': {'pageid': 999, 'title': 'File:test_duplicate.webm'},
                },
              },
            }),
            200,
          );
        });

        final service = WikimediaUploadService(httpClient: mockClient);
        final metadata = UploadMetadata(
          title: 'test_duplicate',
          description: 'Duplicate test',
          date: DateTime.now(),
          author: 'Vaibhav',
          license: CommonsLicense.ccBySa4,
          hasConfirmedRights: true,
        );

        await expectLater(
          () => service.uploadRecording(
            filePath: tempFile.path,
            metadata: metadata,
            accessToken: 'valid-token',
            onProgressUpdate: (_) {},
          ),
          throwsA(
            predicate(
              (e) => e is WikimediaUploadFailure && e.code == 'FILE_EXISTS',
            ),
          ),
        );

        await tempFile.delete();
        await tempDir.delete();
      },
    );

    test(
      'uploadRecording direct upload success flow parses Commons response',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('webm_test');
        final tempFile = File('${tempDir.path}/sample_recording.webm');
        await tempFile.writeAsBytes(
          List.filled(2048, 1),
        ); // 2KB file -> direct multipart

        final mockClient = MockClient((request) async {
          final query = request.url.queryParameters;
          if (query['action'] == 'query' && query['titles'] != null) {
            // checkFileExists -> not exists
            return http.Response(
              jsonEncode({
                'query': {
                  'pages': {
                    '-1': {'title': query['titles'], 'missing': ''},
                  },
                },
              }),
              200,
            );
          }

          if (query['action'] == 'query' && query['meta'] == 'tokens') {
            // fetchCsrfToken
            return http.Response(
              jsonEncode({
                'query': {
                  'tokens': {'csrftoken': 'mock_csrf_token_value+\\'},
                },
              }),
              200,
            );
          }

          // Direct upload POST request
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({
              'upload': {
                'result': 'Success',
                'filename': 'sample_recording.webm',
                'imageinfo': {
                  'timestamp': '2026-10-16T08:00:00Z',
                  'user': 'Vaibhav',
                  'size': 2048,
                  'descriptionurl': 'https://commons.wikimedia.org/wiki/File:sample_recording.webm',
                },
              },
            }),
            200,
          );
        });

        final service = WikimediaUploadService(httpClient: mockClient);
        final progressList = <UploadProgressState>[];

        final metadata = UploadMetadata(
          title: 'sample_recording',
          description: 'Direct upload success test',
          date: DateTime.now(),
          author: 'Vaibhav',
          license: CommonsLicense.ccBy4,
          hasConfirmedRights: true,
        );

        final result = await service.uploadRecording(
          filePath: tempFile.path,
          metadata: metadata,
          accessToken: 'oauth-token',
          onProgressUpdate: (p) => progressList.add(p),
        );

        expect(result.status, UploadStatus.completed);
        expect(
          result.filePageUrl,
          'https://commons.wikimedia.org/wiki/File:sample_recording.webm',
        );
        expect(progressList.isNotEmpty, isTrue);

        await tempFile.delete();
        await tempDir.delete();
      },
    );
  });
}
