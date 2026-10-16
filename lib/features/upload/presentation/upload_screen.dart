import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/commons_auth/models/auth_state.dart';
import 'package:wiki_lazy_coders/features/commons_auth/services/wikimedia_auth_service.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_metadata.dart';
import 'package:wiki_lazy_coders/features/upload/models/upload_task.dart';
import 'package:wiki_lazy_coders/features/upload/services/wikimedia_upload_service.dart';

class UploadScreen extends StatefulWidget {
  final String filePath;
  final VoidCallback onUploadComplete;

  const UploadScreen({
    super.key,
    required this.filePath,
    required this.onUploadComplete,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final WikimediaAuthService _authService = WikimediaAuthService();
  final WikimediaUploadService _uploadService = WikimediaUploadService();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _authorController = TextEditingController();
  final _categoriesController = TextEditingController(
    text: 'Videos, WebM videos',
  );

  CommonsLicense _selectedLicense = CommonsLicense.ccBySa4;
  bool _confirmedRights = false;
  DateTime _recordingDate = DateTime.now();

  OAuthTokens? _tokens;
  WikimediaUser? _user;
  bool _isCheckingAuth = true;

  UploadProgressState _progressState = const UploadProgressState(
    status: UploadStatus.idle,
  );

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final file = File(widget.filePath);
    if (await file.exists()) {
      final stat = await file.stat();
      _recordingDate = stat.modified;
      final baseName = p.basenameWithoutExtension(widget.filePath);
      _titleController.text = baseName;
    }

    final tokens = await _authService.getValidTokens();
    final user = await _authService.getStoredUser();

    if (user != null) {
      _authorController.text = user.name;
    }

    setState(() {
      _tokens = tokens;
      _user = user;
      _isCheckingAuth = false;
    });
  }

  Future<void> _startUpload() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmedRights) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must confirm that you have the rights to publish this recording.',
          ),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    if (_tokens == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please authenticate with Wikimedia Commons before uploading.',
          ),
          backgroundColor: AppTheme.recordingRed,
        ),
      );
      return;
    }

    final categoriesList = _categoriesController.text
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    final metadata = UploadMetadata(
      title: _titleController.text,
      description: _descriptionController.text,
      date: _recordingDate,
      author: _authorController.text.trim().isNotEmpty
          ? _authorController.text.trim()
          : (_user?.name ?? 'Anonymous'),
      license: _selectedLicense,
      categories: categoriesList,
      hasConfirmedRights: _confirmedRights,
    );

    setState(() {
      _progressState = const UploadProgressState(
        status: UploadStatus.fetchingToken,
        progress: 0.05,
        statusMessage: 'Preparing upload to Commons...',
      );
    });

    try {
      final result = await _uploadService.uploadRecording(
        filePath: widget.filePath,
        metadata: metadata,
        accessToken: _tokens!.accessToken,
        onProgressUpdate: (state) {
          if (mounted) setState(() => _progressState = state);
        },
      );

      if (mounted) {
        setState(() => _progressState = result);
        widget.onUploadComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progressState = UploadProgressState(
            status: UploadStatus.failed,
            errorMessage: e.toString(),
            statusMessage: 'Upload failed',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Upload to Commons')),
      body: _isCheckingAuth
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            )
          : _progressState.isCompleted
          ? _buildSuccessView()
          : _progressState.isUploading
          ? _buildUploadingView()
          : _buildFormView(),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Auth advisory if not logged in
            if (_tokens == null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warningOrange),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warningOrange,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Not authenticated. Please go to the Wikimedia tab and connect your account first.',
                        style: TextStyle(
                          color: AppTheme.warningOrange,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_progressState.isFailed) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.recordingRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.recordingRed),
                ),
                child: Text(
                  _progressState.errorMessage ??
                      'Upload failed. Please check parameters and try again.',
                  style: const TextStyle(
                    color: AppTheme.recordingRed,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'File Name on Commons',
                hintText: 'e.g. Birds_in_flight_Mumbai',
                suffixText: '.webm',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please provide a file title';
                }
                if (val.trim().length < 3) {
                  return 'Title must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (English)',
                hintText: 'Describe what this WebM recording depicts...',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please provide a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Author Attribution
            TextFormField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: 'Author / Creator Attribution',
                hintText: 'Wikimedia username or legal name',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please specify the author name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Recording Date Display
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.border),
              ),
              tileColor: AppTheme.surfaceVariant,
              leading: const Icon(
                Icons.calendar_today,
                color: AppTheme.primaryAccent,
                size: 20,
              ),
              title: const Text(
                'Recording Date',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              subtitle: Text(
                DateFormat('MMMM d, yyyy').format(_recordingDate),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Categories
            TextFormField(
              controller: _categoriesController,
              decoration: const InputDecoration(
                labelText: 'Categories (comma separated)',
                hintText: 'Videos, Nature, Architecture',
              ),
            ),
            const SizedBox(height: 20),

            // License Selection Card
            const Text(
              'Free License Selection (Wikimedia Commons Requirement)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: CommonsLicense.values.map((lic) {
                    // ignore: deprecated_member_use
                    return RadioListTile<CommonsLicense>(
                      title: Text(
                        lic.displayName,
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: lic,
                      // ignore: deprecated_member_use
                      groupValue: _selectedLicense,
                      activeColor: AppTheme.primaryAccent,
                      // ignore: deprecated_member_use
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedLicense = val);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Explicit Rights Confirmation
            CheckboxListTile(
              value: _confirmedRights,
              activeColor: AppTheme.primaryAccent,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I confirm that I recorded this video myself, own the copyright, and agree to irrevocably license it under the selected free license according to Wikimedia Commons Terms.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              onChanged: (val) =>
                  setState(() => _confirmedRights = val ?? false),
            ),
            const SizedBox(height: 24),

            // Upload Button
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Publish to Wikimedia Commons'),
              onPressed: _tokens != null ? _startUpload : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryAccent),
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                size: 54,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _progressState.statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progressState.progress,
              backgroundColor: AppTheme.surfaceLight,
              color: AppTheme.primaryAccent,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Text(
              _progressState.progressPercentage,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryAccent, width: 2),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Upload Successful!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your WebM recording is now published on Wikimedia Commons and freely accessible to the world.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            if (_progressState.filePageUrl != null)
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: const Text('View on Wikimedia Commons'),
                onPressed: () async {
                  final uri = Uri.parse(_progressState.filePageUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
