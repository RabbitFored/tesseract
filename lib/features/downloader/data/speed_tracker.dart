import 'dart:async';
import 'dart:collection';

import '../../../core/utils/logger.dart';

/// Tracks download speed by measuring byte deltas every 1 second.
///
/// Maintains per-file speeds and a rolling global speed history
/// of the last 60 data points (60 seconds).
class SpeedTracker {
  SpeedTracker();

  Timer? _timer;
  bool _running = false;

  /// Per-file: last known downloaded_size snapshot.
  final _snapshots = <int, int>{}; // fileId → downloadedSize

  /// Per-file: current bytes/second.
  final _speeds = <int, int>{}; // fileId → bytesPerSecond

  /// Rolling global speed history (last 60 seconds).
  final _history = Queue<int>();
  static const int _maxHistory = 60;

  /// Current global speed (sum of all active file speeds).
  int _globalSpeed = 0;

  // ── Public getters ───────────────────────────────────────────

  int get globalSpeed => _globalSpeed;

  /// Unmodifiable view of the speed history (oldest first).
  List<int> get speedHistory => List.unmodifiable(_history);

  /// Get the current speed for a specific file.
  int getFileSpeed(int fileId) => _speeds[fileId] ?? 0;

  // ── Lifecycle ────────────────────────────────────────────────

  /// Start the 1-second measurement timer.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Log.info('SpeedTracker started', tag: 'SPEED');
  }

  /// Stop tracking. Call when all downloads finish.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _globalSpeed = 0;
    _snapshots.clear();
    _speeds.clear();
    // Don't clear history — keep it for the graph fade-out.
    _history.addLast(0);
    _trimHistory();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  // ── Update interface (called by DownloadManager) ─────────────

  /// Report the current downloaded_size for a file.
  /// Must be called on every TDLib UpdateFile event.
  void reportProgress(int fileId, int downloadedSize) {
    if (!_snapshots.containsKey(fileId)) {
      // First report for this file — seed the snapshot.
      _snapshots[fileId] = downloadedSize;
    }
  }

  /// Remove a file from tracking (completed, paused, removed).
  void removeFile(int fileId) {
    _snapshots.remove(fileId);
    _speeds.remove(fileId);
  }

  // ── Private ──────────────────────────────────────────────────

  void _tick() {
    int totalSpeed = 0;

    for (final fileId in _snapshots.keys.toList()) {
      final prevSize = _snapshots[fileId] ?? 0;
      // The current size will be updated by the next reportProgress call.
      // For now, compute delta from what we last stored.
      final currentSpeed = _speeds[fileId] ?? 0;
      totalSpeed += currentSpeed;
      // Snapshot is already current — speed will be calculated in
      // _computeSpeed called externally.
    }

    _globalSpeed = totalSpeed;

    _history.addLast(_globalSpeed);
    _trimHistory();
  }

  /// Compute speed for a specific file. Call this from DownloadManager
  /// after updating the snapshot.
  int computeSpeed(int fileId, int newDownloadedSize) {
    final prevSize = _snapshots[fileId] ?? newDownloadedSize;
    final delta = (newDownloadedSize - prevSize).clamp(0, double.maxFinite.toInt());
    _snapshots[fileId] = newDownloadedSize;
    _speeds[fileId] = delta;

    // Recalculate global speed as sum of all file speeds.
    _globalSpeed = _speeds.values.fold(0, (sum, s) => sum + s);

    return delta;
  }

  void _trimHistory() {
    while (_history.length > _maxHistory) {
      _history.removeFirst();
    }
  }
}
