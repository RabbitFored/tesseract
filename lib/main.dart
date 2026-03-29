import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/tdlib/tdlib_client.dart';
import 'features/downloader/data/background_service.dart';
import 'features/downloader/data/download_manager.dart';
import 'features/settings/data/settings_controller.dart';

/// Port name registered in [IsolateNameServer] so the background isolate
/// can locate and send messages to the main isolate's [ReceivePort].
const String kMainIsolatePortName = 'tg_downloader_main_port';

/// Port name the background isolate registers so the main isolate can
/// push download-progress updates to the foreground notification.
const String kBackgroundPortName = 'tg_downloader_bg_port';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Register main-isolate receive port ────────────────────
  _registerMainPort();

  // ── 2. Initialize background keep-alive service ──────────────
  await BackgroundDownloadService.initialize();

  // ── 3. Initialize TDLib in the main isolate (sole owner) ─────
  final tdClient = TdLibClient();
  await tdClient.initialize();

  // ── 4. Launch the widget tree with Riverpod injection ────────
  runApp(
    ProviderScope(
      overrides: [
        tdlibClientProvider.overrideWithValue(tdClient),
      ],
      child: const _AppBootstrap(),
    ),
  );
}

/// Registers a [ReceivePort] in [IsolateNameServer] so the background
/// isolate can reach the main isolate.
void _registerMainPort() {
  IsolateNameServer.removePortNameMapping(kMainIsolatePortName);

  final receivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    receivePort.sendPort,
    kMainIsolatePortName,
  );

  receivePort.listen((message) {
    if (message is Map<String, dynamic>) {
      final action = message['action'] as String?;
      switch (action) {
        case 'request_status':
          _pushStatsToBackground(message);
        default:
          break;
      }
    }
  });
}

void _pushStatsToBackground(Map<String, dynamic> _) {
  final bgPort = IsolateNameServer.lookupPortByName(kBackgroundPortName);
  if (bgPort != null) {
    bgPort.send({
      'action': 'status_response',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

// ── App bootstrap widget ──────────────────────────────────────────

class _AppBootstrap extends ConsumerStatefulWidget {
  const _AppBootstrap();

  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.microtask(() async {
      // Initialize settings first (DownloadManager reads concurrency from it).
      await ref.read(settingsControllerProvider.notifier).initialize();
      // Then initialize the download manager.
      await ref.read(downloadManagerProvider).initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final manager = ref.read(downloadManagerProvider);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        manager.onAppBackgrounded();
      case AppLifecycleState.resumed:
        manager.onAppResumed();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const TelegramDownloaderApp();
  }
}
