import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../settings/data/settings_controller.dart';

/// Centralized notification service for download events.
class NotificationService {
  NotificationService(this._ref) {
    _notifications = FlutterLocalNotificationsPlugin();
  }

  final Ref _ref;
  late final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  // Notification IDs
  static const int _downloadCompleteId = 1000;
  static const int _downloadErrorId = 2000;
  static const int _milestoneId = 3000;
  static const int _progressId = 4000;

  // Notification channels (Android)
  static const String _channelIdComplete = 'download_complete';
  static const String _channelIdError = 'download_error';
  static const String _channelIdMilestone = 'milestone';
  static const String _channelIdProgress = 'download_progress';

  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Only initialize on Android
    if (!Platform.isAndroid) {
      Log.info('Notifications only supported on Android', tag: 'NOTIF');
      return;
    }

    try {
      // Android initialization
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      const initSettings = InitializationSettings(
        android: androidSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request permissions (Android 13+)
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _initialized = true;
      Log.info('NotificationService initialized', tag: 'NOTIF');
    } catch (e) {
      Log.error('Failed to initialize notifications: $e', tag: 'NOTIF');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    Log.info('Notification tapped: $payload', tag: 'NOTIF');

    // TODO: Navigate to appropriate screen based on payload
    // Format: "action:fileId" e.g., "open:12345", "retry:67890"
  }

  /// Check if notifications are enabled and within quiet hours
  bool get _canNotify {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.notificationsEnabled) return false;

    // Check quiet hours
    if (settings.quietHoursEnabled) {
      final now = DateTime.now().hour;
      final start = settings.quietHoursStart;
      final end = settings.quietHoursEnd;

      if (start < end) {
        // Normal range: e.g., 22:00 - 06:00
        if (now >= start && now < end) return false;
      } else {
        // Overnight range: e.g., 22:00 - 06:00
        if (now >= start || now < end) return false;
      }
    }

    return true;
  }

  /// Show download completion notification
  Future<void> notifyDownloadComplete({
    required int fileId,
    required String fileName,
    required int fileSize,
  }) async {
    if (!Platform.isAndroid || !_initialized || !_canNotify) return;

    final settings = _ref.read(settingsControllerProvider);
    if (!settings.notifyOnCompletion) return;

    try {
      final sizeStr = _formatBytes(fileSize);

      await _notifications.show(
        _downloadCompleteId + (fileId % 1000),
        'Download Complete',
        '$fileName ($sizeStr)',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdComplete,
            'Download Complete',
            channelDescription: 'Notifications for completed downloads',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF2AABEE),
            playSound: settings.notificationSound,
            enableVibration: settings.hapticsEnabled,
            actions: [
              const AndroidNotificationAction(
                'open',
                'Open',
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                'share',
                'Share',
                showsUserInterface: true,
              ),
            ],
          ),
        ),
        payload: 'open:$fileId',
      );

      Log.info('Sent completion notification for $fileName', tag: 'NOTIF');
    } catch (e) {
      Log.error('Failed to show completion notification: $e', tag: 'NOTIF');
    }
  }

  /// Show download error notification
  Future<void> notifyDownloadError({
    required int fileId,
    required String fileName,
    required String errorReason,
  }) async {
    if (!Platform.isAndroid || !_initialized || !_canNotify) return;

    final settings = _ref.read(settingsControllerProvider);
    if (!settings.notifyOnError) return;

    try {
      final errorMsg = _formatErrorReason(errorReason);

      await _notifications.show(
        _downloadErrorId + (fileId % 1000),
        'Download Failed',
        '$fileName\n$errorMsg',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdError,
            'Download Errors',
            channelDescription: 'Notifications for failed downloads',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFFEF5350),
            playSound: settings.notificationSound,
            enableVibration: settings.hapticsEnabled,
            actions: [
              const AndroidNotificationAction(
                'retry',
                'Retry',
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                'dismiss',
                'Dismiss',
              ),
            ],
          ),
        ),
        payload: 'retry:$fileId',
      );

      Log.info('Sent error notification for $fileName', tag: 'NOTIF');
    } catch (e) {
      Log.error('Failed to show error notification: $e', tag: 'NOTIF');
    }
  }

  /// Show milestone notification
  Future<void> notifyMilestone({
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid || !_initialized || !_canNotify) return;

    final settings = _ref.read(settingsControllerProvider);
    if (!settings.notifyOnMilestone) return;

    try {
      await _notifications.show(
        _milestoneId,
        title,
        message,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdMilestone,
            'Milestones',
            channelDescription: 'Achievement and milestone notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF66BB6A),
            playSound: settings.notificationSound,
            enableVibration: settings.hapticsEnabled,
          ),
        ),
      );

      Log.info('Sent milestone notification: $title', tag: 'NOTIF');
    } catch (e) {
      Log.error('Failed to show milestone notification: $e', tag: 'NOTIF');
    }
  }

  /// Update ongoing download progress notification
  Future<void> updateProgressNotification({
    required int activeCount,
    required int totalCount,
    required double progress,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;

    try {
      final progressPercent = (progress * 100).toInt();

      await _notifications.show(
        _progressId,
        'Downloading $activeCount file${activeCount == 1 ? '' : 's'}',
        '$progressPercent% complete ($activeCount of $totalCount)',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelIdProgress,
            'Download Progress',
            channelDescription: 'Ongoing download progress',
            importance: Importance.low,
            priority: Priority.low,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF2AABEE),
            showProgress: true,
            maxProgress: 100,
            progress: progressPercent,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
    } catch (e) {
      Log.error('Failed to update progress notification: $e', tag: 'NOTIF');
    }
  }

  /// Cancel progress notification
  Future<void> cancelProgressNotification() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _notifications.cancel(_progressId);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _notifications.cancelAll();
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatErrorReason(String reason) {
    return switch (reason) {
      'corrupted_archive' => 'Archive file is corrupted',
      'password_required' => 'Password required for extraction',
      'unsupported_format' => 'Unsupported archive format',
      'file_not_found' => 'File not found',
      'extraction_failed' => 'Extraction failed',
      'checksum_mismatch' => 'File integrity check failed',
      'max_retries_exceeded' => 'Maximum retry attempts exceeded',
      _ => 'Download failed',
    };
  }
}

/// Provider for notification service
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref);
  return service;
});
