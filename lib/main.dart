import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/tdlib/tdlib_client.dart';
import 'features/downloader/data/background_service.dart';
import 'features/downloader/data/download_manager.dart';
import 'features/settings/data/settings_controller.dart';

const String kMainIsolatePortName = 'tg_downloader_main_port';
const String kBackgroundPortName = 'tg_downloader_bg_port';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerMainPort();

  // Run the app FIRST — heavy init happens inside the widget tree
  // so the OS launch screen transitions immediately to a Flutter frame.
  runApp(
    const ProviderScope(
      child: _AppBootstrap(),
    ),
  );
}

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
  TdLibClient? _tdClient;
  Object? _initError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    // Clear any previous error before retrying.
    if (mounted) setState(() => _initError = null);

    try {
      debugPrint('[Bootstrap] Starting BackgroundDownloadService...');
      await BackgroundDownloadService.initialize()
          .timeout(const Duration(seconds: 10));
      debugPrint('[Bootstrap] BackgroundDownloadService ready.');

      debugPrint('[Bootstrap] Starting TdLibClient...');
      final tdClient = TdLibClient();
      await tdClient.initialize()
          .timeout(const Duration(seconds: 20));
      debugPrint('[Bootstrap] TdLibClient ready.');

      debugPrint('[Bootstrap] Initializing settings...');
      await ref.read(settingsControllerProvider.notifier).initialize();

      debugPrint('[Bootstrap] Initializing DownloadManager...');
      await ref.read(downloadManagerProvider).initialize();

      debugPrint('[Bootstrap] All init done. Launching app.');

      if (mounted) {
        setState(() {
          _tdClient = tdClient;
          _ready = true;
        });
      }
    } on TimeoutException catch (e) {
      debugPrint('[Bootstrap] Timeout during init: $e');
      if (mounted) setState(() => _initError = 'Initialization timed out.\n$e');
    } catch (e, st) {
      debugPrint('[Bootstrap] Error during init: $e\n$st');
      if (mounted) setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ready) return;
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
    // ── Error state ───────────────────────────────────────────────
    if (_initError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to start',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_initError',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Loading state ─────────────────────────────────────────────
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // ── App ready ─────────────────────────────────────────────────
    return ProviderScope(
      overrides: [
        tdlibClientProvider.overrideWithValue(_tdClient!),
      ],
      child: const TelegramDownloaderApp(),
    );
  }
}
