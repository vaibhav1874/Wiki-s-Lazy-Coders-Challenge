import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/recordings/models/recording_item.dart';
import 'package:wiki_lazy_coders/features/recordings/presentation/video_player_screen.dart';
import 'package:wiki_lazy_coders/features/recordings/services/recordings_storage_service.dart';

class RecordingsScreen extends StatefulWidget {
  final VoidCallback onNavigateToCamera;
  final Function(String filePath) onUploadRecording;

  const RecordingsScreen({
    super.key,
    required this.onNavigateToCamera,
    required this.onUploadRecording,
  });

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final RecordingsStorageService _storageService = RecordingsStorageService();
  List<RecordingItem> _recordings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final items = await _storageService.loadRecordings();
    setState(() {
      _recordings = items;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Saved WebM Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryAccent),
            )
          : _recordings.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              color: AppTheme.primaryAccent,
              backgroundColor: AppTheme.surfaceVariant,
              onRefresh: _loadRecordings,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _recordings.length,
                itemBuilder: (context, index) {
                  final item = _recordings[index];
                  return _buildRecordingCard(item);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(
                Icons.video_camera_back_outlined,
                size: 56,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No WebM Recordings Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Recordings are encoded directly to WebM format with VP8 and Opus, ready for Wikimedia Commons.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.videocam),
              label: const Text('Start Recording'),
              onPressed: widget.onNavigateToCamera,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard(RecordingItem item) {
    final dateFormat = DateFormat('MMM d, yyyy  •  HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => VideoPlayerScreen(
                recording: item,
                onUpload: (path) => widget.onUploadRecording(path),
                onDelete: _loadRecordings,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Video Icon / Thumbnail Indicator
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Icon(
                  Icons.play_circle_fill,
                  color: AppTheme.primaryAccent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),

              // Title, Date, Codec details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(item.recordedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          item.fileSizeFormatted,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '•',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.durationSeconds.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: item.isCommonsCompliant
                                ? AppTheme.primary.withValues(alpha: 0.2)
                                : AppTheme.warningOrange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.isCommonsCompliant ? 'WebM VP8' : 'Advisory',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: item.isCommonsCompliant
                                  ? AppTheme.primaryAccent
                                  : AppTheme.warningOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                color: AppTheme.surfaceVariant,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'play',
                    child: Row(
                      children: [
                        Icon(
                          Icons.play_arrow,
                          size: 20,
                          color: AppTheme.textPrimary,
                        ),
                        SizedBox(width: 8),
                        Text('Play Video'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'upload',
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 20,
                          color: AppTheme.primaryAccent,
                        ),
                        SizedBox(width: 8),
                        Text('Upload to Commons'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(
                          Icons.share_outlined,
                          size: 20,
                          color: AppTheme.textPrimary,
                        ),
                        SizedBox(width: 8),
                        Text('Share WebM'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppTheme.recordingRed,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppTheme.recordingRed),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) async {
                  if (val == 'play') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => VideoPlayerScreen(
                          recording: item,
                          onUpload: widget.onUploadRecording,
                          onDelete: _loadRecordings,
                        ),
                      ),
                    );
                  } else if (val == 'upload') {
                    widget.onUploadRecording(item.filePath);
                  } else if (val == 'share') {
                    _storageService.shareRecording(item.filePath);
                  } else if (val == 'delete') {
                    await _storageService.deleteRecording(item.filePath);
                    _loadRecordings();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
