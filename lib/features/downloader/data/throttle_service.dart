import 'dart:async';

import '../../../core/utils/logger.dart';

/// Per-file throttle state.
class _FileThrottle {
  _FileThrottle({required this.limitBps});
  int limitBps;
  int bytesAtWindowStart = 0;
  DateTime windowStart = DateTime.now();
  Timer? pauseTimer;
  bool isPaused = false;
}

/// Bandwidth throttler that works with TDLib's download model.
///
/// TDLib has NO native speed-cap API. Passing `limit > 0` to DownloadFile
/// is a byte-range prefetch for streaming — it causes FILE_DOWNLOAD_LIMIT
/// errors when used for full-file throttling.
///
/// The correct approach is **timed pause/resume**:
///   1. DownloadFile is always called with limit=0 (full file, no range).
///   2. On each UpdateFile progress event, we measure bytes received in the
///      current 1-second window.
///   3. If bytes received >= limitBps, we call CancelDownloadFile and schedule
///      a resume at the start of the next 1-second window.
///   4. On resume, DownloadFile is re-issued from the current offset.
///
/// This gives an effective throughput ≈ limitBps bytes/second.
class ThrottleService {
  ThrottleService();

  /// Global speed cap in bytes/second. 0 = unlimited.
  int limitBps = 0;

  /// Per-file overrides. Key = TDLib fileId, value = bytes/second cap.
  final Map<int, int> _perFileLimits = {};

  /// Active throttle state per file.
  final Map<int, _FileThrottle> _active = {};

  /// Callback: cancel a file's download (TDLib CancelDownloadFile).
  Future<void> Function(int fileId)? onPauseFile;

  /// Callback: resume a file's download from [offset] with limit=0.
  Future<void> Function(int fileId, int offset)? onResumeFile;

  // ── Configuration ─────────────────────────────────────────

  void setFileLimit(int fileId, int bps) {
    if (bps <= 0) {
      _perFileLimits.remove(fileId);
      _stopTracking(fileId);
    } else {
      _perFileLimits[fileId] = bps;
    }
  }

  void removeFileLimit(int fileId) {
    _perFileLimits.remove(fileId);
    _stopTracking(fileId);
  }

  int effectiveLimitFor(int fileId) {
    final perFile = _perFileLimits[fileId];
    if (perFile != null && perFile > 0) return perFile;
    return limitBps;
  }

  bool isThrottled(int fileId) => effectiveLimitFor(fileId) > 0;

  // ── Tracking lifecycle ────────────────────────────────────

  /// Call when a download starts. Initialises the measurement window.
  void startTracking(int fileId, int currentBytes) {
    final cap = effectiveLimitFor(fileId);
    if (cap <= 0) return;
    _active[fileId] = _FileThrottle(limitBps: cap)
      ..bytesAtWindowStart = currentBytes
      ..windowStart = DateTime.now();
    Log.info('Throttle tracking: fileId=$fileId cap=${cap ~/ 1024}KB/s',
        tag: 'THROTTLE');
  }

  void _stopTracking(int fileId) {
    _active[fileId]?.pauseTimer?.cancel();
    _active.remove(fileId);
  }

  // ── Progress measurement ──────────────────────────────────

  /// Called on every UpdateFile event.
  /// [downloadedBytes] = total bytes received so far for this file.
  /// [currentOffset]   = byte offset TDLib is currently at.
  void onProgress(int fileId, int downloadedBytes, int currentOffset) {
    final state = _active[fileId];
    if (state == null || state.isPaused) return;

    final cap = effectiveLimitFor(fileId);
    if (cap <= 0) {
      _stopTracking(fileId);
      return;
    }
    state.limitBps = cap;

    final now = DateTime.now();
    final windowMs = now.difference(state.windowStart).inMilliseconds;
    final bytesThisWindow = downloadedBytes - state.bytesAtWindowStart;

    // If we've received >= limitBps bytes in < 1000ms, pause for the remainder.
    if (bytesThisWindow >= cap && windowMs < 1000) {
      final sleepMs = 1000 - windowMs;
      state.isPaused = true;
      state.pauseTimer?.cancel();

      Log.info(
        'Throttle: fileId=$fileId received ${bytesThisWindow ~/ 1024}KB '
        'in ${windowMs}ms — pausing ${sleepMs}ms',
        tag: 'THROTTLE',
      );

      onPauseFile?.call(fileId);

      state.pauseTimer = Timer(Duration(milliseconds: sleepMs), () {
        if (!_active.containsKey(fileId)) return;
        state.isPaused = false;
        // Reset window for the next measurement period.
        state.bytesAtWindowStart = downloadedBytes;
        state.windowStart = DateTime.now();
        onResumeFile?.call(fileId, currentOffset);
      });
    } else if (windowMs >= 1000) {
      // Window expired — reset for next second regardless.
      state.bytesAtWindowStart = downloadedBytes;
      state.windowStart = now;
    }
  }

  void dispose() {
    for (final state in _active.values) {
      state.pauseTimer?.cancel();
    }
    _active.clear();
    _perFileLimits.clear();
    Log.info('ThrottleService disposed', tag: 'THROTTLE');
  }
}
