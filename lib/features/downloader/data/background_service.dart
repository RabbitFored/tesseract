import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

import '../../../core/utils/logger.dart';

/// Port name the background isolate registers so the main isolate can
/// push progress updates to the foreground notification.
const String kBackgroundPortName = 'tg_downloader_bg_port';

/// Port name of the main isolate (registered in main.dart).
const String kMainIsolatePortName = 'tg_downloader_main_port';

/// Manages the Android foreground service that keeps the process alive
/// while downloads are active.
///
/// **Architecture rule**: This service runs in a SEPARATE Dart isolate.
/// It must NEVER:
///   - Initialize or access TDLib (would cause DB lock)
///   - Open or query SQLite (would cause DB lock)
///   - Import any Riverpod providers
///
/// Its sole responsibilities are:
///   1. Keep the Android process alive via foreground notification
///   2. Receive progress updates from the main isolate via [SendPort]
///   3. Update the notification content with download stats
class BackgroundDownloadService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Configure the service. Call once from [main] before [runApp].
  static Future<void> initialize() async {
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: false,
        initialNotificationTitle: 'Telegram Downloader',
        initialNotificationContent: 'Ready',
        foregroundServiceNotificationId: 8888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
    );
  }

  /// Start the keep-alive service. Call when downloads begin.
  static Future<void> start() async {
    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      Log.info('Background service started (keep-alive)', tag: 'BG_SVC');
    }
  }

  /// Stop the keep-alive service. Call when all downloads finish.
  static Future<void> stop() async {
    _service.invoke('stop');
    Log.info('Background service stopped', tag: 'BG_SVC');
  }

  /// Whether the service is currently running.
  static Future<bool> get isRunning => _service.isRunning();

  /// Push download progress from the MAIN isolate to the background
  /// isolate's notification via [IsolateNameServer].
  static void pushProgressToNotification({
    required int activeCount,
    required int totalCount,
    required double overallProgress,
  }) {
    final bgPort = IsolateNameServer.lookupPortByName(kBackgroundPortName);
    if (bgPort == null) return;

    bgPort.send({
      'action': 'update_notification',
      'active': activeCount,
      'total': totalCount,
      'progress': overallProgress,
    });
  }
}

// ── Headless isolate entry points ────────────────────────────────
// These run in a SEPARATE isolate. No TDLib. No SQLite. No Riverpod.

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ── Register this isolate's receive port ──────────────────────
  // The main isolate pushes progress updates here.
  IsolateNameServer.removePortNameMapping(kBackgroundPortName);
  final bgReceivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    bgReceivePort.sendPort,
    kBackgroundPortName,
  );

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // ── Listen for progress updates from main isolate ─────────────
  bgReceivePort.listen((message) {
    if (message is Map<String, dynamic> && service is AndroidServiceInstance) {
      final action = message['action'] as String?;

      if (action == 'update_notification') {
        final active = message['active'] as int? ?? 0;
        final total = message['total'] as int? ?? 0;
        final progress = message['progress'] as double? ?? 0.0;
        final pct = (progress * 100).toInt();

        service.setForegroundNotificationInfo(
          title: 'Downloading $active of $total files',
          content: 'Overall progress: $pct%',
        );
      }
    }
  });

  // ── Listen for stop command from main isolate ─────────────────
  service.on('stop').listen((_) {
    IsolateNameServer.removePortNameMapping(kBackgroundPortName);
    bgReceivePort.close();
    service.stopSelf();
  });

  // ── Heartbeat: periodically request status from main isolate ──
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      final isFg = await service.isForegroundService();
      if (!isFg) {
        timer.cancel();
        return;
      }
    }

    // Ask the main isolate for the latest download stats.
    final mainPort = IsolateNameServer.lookupPortByName(kMainIsolatePortName);
    mainPort?.send({'action': 'request_status'});
  });
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
