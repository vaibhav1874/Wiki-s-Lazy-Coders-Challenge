import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wiki_lazy_coders/main.dart';

void main() {
  testWidgets('App shell loads navigation items and initial screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WikiLazyCodersApp());

    // Verify bottom navigation bar items exist
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Recordings'), findsOneWidget);
    expect(find.text('Wikimedia'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Verify icons exist
    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
