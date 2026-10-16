import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';
import 'package:wiki_lazy_coders/features/camera/services/native_camera_service.dart';
import 'package:wiki_lazy_coders/features/recordings/services/recordings_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final RecordingConfig currentConfig;
  final Function(RecordingConfig newConfig) onConfigChanged;
  final VoidCallback onNavigateToAuth;

  const SettingsScreen({
    super.key,
    required this.currentConfig,
    required this.onConfigChanged,
    required this.onNavigateToAuth,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NativeCameraService _cameraService = NativeCameraService();
  final RecordingsStorageService _storageService = RecordingsStorageService();

  late RecordingConfig _config;
  DeviceCodecCapabilities? _capabilities;
  bool _isLoadingCapabilities = true;
  int _recordingsCount = 0;
  int _totalSizeBytes = 0;
  String _storagePath = '';

  @override
  void initState() {
    super.initState();
    _config = widget.currentConfig;
    _loadSettingsData();
  }

  Future<void> _loadSettingsData() async {
    setState(() => _isLoadingCapabilities = true);

    try {
      final caps = await _cameraService.getDeviceCapabilities();
      final dir = await _storageService.getRecordingsDirectory();
      _storagePath = dir.path;

      int count = 0;
      int bytes = 0;
      if (await dir.exists()) {
        final files = await dir.list().toList();
        for (final f in files) {
          if (f is File && f.path.endsWith('.webm')) {
            count++;
            bytes += await f.length();
          }
        }
      }

      setState(() {
        _capabilities = caps;
        _recordingsCount = count;
        _totalSizeBytes = bytes;
        _isLoadingCapabilities = false;
      });
    } catch (_) {
      setState(() => _isLoadingCapabilities = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void _updateConfig(RecordingConfig newConfig) {
    setState(() => _config = newConfig);
    widget.onConfigChanged(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Settings & Hardware Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section 1: Device Hardware & WebM Diagnostics
          _buildHardwareCapabilitiesCard(),
          const SizedBox(height: 16),

          // Section 2: Recording Configuration
          _buildRecordingConfigCard(),
          const SizedBox(height: 16),

          // Section 3: Storage & Local Files
          _buildStorageCard(),
          const SizedBox(height: 16),

          // Section 4: Wikimedia Commons Integration & Guidelines
          _buildWikimediaCard(),
          const SizedBox(height: 24),

          // App Info
          const Center(
            child: Text(
              'Wiki Lazy Coders Challenge • Direct WebM Engine\nVP8/Vorbis Native Android Pipeline',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHardwareCapabilitiesCard() {
    final caps = _capabilities;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.memory,
                  color: AppTheme.primaryAccent,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Android Media Capabilities',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (caps != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: caps.isCommonsReady
                          ? AppTheme.primary.withValues(alpha: 0.25)
                          : AppTheme.warningOrange.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      caps.isCommonsReady ? 'Commons Ready' : 'Limited',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: caps.isCommonsReady
                            ? AppTheme.primaryAccent
                            : AppTheme.warningOrange,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),
            if (_isLoadingCapabilities)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryAccent,
                  ),
                ),
              )
            else if (caps == null)
              const Text(
                'Capabilities unavailable on this platform.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              )
            else ...[
              _buildDiagRow(
                'Device / OS',
                '${caps.deviceModel} (Android ${caps.androidVersion}, API ${caps.sdkInt})',
              ),
              _buildDiagRow(
                'WebM Container',
                caps.supportsWebmContainer
                    ? 'Supported (OutputFormat.WEBM)'
                    : 'Unsupported',
                isOk: caps.supportsWebmContainer,
              ),
              _buildDiagRow(
                'VP8 Video Encoder',
                caps.hasVp8Encoder
                    ? 'Hardware / Software VP8 Available'
                    : 'Not detected',
                isOk: caps.hasVp8Encoder,
              ),
              _buildDiagRow(
                'VP9 Video Encoder',
                caps.hasVp9Encoder ? 'Available' : 'Not detected',
                isOk: caps.hasVp9Encoder,
              ),
              _buildDiagRow(
                'Audio Encoders',
                'Vorbis: ${caps.hasVorbisEncoder ? "Yes" : "No"} | Opus: ${caps.hasOpusEncoder ? "Yes" : "No"}',
                isOk: caps.hasVorbisEncoder || caps.hasOpusEncoder,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, color: AppTheme.secondaryLight, size: 22),
                SizedBox(width: 8),
                Text(
                  'Recording Configuration',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),

            // Resolution Selector
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resolution', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '${_config.width} x ${_config.height} (${_getResolutionName(_config.width, _config.height)})',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: DropdownButton<String>(
                value: '${_config.width}x${_config.height}',
                dropdownColor: AppTheme.surfaceVariant,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: '1920x1080',
                    child: Text('1080p FHD'),
                  ),
                  DropdownMenuItem(value: '1280x720', child: Text('720p HD')),
                  DropdownMenuItem(value: '640x480', child: Text('480p SD')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  final parts = val.split('x');
                  final w = int.parse(parts[0]);
                  final h = int.parse(parts[1]);
                  _updateConfig(_config.copyWith(width: w, height: h));
                },
              ),
            ),

            // Frame Rate
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Frame Rate', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '${_config.fps} FPS',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: DropdownButton<int>(
                value: _config.fps,
                dropdownColor: AppTheme.surfaceVariant,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: 24,
                    child: Text('24 FPS (Cinematic)'),
                  ),
                  DropdownMenuItem(value: 30, child: Text('30 FPS (Standard)')),
                  DropdownMenuItem(value: 60, child: Text('60 FPS (Smooth)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateConfig(_config.copyWith(fps: val));
                  }
                },
              ),
            ),

            // Bitrate
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Video Bitrate',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '${(_config.bitRate / 1000000).toStringAsFixed(1)} Mbps',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: DropdownButton<int>(
                value: _config.bitRate,
                dropdownColor: AppTheme.surfaceVariant,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: 1500000,
                    child: Text('1.5 Mbps (Low)'),
                  ),
                  DropdownMenuItem(
                    value: 2500000,
                    child: Text('2.5 Mbps (Default)'),
                  ),
                  DropdownMenuItem(
                    value: 5000000,
                    child: Text('5.0 Mbps (High)'),
                  ),
                  DropdownMenuItem(
                    value: 8000000,
                    child: Text('8.0 Mbps (Ultra)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateConfig(_config.copyWith(bitRate: val));
                  }
                },
              ),
            ),

            // Video Codec
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Video Codec', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _config.videoCodec == 'VP8' ? 'VP8 (Commons Required)' : 'VP9',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: DropdownButton<String>(
                value: _config.videoCodec,
                dropdownColor: AppTheme.surfaceVariant,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(
                    value: 'VP8',
                    child: Text('VP8 (Recommended)'),
                  ),
                  DropdownMenuItem(value: 'VP9', child: Text('VP9')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateConfig(_config.copyWith(videoCodec: val));
                  }
                },
              ),
            ),

            // Audio Toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppTheme.primaryAccent,
              title: const Text('Record Audio', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Vorbis / Opus audio track inside WebM container',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              value: _config.audioEnabled,
              onChanged: (val) {
                _updateConfig(_config.copyWith(audioEnabled: val));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: AppTheme.warningOrange,
                  size: 22,
                ),
                SizedBox(width: 8),
                Text(
                  'Local Storage',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),
            _buildDiagRow('Recordings Count', '$_recordingsCount files'),
            _buildDiagRow('Total Disk Usage', _formatBytes(_totalSizeBytes)),
            if (_storagePath.isNotEmpty)
              _buildDiagRow('Storage Path', _storagePath),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Storage Info'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
              ),
              onPressed: _loadSettingsData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWikimediaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.public, color: AppTheme.primaryAccent, size: 22),
                SizedBox(width: 8),
                Text(
                  'Wikimedia Commons Integration',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),
            const Text(
              'Videos uploaded to Commons must use free codecs: WebM (VP8/VP9 with Vorbis/Opus) or Ogg Theora. Our direct native recording engine guarantees strict compliance.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('OAuth & Account'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: widget.onNavigateToAuth,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('Commons Video FAQ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    onPressed: () {
                      launchUrl(
                        Uri.parse(
                          'https://commons.wikimedia.org/wiki/Commons:Video',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagRow(String label, String value, {bool? isOk}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: isOk == null
                    ? AppTheme.textPrimary
                    : (isOk ? AppTheme.primaryAccent : AppTheme.warningOrange),
                fontWeight: isOk == true ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getResolutionName(int w, int h) {
    if (w >= 1920) return 'FHD';
    if (w >= 1280) return 'HD';
    return 'SD';
  }
}
