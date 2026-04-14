import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/download_manager.dart';
import '../domain/download_item.dart';
import '../domain/download_status.dart';

// ── Database provider (singleton) ──────────────────────────────
// (Removed duplicate instances of DownloadDb)

// ── Live queue stream ──────────────────────────────────────────

/// Emits the full, ordered download queue every time it changes.
/// Items include live `currentSpeed` from the SpeedTracker.
final downloadQueueProvider = StreamProvider<List<DownloadItem>>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  final controller = StreamController<List<DownloadItem>>();

  Future<void> emit() async {
    final items = await manager.db.getAll();
    // Enrich items with live speed data.
    final enriched = items.map((item) {
      if (item.isActive) {
        return item.copyWith(
          currentSpeed: manager.speedTracker.getFileSpeed(item.fileId),
        );
      }
      return item;
    }).toList();
    if (!controller.isClosed) {
      controller.add(enriched);
    }
  }

  final sub = manager.onQueueChanged.listen((_) => emit());
  emit();

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

// ── Filtered convenience providers ─────────────────────────────

final activeDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final queue = ref.watch(downloadQueueProvider);
  return queue.when(
    data: (items) =>
        items.where((i) => i.status == DownloadStatus.downloading).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final completedDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final queue = ref.watch(downloadQueueProvider);
  return queue.when(
    data: (items) =>
        items.where((i) => i.status == DownloadStatus.completed).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final queuedDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final queue = ref.watch(downloadQueueProvider);
  return queue.when(
    data: (items) =>
        items.where((i) => i.status == DownloadStatus.queued).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final pausedDownloadsProvider = Provider<List<DownloadItem>>((ref) {
  final queue = ref.watch(downloadQueueProvider);
  return queue.when(
    data: (items) =>
        items.where((i) => i.status == DownloadStatus.paused).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Summary stats including speed data.
final downloadStatsProvider = Provider<DownloadStats>((ref) {
  final queue = ref.watch(downloadQueueProvider);
  final manager = ref.watch(downloadManagerProvider);

  return queue.when(
    data: (items) => DownloadStats.fromItems(
      items,
      globalSpeed: manager.speedTracker.globalSpeed,
      speedHistory: manager.speedTracker.speedHistory,
    ),
    loading: () => const DownloadStats(),
    error: (_, __) => const DownloadStats(),
  );
});

/// Stats object with speed analytics.
class DownloadStats {
  const DownloadStats({
    this.total = 0,
    this.active = 0,
    this.queued = 0,
    this.paused = 0,
    this.completed = 0,
    this.errors = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.globalSpeed = 0,
    this.speedHistory = const [],
  });

  final int total;
  final int active;
  final int queued;
  final int paused;
  final int completed;
  final int errors;
  final int totalBytes;
  final int downloadedBytes;

  /// Current total download speed in bytes/second.
  final int globalSpeed;

  /// Rolling speed history (last 60 seconds) for sparkline.
  final List<int> speedHistory;

  double get overallProgress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  factory DownloadStats.fromItems(
    List<DownloadItem> items, {
    int globalSpeed = 0,
    List<int> speedHistory = const [],
  }) {
    int active = 0, queued = 0, paused = 0, completed = 0, errors = 0;
    int totalBytes = 0, downloadedBytes = 0;

    for (final item in items) {
      totalBytes += item.totalSize;
      downloadedBytes += item.downloadedSize;
      switch (item.status) {
        case DownloadStatus.downloading:
          active++;
        case DownloadStatus.queued:
          queued++;
        case DownloadStatus.paused:
          paused++;
        case DownloadStatus.completed:
          completed++;
        case DownloadStatus.extracting:
          // Count extracting/verifying files as active — still "in progress".
          active++;
        case DownloadStatus.verifying:
          active++;
        case DownloadStatus.error:
          errors++;
      }
    }

    return DownloadStats(
      total: items.length,
      active: active,
      queued: queued,
      paused: paused,
      completed: completed,
      errors: errors,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      globalSpeed: globalSpeed,
      speedHistory: speedHistory,
    );
  }
}
