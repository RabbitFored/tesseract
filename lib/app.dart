import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/settings/data/settings_controller.dart';

/// Root widget for the Telegram Downloader application.
/// Watches [settingsControllerProvider] to reactively switch themes.
class TelegramDownloaderApp extends ConsumerWidget {
  const TelegramDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(
      settingsControllerProvider.select((s) => s.isDarkMode),
    );

    return MaterialApp(
      title: 'Telegram Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2AABEE),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2AABEE),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const AppRouter(),
    );
  }
}
