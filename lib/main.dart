import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wiki_lazy_coders/core/theme/app_theme.dart';
import 'package:wiki_lazy_coders/features/camera/models/camera_models.dart';
import 'package:wiki_lazy_coders/features/camera/presentation/camera_screen.dart';
import 'package:wiki_lazy_coders/features/commons_auth/presentation/auth_screen.dart';
import 'package:wiki_lazy_coders/features/recordings/presentation/recordings_screen.dart';
import 'package:wiki_lazy_coders/features/settings/presentation/settings_screen.dart';
import 'package:wiki_lazy_coders/features/upload/presentation/upload_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const WikiLazyCodersApp());
}

class WikiLazyCodersApp extends StatelessWidget {
  const WikiLazyCodersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wiki WebM Camera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainShellScreen(),
    );
  }
}

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  RecordingConfig _recordingConfig = const RecordingConfig();

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _openUploadScreen(String filePath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => UploadScreen(
          filePath: filePath,
          onUploadComplete: () {
            // Switch to recordings tab to see updated status
            setState(() => _currentIndex = 1);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      // 0: Camera
      CameraScreen(
        onNavigateToRecordings: () => _navigateToTab(1),
        onUploadRecording: _openUploadScreen,
      ),
      // 1: Recordings Gallery
      RecordingsScreen(
        onNavigateToCamera: () => _navigateToTab(0),
        onUploadRecording: _openUploadScreen,
      ),
      // 2: Wikimedia OAuth
      const AuthScreen(),
      // 3: Settings & Diagnostics
      SettingsScreen(
        currentConfig: _recordingConfig,
        onConfigChanged: (newConfig) {
          setState(() => _recordingConfig = newConfig);
        },
        onNavigateToAuth: () => _navigateToTab(2),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _navigateToTab,
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.primaryAccent,
        unselectedItemColor: AppTheme.textMuted,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.videocam_outlined),
            activeIcon: Icon(Icons.videocam),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library_outlined),
            activeIcon: Icon(Icons.video_library),
            label: 'Recordings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_outlined),
            activeIcon: Icon(Icons.cloud),
            label: 'Wikimedia',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
