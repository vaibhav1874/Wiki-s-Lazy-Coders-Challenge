import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:wiki_lazy_coders/core/constants/api_constants.dart';
import 'package:wiki_lazy_coders/core/errors/failures.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_metadata.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_task.dart';

class WikimediaUploadService {
  final http.Client _httpClient;

  WikimediaUploadService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Fetches a CSRF token for the authenticated user from the Action API.
  Future<String> fetchCsrfToken(String accessToken) async {
    final uri = Uri.parse(ApiConstants.commonsApiUrl).replace(
      queryParameters: {
        'action': 'query',
        'meta': 'tokens',
        'type': 'csrf',
        'format': 'json',
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 200) {
      throw WikimediaUploadFailure(
        'Failed to fetch CSRF token: HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['query']?['tokens']?['csrftoken']?.toString();
    if (token == null || token.isEmpty || token == '+\\') {
      throw const WikimediaUploadFailure(
        'Invalid or anonymous CSRF token. Please authenticate first.',
      );
    }

    return token;
  }

  /// Checks if a file with the given title already exists on Wikimedia Commons.
  Future<bool> checkFileExists(String filename, String accessToken) async {
    final uri = Uri.parse(ApiConstants.commonsApiUrl).replace(
      queryParameters: {
        'action': 'query',
        'titles': 'File:$filename',
        'format': 'json',
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages = data['query']?['pages'] as Map<String, dynamic>?;
      if (pages != null) {
        for (final page in pages.values) {
          final pageId = (page as Map<String, dynamic>)['pageid'] as int?;
          if (pageId != null && pageId > 0) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Performs an end-to-end authenticated upload to Wikimedia Commons.
  Future<UploadProgressState> uploadRecording({
    required String filePath,
    required UploadMetadata metadata,
    required String accessToken,
    required Function(UploadProgressState) onProgressUpdate,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const WikimediaUploadFailure(
        'Recording file does not exist on disk.',
      );
    }

    final totalBytes = await file.length();
    final filename = metadata.sanitizedFilename;

    // Step 1: Pre-check duplicate title
    onProgressUpdate(
      UploadProgressState(
        status: UploadStatus.checkingDuplicate,
        progress: 0.05,
        totalBytes: totalBytes,
        statusMessage: 'Checking Commons for duplicate title...',
      ),
    );

    final exists = await checkFileExists(filename, accessToken);
    if (exists) {
      throw WikimediaUploadFailure(
        'A file named "File:$filename" already exists on Wikimedia Commons. Please choose a different title.',
        code: 'FILE_EXISTS',
      );
    }

    // Step 2: Fetch CSRF Token
    onProgressUpdate(
      UploadProgressState(
        status: UploadStatus.fetchingToken,
        progress: 0.15,
        totalBytes: totalBytes,
        statusMessage: 'Fetching Wikimedia CSRF upload token...',
      ),
    );

    final csrfToken = await fetchCsrfToken(accessToken);

    // Step 3: Upload (Chunked for > 4MB, direct multipart for smaller)
    if (totalBytes > 4 * 1024 * 1024) {
      return await _uploadChunked(
        file: file,
        filename: filename,
        metadata: metadata,
        csrfToken: csrfToken,
        accessToken: accessToken,
        totalBytes: totalBytes,
        onProgressUpdate: onProgressUpdate,
      );
    } else {
      return await _uploadDirect(
        file: file,
        filename: filename,
        metadata: metadata,
        csrfToken: csrfToken,
        accessToken: accessToken,
        totalBytes: totalBytes,
        onProgressUpdate: onProgressUpdate,
      );
    }
  }

  /// Uploads small to medium WebM videos via direct multipart POST.
  Future<UploadProgressState> _uploadDirect({
    required File file,
    required String filename,
    required UploadMetadata metadata,
    required String csrfToken,
    required String accessToken,
    required int totalBytes,
    required Function(UploadProgressState) onProgressUpdate,
  }) async {
    onProgressUpdate(
      UploadProgressState(
        status: UploadStatus.uploading,
        progress: 0.25,
        bytesSent: 0,
        totalBytes: totalBytes,
        statusMessage: 'Uploading WebM file to Commons...',
      ),
    );

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiConstants.commonsApiUrl),
    );
    request.headers['User-Agent'] = ApiConstants.userAgent;
    request.headers['Authorization'] = 'Bearer $accessToken';

    request.fields['action'] = 'upload';
    request.fields['filename'] = filename;
    request.fields['token'] = csrfToken;
    request.fields['text'] = metadata.generateWikitext();
    request.fields['comment'] =
        'Uploaded via Wiki WebM Camera (Lazy Coders Challenge)';
    request.fields['format'] = 'json';

    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      filename: filename,
      contentType: MediaType('video', 'webm'),
    );
    request.files.add(multipartFile);

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    return _parseUploadResponse(response.body, filename);
  }

  /// Uploads large files in chunks using Wikimedia Stash API.
  Future<UploadProgressState> _uploadChunked({
    required File file,
    required String filename,
    required UploadMetadata metadata,
    required String csrfToken,
    required String accessToken,
    required int totalBytes,
    required Function(UploadProgressState) onProgressUpdate,
  }) async {
    const chunkSize = 2 * 1024 * 1024; // 2MB chunk
    final randomAccess = await file.open(mode: FileMode.read);
    String? fileKey;
    int offset = 0;

    try {
      while (offset < totalBytes) {
        final bytesToRead = (offset + chunkSize <= totalBytes)
            ? chunkSize
            : (totalBytes - offset);
        final chunkBytes = await randomAccess.read(bytesToRead);

        final request = http.MultipartRequest(
          'POST',
          Uri.parse(ApiConstants.commonsApiUrl),
        );
        request.headers['User-Agent'] = ApiConstants.userAgent;
        request.headers['Authorization'] = 'Bearer $accessToken';

        request.fields['action'] = 'upload';
        request.fields['stash'] = '1';
        request.fields['filesize'] = totalBytes.toString();
        request.fields['offset'] = offset.toString();
        request.fields['filename'] = filename;
        request.fields['token'] = csrfToken;
        request.fields['format'] = 'json';

        if (fileKey != null) {
          request.fields['filekey'] = fileKey;
        }

        final chunkMultipart = http.MultipartFile.fromBytes(
          'chunk',
          chunkBytes,
          filename: 'chunk_$offset.webm',
          contentType: MediaType('video', 'webm'),
        );
        request.files.add(chunkMultipart);

        final streamed = await _httpClient.send(request);
        final resp = await http.Response.fromStream(streamed);

        if (resp.statusCode != 200) {
          throw WikimediaUploadFailure(
            'Chunk upload failed at offset $offset: ${resp.body}',
          );
        }

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final uploadResult = data['upload'] as Map<String, dynamic>?;

        if (uploadResult == null) {
          throw WikimediaUploadFailure('Invalid chunk response: ${resp.body}');
        }

        fileKey = uploadResult['filekey']?.toString() ?? fileKey;
        offset += bytesToRead;

        final progressFraction = 0.2 + (offset / totalBytes) * 0.7;
        onProgressUpdate(
          UploadProgressState(
            status: UploadStatus.uploading,
            progress: progressFraction,
            bytesSent: offset,
            totalBytes: totalBytes,
            statusMessage:
                'Uploading chunk: ${(offset / (1024 * 1024)).toStringAsFixed(1)}MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB',
          ),
        );
      }
    } finally {
      await randomAccess.close();
    }

    // Finalize commit from stash
    onProgressUpdate(
      UploadProgressState(
        status: UploadStatus.verifying,
        progress: 0.95,
        bytesSent: totalBytes,
        totalBytes: totalBytes,
        statusMessage: 'Committing recording to Wikimedia Commons...',
      ),
    );

    final commitResponse = await _httpClient.post(
      Uri.parse(ApiConstants.commonsApiUrl),
      headers: {
        'User-Agent': ApiConstants.userAgent,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'action': 'upload',
        'filekey': fileKey ?? '',
        'filename': filename,
        'comment': 'Uploaded via Wiki WebM Camera (Lazy Coders Challenge)',
        'text': metadata.generateWikitext(),
        'token': csrfToken,
        'format': 'json',
      },
    );

    return _parseUploadResponse(commitResponse.body, filename);
  }

  /// Parses MediaWiki upload API response and handles warnings/errors.
  UploadProgressState _parseUploadResponse(
    String responseBody,
    String filename,
  ) {
    final data = jsonDecode(responseBody) as Map<String, dynamic>;

    if (data.containsKey('error')) {
      final err = data['error'] as Map<String, dynamic>;
      final code = err['code']?.toString() ?? 'UPLOAD_ERROR';
      final info = err['info']?.toString() ?? 'Unknown API error';
      throw WikimediaUploadFailure(
        'Wikimedia API Error ($code): $info',
        code: code,
      );
    }

    final upload = data['upload'] as Map<String, dynamic>?;
    if (upload == null) {
      throw WikimediaUploadFailure('Malformed upload response: $responseBody');
    }

    final result = upload['result']?.toString() ?? '';
    final warnings = <String>[];

    if (upload.containsKey('warnings')) {
      final warnMap = upload['warnings'] as Map<String, dynamic>;
      for (final key in warnMap.keys) {
        warnings.add('$key: ${warnMap[key]}');
      }
    }

    if (result.equalsIgnoreCase('Success')) {
      final canonicalUrl = 'https://commons.wikimedia.org/wiki/File:$filename';
      return UploadProgressState(
        status: UploadStatus.completed,
        progress: 1.0,
        statusMessage: 'Successfully published to Wikimedia Commons!',
        filePageUrl: canonicalUrl,
        warnings: warnings,
      );
    } else if (result.equalsIgnoreCase('Warning')) {
      return UploadProgressState(
        status: UploadStatus.failed,
        progress: 0.9,
        statusMessage: 'Upload stopped due to Commons warnings.',
        errorMessage: warnings.join('\n'),
        warnings: warnings,
      );
    } else {
      throw WikimediaUploadFailure(
        'Upload result status: $result\n$responseBody',
      );
    }
  }
}

extension StringUtils on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
