import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/recordings/models/recording_item.dart';
import 'package:wiki_lazy_coders/features/recordings/services/recordings_storage_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final RecordingItem recording;
  final Function(String filePath) onUpload;
  final VoidCallback onDelete;

  const VideoPlayerScreen({
    super.key,
    required this.recording,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  final RecordingsStorageService _storageService = RecordingsStorageService();
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final file = File(widget.recording.filePath);
    if (!await file.exists()) {
      setState(() {
        _initError = 'Recording file not found on disk.';
      });
      return;
    }

    try {
      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() {
        _isInitialized = true;
      });
      _controller.play();
    } catch (e) {
      setState(() {
        _initError = 'Failed to load video player: $e';
      });
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final val = widget.recording.validation;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.recording.fileName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _storageService.shareRecording(widget.recording.filePath),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.recordingRed),
            onPressed: () async {
              final nav = Navigator.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: const Text('Delete Recording?'),
                  content: Text('Are you sure you want to permanently delete "${widget.recording.fileName}"?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.recordingRed),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _storageService.deleteRecording(widget.recording.filePath);
                widget.onDelete();
                if (mounted) nav.pop();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Player Area
            AspectRatio(
              aspectRatio: _isInitialized && _controller.value.aspectRatio > 0
                  ? _controller.value.aspectRatio
                  : 16 / 9,
              child: Container(
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isInitialized)
                      VideoPlayer(_controller)
                    else if (_initError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _initError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.recordingRed),
                        ),
                      )
                    else
                      const CircularProgressIndicator(color: AppTheme.primaryAccent),

                    // Center Play/Pause Touch Overlay
                    if (_isInitialized)
                      GestureDetector(
                        onTap: () {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: AnimatedOpacity(
                            opacity: _controller.value.isPlaying ? 0.0 : 0.85,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow, size: 54, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Playback Progress Bar & Time
            if (_isInitialized) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: AppTheme.primaryAccent,
                        inactiveTrackColor: AppTheme.surfaceLight,
                        thumbColor: AppTheme.primaryAccent,
                      ),
                      child: Slider(
                        value: _controller.value.position.inMilliseconds
                            .toDouble()
                            .clamp(0.0, _controller.value.duration.inMilliseconds.toDouble()),
                        max: _controller.value.duration.inMilliseconds.toDouble() > 0
                            ? _controller.value.duration.inMilliseconds.toDouble()
                            : 1.0,
                        onChanged: (val) {
                          _controller.seekTo(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_controller.value.position),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                        Text(
                          _formatDuration(_controller.value.duration),
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // WebM Container & Codec Validation Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'WebM Container Verification',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: val.isCommonsCompliant
                                  ? AppTheme.primary.withValues(alpha: 0.25)
                                  : AppTheme.warningOrange.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: val.isCommonsCompliant ? AppTheme.primaryAccent : AppTheme.warningOrange,
                              ),
                            ),
                            child: Text(
                              val.isCommonsCompliant ? 'COMMONS READY' : 'NON-COMPLIANT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: val.isCommonsCompliant ? AppTheme.primaryAccent : AppTheme.warningOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: AppTheme.border),
                      _buildDiagnosticRow('Container Format', 'WebM (EBML: 0x1A45DFA3, DocType: ${val.docType})'),
                      _buildDiagnosticRow('Video Track', '${val.videoMime ?? "VP8"} (${val.width}x${val.height} @ ${val.frameRate}fps)'),
                      _buildDiagnosticRow('Audio Track', val.audioMime ?? 'Opus (audio/opus)'),
                      _buildDiagnosticRow('File Size', widget.recording.fileSizeFormatted),
                      _buildDiagnosticRow('Duration', '${val.durationSeconds.toStringAsFixed(1)}s'),
                      if (val.diagnostics.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            val.diagnostics,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Upload CTA Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Upload to Wikimedia Commons'),
                onPressed: () {
                  widget.onUpload(widget.recording.filePath);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
