import 'dart:async';
import 'dart:io' as io;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_client.dart';
import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../../settings/data/settings_controller.dart';
import '../../settings/domain/settings_state.dart';
import '../../browser/domain/media_message.dart';
import '../domain/download_item.dart';
import '../domain/download_status.dart';
import 'background_service.dart';
import 'download_db.dart';
import 'extraction_service.dart';
import 'resource_monitor.dart';
import 'speed_tracker.dart';

/// Riverpod provider for the singleton [DownloadManager].
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(ref);
  ref.onDispose(() => manager.dispose());
  return manager;
});

class DownloadManager {
  DownloadManager(this._ref) {
    _db = DownloadDb();
    _speed = SpeedTracker();
    _resourceMonitor = ResourceMonitor(_ref);
  }

  final Ref _ref;
  late final DownloadDb _db;
  late final SpeedTracker _speed;
  late final ResourceMonitor _resourceMonitor;
  StreamSubscription<TdObject>? _tdlibSub;
  bool _initialized = false;
  bool _disposed = false;

  final _queueChanged = StreamController<void>.broadcast();
  Stream<void> get onQueueChanged => _queueChanged.stream;

  DownloadDb get db => _db;
  SpeedTracker get speedTracker => _speed;
  ResourceMonitor get resourceMonitor => _resourceMonitor;

  int get _maxConcurrent =>
      _ref.read(settingsControllerProvider).concurrentDownloads;

  // ── Lifecycle ────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Bug 1 fix: Request storage permissions upfront on Android.
    if (Platform.isAndroid) {
      await _ensureStoragePermissions();
    }

    await _db.database;
    await _db.resetStaleDownloads();

    // Wire resource monitor callbacks.
    _resourceMonitor.onConstraintViolated = _onResourceViolated;
    _resourceMonitor.onConstraintRestored = _onResourceRestored;
    await _resourceMonitor.start();

    final client = _ref.read(tdlibClientProvider);
    _tdlibSub = client.updates.listen(_onTdlibUpdate);

    await _processQueue();
    Log.info('DownloadManager initialized (max=$_maxConcurrent)',
        tag: 'DL_MGR');
  }

  void dispose() {
    _disposed = true;
    _tdlibSub?.cancel();
    _queueChanged.close();
    _speed.dispose();
    _resourceMonitor.dispose();
    _db.close();
  }

  /// Bug 1 fix: Request storage permissions at app startup on Android.
  Future<void> _ensureStoragePermissions() async {
    if (!await Permission.storage.isGranted) {
      final result = await Permission.storage.request();
      Log.info('Storage permission: $result', tag: 'DL_MGR');
    }
    if (!await Permission.manageExternalStorage.isGranted) {
      final result = await Permission.manageExternalStorage.request();
      Log.info('Manage storage permission: $result', tag: 'DL_MGR');
    }
  }

  // ── Resource constraint callbacks ────────────────────────────

  void _onResourceViolated(String reason) {
    Log.info('Resource constraint: $reason — pausing all', tag: 'DL_MGR');
    pauseAll();
    BackgroundDownloadService.pushProgressToNotification(
      activeCount: 0,
      totalCount: 0,
      overallProgress: 0,
    );
  }

  void _onResourceRestored(String reason) {
    Log.info('Resource restored: $reason — resuming', tag: 'DL_MGR');
    resumeAll();
  }

  // ── App lifecycle hooks ──────────────────────────────────────

  Future<void> onAppBackgrounded() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final active = await _db.activeCount();
    if (active > 0) {
      await BackgroundDownloadService.start();
      _pushProgressToService();
    }
  }

  Future<void> onAppResumed() async {
    _notifyChange();
    _resourceMonitor.recheck();
    final active = await _db.activeCount();
    final queued = (await _db.getByStatus(DownloadStatus.queued)).length;
    if (active == 0 && queued == 0 && (Platform.isAndroid || Platform.isIOS)) {
      await BackgroundDownloadService.stop();
    }
  }

  // ── TDLib update handler ─────────────────────────────────────

  void _onTdlibUpdate(TdObject event) {
    if (event is UpdateFile) {
      _handleFileUpdate(event.file);
    }
  }

  Future<void> _handleFileUpdate(File file) async {
    final item = await _db.getByFileId(file.id);
    if (item == null) return;

    final local = file.local;
    final isComplete = local.isDownloadingCompleted;
    final downloadedSize = local.downloadedSize;

    _speed.reportProgress(file.id, downloadedSize);
    _speed.computeSpeed(file.id, downloadedSize);

    // Fix Pause Bug: If the user currently set the item to paused, but TDLib is still processing the cancellation
    // (local.isDownloadingActive is true), we must not overwrite our paused status back to downloading.
    var newStatus = item.status;
    if (isComplete) {
      newStatus = DownloadStatus.completed;
    } else if (item.status != DownloadStatus.paused && item.status != DownloadStatus.error) {
      newStatus = local.isDownloadingActive
          ? DownloadStatus.downloading
          : item.status;
    }

    if (isComplete && local.path.isNotEmpty) {
      // Update both progress AND the actual local path from TDLib.
      await _db.updateProgressAndPath(
        file.id,
        downloadedSize: downloadedSize,
        status: newStatus,
        localPath: local.path,
      );
    } else {
      await _db.updateProgress(
        file.id,
        downloadedSize: downloadedSize,
        status: newStatus,
      );
    }

    _notifyChange();
    _pushProgressToService();

    if (isComplete) {
      Log.tdlib('Download complete: fileId=${file.id} path=${local.path}');
      _speed.removeFile(file.id);

      // Copy the file to the user-accessible Downloads folder and update DB.
      final publicPath = await _exportCompletedFile(item, local.path);
      if (publicPath != null) {
        await _db.updateProgressAndPath(
          item.fileId,
          downloadedSize: item.totalSize,
          status: DownloadStatus.completed,
          localPath: publicPath,
        );
        // Also pass publicPath to auto-extractor so it extracts to the correct base.
        await _autoExtractIfNeeded(item, publicPath);
      } else {
        await _autoExtractIfNeeded(item, local.path);
      }

      await _processQueue();

      final remaining = await _db.activeCount();
      final queued = (await _db.getByStatus(DownloadStatus.queued)).length;
      if (remaining == 0 && queued == 0) {
        _speed.stop();
        await BackgroundDownloadService.stop();
      }
    }
  }

  // ── Public API ───────────────────────────────────────────────

  /// Enqueue a download with smart de-duplication.
  Future<bool> enqueue(DownloadItem item) async {
    // ── De-duplication check ───────────────────────────────
    // 1. Check if fileId already exists in DB.
    final existing = await _db.getByFileId(item.fileId);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        // Already downloaded — skip re-download.
        Log.info(
          'De-dup: fileId=${item.fileId} already completed',
          tag: 'DL_MGR',
        );
        return false; // signal "already exists"
      }
      // If queued/paused/error, just re-queue.
      if (existing.status != DownloadStatus.downloading) {
        await _db.updateStatus(item.fileId, DownloadStatus.queued);
        _notifyChange();
        await _processQueue();
        return true;
      }
      return false; // already downloading
    }

    // 2. Check if a file with same size and name is already completed.
    final allCompleted = await _db.getByStatus(DownloadStatus.completed);
    for (final completed in allCompleted) {
      if (completed.totalSize == item.totalSize &&
          completed.fileName == item.fileName) {
        // Check if the local file actually exists.
        final localFile = IOFile(completed.localPath);
        if (await localFile.exists()) {
          Log.info(
            'De-dup: "${item.fileName}" (${item.totalSize}B) matches '
            'completed fileId=${completed.fileId}',
            tag: 'DL_MGR',
          );
          // Insert as completed pointing to existing path.
          await _db.insert(item.copyWith(
            localPath: completed.localPath,
            downloadedSize: completed.totalSize,
            status: DownloadStatus.completed,
          ));
          _notifyChange();
          return false; // signal "de-duped"
        }
      }
    }

    // ── Check resource constraints before enqueuing ─────────
    if (_resourceMonitor.isPausedByResource) {
      // Enqueue but don't start downloading.
      await _db.insert(item.copyWith(status: DownloadStatus.paused));
      _notifyChange();
      return true;
    }

    // ── Normal enqueue ─────────────────────────────────────
    await _db.insert(item);
    _notifyChange();
    await _processQueue();
    return true;
  }

  /// Enqueue a download from a Telegram message link.
  /// Returns null on success, or an error message if it fails.
  ///
  /// Enforces a timeout on [GetMessageLinkInfo] via send()'s built-in
  /// 30-second timeout. Previous double-timeout left orphaned listeners.
  Future<String?> enqueueFromUrl(String url) async {
    final send = _ref.read(tdlibSendProvider);

    TdObject? linkInfoResult;
    try {
      linkInfoResult = await send(GetMessageLinkInfo(url: url));
    } catch (e) {
      return 'Failed to look up link: $e';
    }

    if (linkInfoResult is TdError) {
      return linkInfoResult.message;
    }

    if (linkInfoResult is! MessageLinkInfo) {
      return 'Invalid link';
    }

    final message = linkInfoResult.message;

    if (message == null) {
      return 'Message not accessible. Please ensure you have access to the chat.';
    }

    final media = MediaMessage.fromTdlibMessage(message);
    if (media == null) {
      return 'No downloadable media found in this message';
    }

    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/downloads/${media.fileName}';

    final enqueued = await enqueue(DownloadItem(
      fileId: media.fileId,
      localPath: localPath,
      totalSize: media.fileSize,
      fileName: media.fileName,
      chatId: media.chatId,
      messageId: media.messageId,
    ));

    if (!enqueued) {
      return 'File is already in the queue or downloaded';
    }

    return null; // Success
  }

  Future<void> downloadFile(int fileId) async {
    // Check resource constraints.
    if (_resourceMonitor.isPausedByResource) return;

    final send = _ref.read(tdlibSendProvider);
    await _db.updateStatus(fileId, DownloadStatus.downloading);
    _notifyChange();

    _speed.start();

    final result = await send(DownloadFile(
      fileId: fileId,
      priority: 32, // 32 is the highest priority in TDLib
      offset: 0,
      limit: 0,
      synchronous: false,
    ));

    _handleTdlibResult(fileId, result);

    if (Platform.isAndroid || Platform.isIOS) {
      await BackgroundDownloadService.start();
      _pushProgressToService();
    }
  }

  Future<void> pauseDownload(int fileId) async {
    final send = _ref.read(tdlibSendProvider);
    await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
    await _db.updateStatus(fileId, DownloadStatus.paused);
    _speed.removeFile(fileId);
    _notifyChange();
    _pushProgressToService();
    await _processQueue();
  }

  Future<void> resumeDownload(int fileId) async {
    if (_resourceMonitor.isPausedByResource) return;
    await _db.updateStatus(fileId, DownloadStatus.queued);
    _notifyChange();
    await _processQueue();
  }

  /// Bug 3 fix: Dedicated retry method that fully resets download state.
  /// Unlike resumeDownload(), this clears downloaded progress and error state
  /// so TDLib starts fresh instead of trying to resume a corrupted partial.
  Future<void> retryDownload(int fileId) async {
    if (_resourceMonitor.isPausedByResource) return;

    // Cancel any stale TDLib state for this file.
    final send = _ref.read(tdlibSendProvider);
    await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
    await send(DeleteFile(fileId: fileId)); // Force TDLib to discard broken physical chunk

    // Reset progress, error state, and re-queue.
    await _db.resetForRetry(fileId);
    _speed.removeFile(fileId);
    _notifyChange();
    await _processQueue();
  }

  Future<void> setPriority(int fileId, int priority) async {
    await _db.updatePriority(fileId, priority);
    _notifyChange();
  }

  Future<void> removeFromQueue(int fileId) async {
    final item = await _db.getByFileId(fileId);
    if (item != null) {
      final send = _ref.read(tdlibSendProvider);
      if (item.isActive) {
        await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
        _speed.removeFile(fileId);
      }
      // Delete from TDLib completely to prevent "sticky" completion on re-add
      await send(DeleteFile(fileId: fileId));
    }
    await _db.delete(fileId);
    _notifyChange();
    _pushProgressToService();
    await _processQueue();
  }

  /// Remove multiple downloads by fileId (batch delete).
  Future<void> removeMultiple(List<int> fileIds) async {
    final send = _ref.read(tdlibSendProvider);
    for (final fileId in fileIds) {
      final item = await _db.getByFileId(fileId);
      if (item != null) {
        if (item.isActive) {
          await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
          _speed.removeFile(fileId);
        }
        await send(DeleteFile(fileId: fileId));
      }
      await _db.delete(fileId);
    }
    _notifyChange();
    _pushProgressToService();
    await _processQueue();
  }

  Future<void> pauseAll() async {
    final active = await _db.getByStatus(DownloadStatus.downloading);
    for (final item in active) {
      await pauseDownload(item.fileId);
    }
  }

  Future<void> resumeAll() async {
    if (_resourceMonitor.isPausedByResource) return;
    final paused = await _db.getByStatus(DownloadStatus.paused);
    for (final item in paused) {
      await _db.updateStatus(item.fileId, DownloadStatus.queued);
    }
    _notifyChange();
    await _processQueue();
  }

  // ── Queue processor ──────────────────────────────────────────

  Future<void> _processQueue() async {
    if (_resourceMonitor.isPausedByResource) return;

    final activeCount = await _db.activeCount();
    final slotsAvailable = _maxConcurrent - activeCount;

    if (slotsAvailable <= 0) return;

    final next = await _db.nextQueued(limit: slotsAvailable);
    for (final item in next) {
      Log.tdlib('Starting download: fileId=${item.fileId}, '
          'priority=${item.priority}');
      await downloadFile(item.fileId);
    }
  }

  // ── Smart categorization ─────────────────────────────────────

  /// Exports the downloaded file to the user's chosen download directory.
  /// Returns the new path on success, or null if it failed.
  Future<String?> _exportCompletedFile(
      DownloadItem item, String sourcePath) async {
    final settingsNotifier = _ref.read(settingsControllerProvider.notifier);
    if (sourcePath.isEmpty) {
      Log.error('Export skipped: source path is empty', tag: 'DL_MGR');
      return null;
    }

    try {
      // Best-effort permission request before copying (safety net — Bug 1
      // fix ensures these are already granted at startup on Android).
      if (Platform.isAndroid) {
        if (!await Permission.storage.isGranted) {
          await Permission.storage.request();
        }
        if (!await Permission.manageExternalStorage.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      }

      // Read the CURRENT download path from settings state (not stale).
      final targetPath = settingsNotifier.resolveDownloadPath(item.fileName);
      Log.info('Export target: $targetPath', tag: 'DL_MGR');

      final targetFile = IOFile(targetPath);

      // Create parent directories.
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
        Log.info('Created directory: ${targetFile.parent.path}', tag: 'DL_MGR');
      }

      final sourceFile = IOFile(sourcePath);
      if (!await sourceFile.exists()) {
        Log.error('Source file missing: $sourcePath', tag: 'DL_MGR');
        return null;
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await sourceFile.copy(targetPath);
      Log.info('Exported: ${item.fileName} → $targetPath', tag: 'DL_MGR');

      try {
        if (Platform.isAndroid) {
          const platform = MethodChannel('tesseract/media_scanner');
          await platform.invokeMethod('scanFile', {'path': targetPath});
        }
      } catch (e) {
        Log.error('Failed to trigger media scan for $targetPath: $e', tag: 'DL_MGR');
      }

      return targetPath;
    } catch (e) {
      Log.error('Failed to export file "${item.fileName}": $e', error: e, tag: 'DL_MGR');
    }
    return null;
  }

  // ── Auto-extraction ──────────────────────────────────────────

  Future<void> _autoExtractIfNeeded(
      DownloadItem item, String sourcePath) async {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.autoExtractArchives) return;
    if (!SettingsState.isArchive(item.fileName)) return;
    if (sourcePath.isEmpty) return;

    // Mark as extracting in DB — UI shows indeterminate progress.
    await _db.updateStatusWithReason(
        item.fileId, DownloadStatus.extracting, '');
    _notifyChange();

    // Determine target directory.
    final baseName = item.fileName.contains('.')
        ? item.fileName.substring(0, item.fileName.lastIndexOf('.'))
        : item.fileName;
    final targetDir = '${settings.downloadBasePath}/Archives/$baseName';

    // Run extraction in a separate isolate.
    // The isolate returns a typed result — it does NOT touch SQLite or Riverpod.
    final result = await ExtractionService.extract(
      sourcePath: sourcePath,
      targetDir: targetDir,
      deleteOriginalOnSuccess: true, // Phase 10: clean up original archive.
    );

    if (result.success) {
      Log.info(
        'Extracted ${result.extractedCount} files from ${item.fileName}'
        '${result.originalDeleted ? ' (original deleted)' : ''}',
        tag: 'DL_MGR',
      );
      // Clear any previous error reason and mark completed.
      await _db.updateStatusWithReason(
          item.fileId, DownloadStatus.completed, '');
    } else {
      // Phase 10: Map specific error types to persisted error reasons.
      final reason = result.errorType.reason;
      Log.error(
        'Extraction failed [${result.errorType.name}] for ${item.fileName}: '
        '${result.errorMessage}',
        tag: 'DL_MGR',
      );
      // Set error status with specific reason for contextual UI badges.
      await _db.updateStatusWithReason(
          item.fileId, DownloadStatus.error, reason);
    }

    _notifyChange();
  }

  // ── Background service communication ─────────────────────────

  Future<void> _pushProgressToService() async {
    final all = await _db.getAll();
    int active = 0;
    int totalBytes = 0;
    int downloadedBytes = 0;

    for (final item in all) {
      if (item.status == DownloadStatus.downloading) active++;
      if (item.status != DownloadStatus.completed) {
        totalBytes += item.totalSize;
        downloadedBytes += item.downloadedSize;
      }
    }

    final progress =
        totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

    BackgroundDownloadService.pushProgressToNotification(
      activeCount: active,
      totalCount: all.length,
      overallProgress: progress,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  void _handleTdlibResult(int fileId, TdObject? result) {
    if (result is TdError) {
      Log.error('TDLib download error for fileId=$fileId: '
          '${result.code} ${result.message}');
      _db.updateStatus(fileId, DownloadStatus.error);
      _speed.removeFile(fileId);
      _notifyChange();
    }
  }

  void _notifyChange() {
    if (!_disposed && !_queueChanged.isClosed) {
      _queueChanged.add(null);
    }
  }
}

// Alias for dart:io.File to avoid shadowing the TDLib File type.
typedef IOFile = io.File;
typedef IODirectory = io.Directory;
