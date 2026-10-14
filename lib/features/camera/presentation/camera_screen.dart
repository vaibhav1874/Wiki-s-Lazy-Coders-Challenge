import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';
import 'package:wiki_lazy_coders/features/camera/services/native_camera_service.dart';

class CameraScreen extends StatefulWidget {
  final VoidCallback onNavigateToRecordings;
  final Function(String filePath) onUploadRecording;

  const CameraScreen({
    super.key,
    required this.onNavigateToRecordings,
    required this.onUploadRecording,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final NativeCameraService _cameraService = NativeCameraService();

  List<CameraInfo> _cameras = [];
  int _currentCameraIndex = 0;
  int? _textureId;
  bool _isInitializing = true;
  bool _isRecording = false;
  String? _errorMessage;

  RecordingConfig _config = const RecordingConfig();
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraService.stopPreview();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_isRecording) {
        _stopRecording();
      }
      _cameraService.stopPreview();
      setState(() => _textureId = null);
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final cameras = await _cameraService.getAvailableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'No camera devices detected on hardware.';
        });
        return;
      }

      _cameras = cameras;
      final selectedCamera = _cameras[_currentCameraIndex];

      final textureId = await _cameraService.startPreview(
        cameraId: selectedCamera.id,
        width: _config.width,
        height: _config.height,
      );

      setState(() {
        _textureId = textureId;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1 || _isRecording) return;
    setState(() {
      _isInitializing = true;
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    });
    await _cameraService.stopPreview();
    await _initializeCamera();
  }

  Future<void> _startRecording() async {
    try {
      await _cameraService.startRecording(config: _config);
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds++;
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start WebM recording: $e'),
          backgroundColor: AppTheme.recordingRed,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    try {
      final result = await _cameraService.stopRecording();
      final filePath = result['filePath'] as String? ?? '';
      final validation = result['validation'] as WebmValidationResult?;

      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });

      if (mounted && validation != null) {
        _showRecordingSuccessSheet(filePath, validation);
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            backgroundColor: AppTheme.recordingRed,
          ),
        );
      }
    }
  }

  void _showRecordingSuccessSheet(String filePath, WebmValidationResult validation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    validation.isCommonsCompliant ? Icons.check_circle : Icons.warning_rounded,
                    color: validation.isCommonsCompliant ? AppTheme.primaryAccent : AppTheme.warningOrange,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      validation.isCommonsCompliant
                          ? 'Genuine WebM Video Saved'
                          : 'WebM Validation Advisory',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: validation.isCommonsCompliant ? AppTheme.primaryAccent : AppTheme.warningOrange,
                      width: 4,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Container: WebM (DocType: ${validation.docType})',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Video Track: ${validation.videoMime ?? "VP8"} (${validation.width}x${validation.height})',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Audio Track: ${validation.audioMime ?? "Opus"}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Duration: ${validation.durationSeconds.toStringAsFixed(1)}s  •  Size: ${validation.fileSizeFormatted}',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('View Gallery'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onNavigateToRecordings();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Upload Commons'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onUploadRecording(filePath);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview using TextureRegistry
          if (_textureId != null)
            Center(
              child: AspectRatio(
                aspectRatio: _config.width / _config.height,
                child: Texture(textureId: _textureId!),
              ),
            )
          else if (_isInitializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryAccent),
                  SizedBox(height: 16),
                  Text(
                    'Initializing Hardware Camera2...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off, color: AppTheme.recordingRed, size: 54),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _initializeCamera,
                      child: const Text('Retry Camera'),
                    ),
                  ],
                ),
              ),
            ),

          // Top Overlay: Codec Badge, Resolution, Audio Toggle
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Container / Codec Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'WEBM · ${_config.videoCodec} · ${_config.audioEnabled ? "OPUS" : "MUTED"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Top Actions (Audio Mute Toggle & Resolution Switcher)
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _config.audioEnabled ? Icons.mic : Icons.mic_off,
                        color: _config.audioEnabled ? Colors.white : AppTheme.recordingRed,
                      ),
                      onPressed: _isRecording
                          ? null
                          : () {
                              setState(() {
                                _config = _config.copyWith(audioEnabled: !_config.audioEnabled);
                              });
                            },
                    ),
                    const SizedBox(width: 8),
                    // Camera Switch (Front/Back)
                    if (_cameras.length > 1)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android, color: Colors.white),
                        onPressed: _isRecording ? null : _switchCamera,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Recording Indicator & Timer
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.recordingRed, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppTheme.recordingRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'REC ${_formatTimer(_recordingSeconds)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Controls: Gallery Shortcut, Large Record Button, Settings
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gallery shortcut
                IconButton(
                  iconSize: 32,
                  icon: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                  onPressed: _isRecording ? null : widget.onNavigateToRecordings,
                ),

                // Main Circular Record Button
                GestureDetector(
                  onTap: () {
                    if (_isRecording) {
                      _stopRecording();
                    } else {
                      _startRecording();
                    }
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: AppTheme.recordingRed,
                        borderRadius: BorderRadius.circular(_isRecording ? 10 : 36),
                      ),
                    ),
                  ),
                ),

                // Resolution picker shortcut
                PopupMenuButton<ResolutionSize>(
                  icon: const Icon(Icons.tune, color: Colors.white70, size: 28),
                  enabled: !_isRecording,
                  color: AppTheme.surfaceVariant,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: ResolutionSize(width: 1920, height: 1080),
                      child: Text('1080p (Full HD)'),
                    ),
                    const PopupMenuItem(
                      value: ResolutionSize(width: 1280, height: 720),
                      child: Text('720p (HD - Recommended)'),
                    ),
                    const PopupMenuItem(
                      value: ResolutionSize(width: 854, height: 480),
                      child: Text('480p (SD)'),
                    ),
                  ],
                  onSelected: (res) {
                    setState(() {
                      _config = _config.copyWith(width: res.width, height: res.height);
                    });
                    _initializeCamera();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
