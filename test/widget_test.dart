// Minimal smoke test for TESSERACT.
//
// This test wires up the actual app widget with a fake TdLibClient so it can
// render without a real TDLib native library present in the test environment.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tesseract/app.dart';
import 'package:tesseract/core/constants/app_constants.dart';
import 'package:tesseract/core/tdlib/tdlib_client.dart';

void main() {
  setUpAll(() async {
    // Initialize AppConstants with test-safe fallbacks (no real platform).
    await AppConstants.initialize();
  });

  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build the app with a fake TdLibClient injected so no native library
    // is required during tests.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tdlibClientProvider.overrideWithValue(_FakeTdLibClient()),
        ],
        child: const TelegramDownloaderApp(),
      ),
    );

    // The app should render at least one widget without throwing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

/// A no-op TdLibClient used in tests to avoid initializing the native TDLib.
class _FakeTdLibClient extends TdLibClient {
  @override
  Future<void> initialize() async {
    // No-op: skip native initialization in test environment.
  }
}
