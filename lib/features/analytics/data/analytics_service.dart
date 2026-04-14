import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../settings/domain/settings_state.dart';
import '../domain/analytics_event.dart';
import 'analytics_db.dart';

/// Analytics service for tracking download events
class AnalyticsService {
  AnalyticsService() {
    _db = AnalyticsDb();
  }

  late final AnalyticsDb _db;

  AnalyticsDb get db => _db;

  /// Track download started
  Future<void> trackDownloadStarted({
    required int fileId,
    required int fileSize,
    required String fileName,
    int? channelId,
  }) async {
    try {
      final category = SettingsState.categoryForExtension(fileName);

      await _db.recordEvent(AnalyticsEvent(
        eventType: EventType.downloadStarted,
        fileId: fileId,
        fileSize: fileSize,
        channelId: channelId,
        category: category,
        timestamp: DateTime.now(),
      ));

      Log.info('Tracked download started: $fileName', tag: 'ANALYTICS');
    } catch (e) {
      Log.error('Failed to track download started: $e', tag: 'ANALYTICS');
    }
  }

  /// Track download completed
  Future<void> trackDownloadCompleted({
    required int fileId,
    required int fileSize,
    required String fileName,
    int? channelId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final category = SettingsState.categoryForExtension(fileName);

      await _db.recordEvent(AnalyticsEvent(
        eventType: EventType.downloadCompleted,
        fileId: fileId,
        fileSize: fileSize,
        channelId: channelId,
        category: category,
        timestamp: DateTime.now(),
        metadata: metadata,
      ));

      Log.info('Tracked download completed: $fileName', tag: 'ANALYTICS');

      // Check for milestones
      await _checkMilestones();
    } catch (e) {
      Log.error('Failed to track download completed: $e', tag: 'ANALYTICS');
    }
  }

  /// Track download failed
  Future<void> trackDownloadFailed({
    required int fileId,
    required String fileName,
    required String errorReason,
    int? channelId,
  }) async {
    try {
      final category = SettingsState.categoryForExtension(fileName);

      await _db.recordEvent(AnalyticsEvent(
        eventType: EventType.downloadFailed,
        fileId: fileId,
        channelId: channelId,
        category: category,
        timestamp: DateTime.now(),
        metadata: {'error_reason': errorReason},
      ));

      Log.info('Tracked download failed: $fileName', tag: 'ANALYTICS');
    } catch (e) {
      Log.error('Failed to track download failed: $e', tag: 'ANALYTICS');
    }
  }

  /// Track download paused
  Future<void> trackDownloadPaused({
    required int fileId,
    int? channelId,
  }) async {
    try {
      await _db.recordEvent(AnalyticsEvent(
        eventType: EventType.downloadPaused,
        fileId: fileId,
        channelId: channelId,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      Log.error('Failed to track download paused: $e', tag: 'ANALYTICS');
    }
  }

  /// Track download resumed
  Future<void> trackDownloadResumed({
    required int fileId,
    int? channelId,
  }) async {
    try {
      await _db.recordEvent(AnalyticsEvent(
        eventType: EventType.downloadResumed,
        fileId: fileId,
        channelId: channelId,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      Log.error('Failed to track download resumed: $e', tag: 'ANALYTICS');
    }
  }

  /// Check for milestones and return achievement if reached
  Future<String?> _checkMilestones() async {
    try {
      final stats = await _db.getTotalStats();
      final completedDownloads = stats['completedDownloads'] as int;
      final totalBytes = stats['totalBytes'] as int;

      // Check download count milestones
      if (completedDownloads == 10) {
        return '🎉 First 10 downloads!';
      } else if (completedDownloads == 50) {
        return '🎉 50 downloads milestone!';
      } else if (completedDownloads == 100) {
        return '🎉 100 downloads milestone!';
      } else if (completedDownloads == 500) {
        return '🎉 500 downloads milestone!';
      } else if (completedDownloads == 1000) {
        return '🎉 1000 downloads milestone!';
      }

      // Check data size milestones (in GB)
      final totalGB = totalBytes / (1024 * 1024 * 1024);
      if (totalGB >= 1 && totalGB < 1.1) {
        return '🎉 Downloaded 1 GB of data!';
      } else if (totalGB >= 10 && totalGB < 10.1) {
        return '🎉 Downloaded 10 GB of data!';
      } else if (totalGB >= 100 && totalGB < 100.1) {
        return '🎉 Downloaded 100 GB of data!';
      }

      return null;
    } catch (e) {
      Log.error('Failed to check milestones: $e', tag: 'ANALYTICS');
      return null;
    }
  }

  /// Cleanup old analytics data
  Future<void> cleanup({int keepDays = 90}) async {
    await _db.cleanupOldEvents(keepDays: keepDays);
  }

  /// Close database
  Future<void> dispose() async {
    await _db.close();
  }
}

/// Provider for analytics service
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService();
  ref.onDispose(() => service.dispose());
  return service;
});
