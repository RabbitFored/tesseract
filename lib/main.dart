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

  // runApp immediately — all heavy init happens inside the widget tree.
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
      if (action == 'request_status') {
        _pushStatsToBackground(message);
      }
    }
  });
}

void _pushStatsToBackground(Map<String, dynamic> _) {
  final bgPort = IsolateNameServer.lookupPortByName(kBackgroundPortName);
  bgPort?.send({
    'action': 'status_response',
    'timestamp': DateTime.now().toIso8601String(),
  });
}

// ── Stage 1 bootstrap: NO Riverpod provider reads here ───────────
//
// Only initializes BackgroundDownloadService and TdLibClient.
// settingsController and downloadManager depend on tdlibClientProvider,
// so they MUST be initialized after the override is in place (see _AppInner).

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  TdLibClient? _tdClient;
  Object? _initError;
  StackTrace? _initStack;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _initError = null;
        _initStack = null;
      });
    }

    try {
      debugPrint('[Bootstrap] Starting BackgroundDownloadService...');
      await BackgroundDownloadService.initialize()
          .timeout(const Duration(seconds: 10));
      debugPrint('[Bootstrap] BackgroundDownloadService ready.');

      debugPrint('[Bootstrap] Starting TdLibClient...');
      final tdClient = TdLibClient();
      await tdClient.initialize()
          .timeout(const Duration(seconds: 45));
      debugPrint('[Bootstrap] TdLibClient ready.');

      if (mounted) {
        setState(() {
          _tdClient = tdClient;
          _ready = true;
        });
      }
    } on TimeoutException catch (e, st) {
  debugPrint('[Bootstrap] Timeout: $e\n$st');
  if (mounted) {
    setState(() {
      _initError = 'Initialization timed out. TDLib did not respond.\n\n'
          'Check that:\n'
          '• libtdjson.so is bundled in the APK\n'
          '• TELEGRAM_API_ID and TELEGRAM_API_HASH are correct\n\n'
          'Error: $e';
      _initStack = st;
    });
  }
} catch (e, st) {
      debugPrint('[Bootstrap] Error: $e\n$st');
      if (mounted) setState(() => _initError = '$e\n\n$st');  // <-- add st here
      if (mounted) {
        setState(() {
          _initError = e;
          _initStack = st;
        });
      }
    }
  }
  
  

  @override
  Widget build(BuildContext context) {
    // ── Error state ───────────────────────────────────────────────
    if (_initError != null) {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to start',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: SingleChildScrollView(
                        child: Text(
                          '$_initError\n\n$_initStack',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ),
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

    // ── TdLibClient is live — set override, mount stage-2 widget ─
    return ProviderScope(
      overrides: [
        tdlibClientProvider.overrideWithValue(_tdClient!),
      ],
      child: const _AppInner(),
    );
  }
}

// ── Stage 2 bootstrap: inside the overridden ProviderScope ───────
//
// At this point tdlibClientProvider resolves to a real TdLibClient,
// so settingsController and downloadManager can be safely initialized.

class _AppInner extends ConsumerStatefulWidget {
  const _AppInner();

  @override
  ConsumerState<_AppInner> createState() => _AppInnerState();
}

class _AppInnerState extends ConsumerState<_AppInner>
    with WidgetsBindingObserver {
  bool _providersReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initProviders();
  }

  Future<void> _initProviders() async {
    debugPrint('[AppInner] Initializing settings...');
    await ref.read(settingsControllerProvider.notifier).initialize();
    debugPrint('[AppInner] Initializing DownloadManager...');
    await ref.read(downloadManagerProvider).initialize();
    debugPrint('[AppInner] All providers ready.');
    if (mounted) setState(() => _providersReady = true);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_providersReady) return;
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
    if (!_providersReady) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return const TelegramDownloaderApp();
  }
}
