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
import '../../notifications/data/notification_service.dart';
import '../../settings/data/haptic_helper.dart';
import '../../settings/data/settings_controller.dart';
import '../../settings/domain/settings_state.dart' as app_settings;
import '../../browser/domain/media_message.dart';
import '../domain/download_item.dart';
import '../domain/download_status.dart';
import 'background_service.dart';
import 'checksum_service.dart';
import 'cleanup_service.dart';
import 'download_db.dart';
import 'extraction_service.dart';
import 'mirror_controller.dart';
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
    _mirror = MirrorController(_ref);
  }

  final Ref _ref;
  late final DownloadDb _db;
  late final SpeedTracker _speed;
  late final ResourceMonitor _resourceMonitor;
  late final MirrorController _mirror;
  StreamSubscription<TdObject>? _tdlibSub;
  Timer? _schedulePoller;
  Timer? _autoSyncTimer;
  bool _initialized = false;
  bool _disposed = false;

  final _queueChanged = StreamController<void>.broadcast();
  Stream<void> get onQueueChanged => _queueChanged.stream;

  DownloadDb get db => _db;
  SpeedTracker get speedTracker => _speed;
  ResourceMonitor get resourceMonitor => _resourceMonitor;
  MirrorController get mirrorController => _mirror;

  int get _maxConcurrent =>
      _ref.read(settingsControllerProvider).concurrentDownloads;

  // ── Lifecycle ────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      await _ensureStoragePermissions();
    }

    await _db.database;
    await _db.resetStaleDownloads();

    // Initialize notification service
    final notificationService = _ref.read(notificationServiceProvider);
    await notificationService.initialize();

    _resourceMonitor.onConstraintViolated = _onResourceViolated;
    _resourceMonitor.onConstraintRestored = _onResourceRestored;
    await _resourceMonitor.start();

    // Apply proxy if configured.
    final settings = _ref.read(settingsControllerProvider);
    if (settings.proxyEnabled) {
      await _applyProxy(settings);
    }

    final client = _ref.read(tdlibClientProvider);
    _tdlibSub = client.updates.listen(_onTdlibUpdate);

    // Start channel mirror listener — pass enqueue as callback to avoid
    // a circular provider dependency (MirrorController is owned by this manager).
    _mirror.start(enqueuer: enqueue);

    // Poll for scheduled downloads every minute.
    _schedulePoller = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _processScheduledItems(),
    );

    // Check for auto-sync mirror rules every 15 minutes.
    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _checkAutoSyncRules(),
    );

    // Run auto-cleanup on startup if enabled.
    await _runAutoCleanupIfNeeded();

    await _processQueue();
    Log.info('DownloadManager initialized (max=$_maxConcurrent)',
        tag: 'DL_MGR');
  }

  void dispose() {
    _disposed = true;
    _tdlibSub?.cancel();
    _schedulePoller?.cancel();
    _autoSyncTimer?.cancel();
    _queueChanged.close();
    _speed.dispose();
    _resourceMonitor.dispose();
    _mirror.dispose();
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

  // ── Proxy ────────────────────────────────────────────────────

  Future<void> _applyProxy(app_settings.SettingsState settings) async {
    final send = _ref.read(tdlibSendProvider);
    try {
      // First disable all existing proxies.
      final proxies = await send(const GetProxies());
      if (proxies is Proxies) {
        for (final p in proxies.proxies) {
          await send(RemoveProxy(proxyId: p.id));
        }
      }

      if (!settings.proxyEnabled ||
          settings.proxyHost.isEmpty ||
          settings.proxyType == app_settings.ProxyType.none) {
        return;
      }

      switch (settings.proxyType) {
        case app_settings.ProxyType.socks5:
          await send(AddProxy(
            server: settings.proxyHost,
            port: settings.proxyPort,
            enable: true,
            type: ProxyTypeSocks5(
              username: settings.proxyUsername,
              password: settings.proxyPassword,
            ),
          ));
          Log.info(
            'SOCKS5 proxy applied: ${settings.proxyHost}:${settings.proxyPort}',
            tag: 'DL_MGR',
          );
        case app_settings.ProxyType.mtproto:
          await send(AddProxy(
            server: settings.proxyHost,
            port: settings.proxyPort,
            enable: true,
            type: ProxyTypeMtproto(secret: settings.proxySecret),
          ));
          Log.info(
            'MTProto proxy applied: ${settings.proxyHost}:${settings.proxyPort}',
            tag: 'DL_MGR',
          );
        case app_settings.ProxyType.none:
          break;
      }
    } catch (e) {
      Log.error('Failed to apply proxy: $e', tag: 'DL_MGR');
    }
  }

  /// Re-apply proxy settings (called when settings change).
  Future<void> reapplyProxy() async {
    final settings = _ref.read(settingsControllerProvider);
    await _applyProxy(settings);
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

    var newStatus = item.status;
    if (isComplete) {
      newStatus = DownloadStatus.completed;
    } else if (item.status != DownloadStatus.paused && item.status != DownloadStatus.error) {
      if (local.isDownloadingActive) {
        newStatus = DownloadStatus.downloading;
      } else {
        // Network drop or unexpected stop — schedule auto-retry.
        newStatus = DownloadStatus.error;
        _scheduleAutoRetry(item);
      }
    }

    if (isComplete && local.path.isNotEmpty) {
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

      // Haptic feedback for completion
      try {
        final haptic = _ref.read(hapticHelperProvider);
        haptic.success();
      } catch (_) {
        // Ignore haptic errors
      }

      // Notification for completion
      try {
        final notificationService = _ref.read(notificationServiceProvider);
        await notificationService.notifyDownloadComplete(
          fileId: file.id,
          fileName: item.fileName,
          fileSize: item.totalSize,
        );
      } catch (e) {
        Log.error('Failed to send completion notification: $e', tag: 'DL_MGR');
      }

      final publicPath = await _exportCompletedFile(item, local.path);
      final finalPath = publicPath ?? local.path;

      if (publicPath != null) {
        await _db.updateProgressAndPath(
          item.fileId,
          downloadedSize: item.totalSize,
          status: DownloadStatus.completed,
          localPath: publicPath,
        );
      }

      // Checksum verification.
      final settings = _ref.read(settingsControllerProvider);
      if (settings.verifyChecksums && item.checksumMd5.isNotEmpty) {
        await _verifyChecksum(item, finalPath);
      } else {
        await _autoExtractIfNeeded(item, finalPath);
      }

      await _processQueue();

      final remaining = await _db.activeCount();
      final queued = (await _db.getByStatus(DownloadStatus.queued)).length;
      if (remaining == 0 && queued == 0) {
        _speed.stop();
        await BackgroundDownloadService.stop();
        await _runAutoCleanupIfNeeded();
      }
    }
  }

  // ── Checksum verification ────────────────────────────────────

  Future<void> _verifyChecksum(DownloadItem item, String filePath) async {
    Log.info('Verifying checksum for ${item.fileName}', tag: 'DL_MGR');
    await _db.updateStatusWithReason(
        item.fileId, DownloadStatus.verifying, '');
    _notifyChange();

    final ok = await ChecksumService.verifyMd5(filePath, item.checksumMd5);

    if (ok) {
      Log.info('Checksum OK for ${item.fileName}', tag: 'DL_MGR');
      await _db.updateStatusWithReason(
          item.fileId, DownloadStatus.completed, '');
      await _autoExtractIfNeeded(item, filePath);
    } else {
      Log.error('Checksum MISMATCH for ${item.fileName}', tag: 'DL_MGR');
      await _db.updateStatusWithReason(
          item.fileId, DownloadStatus.error, 'checksum_mismatch');
    }
    _notifyChange();
  }

  // ── Auto-retry with exponential backoff ──────────────────────

  void _scheduleAutoRetry(DownloadItem item) {
    final settings = _ref.read(settingsControllerProvider);
    if (settings.maxAutoRetries <= 0) return;
    if (item.retryCount >= settings.maxAutoRetries) {
      Log.info(
        'Max retries (${settings.maxAutoRetries}) reached for ${item.fileName}',
        tag: 'DL_MGR',
      );
      _db.updateStatusWithReason(
          item.fileId, DownloadStatus.error, 'max_retries_exceeded');
      _notifyChange();
      return;
    }

    // Exponential backoff: base * 2^retryCount seconds.
    final delaySeconds =
        settings.retryBackoffBaseSeconds * (1 << item.retryCount);
    final capped = delaySeconds.clamp(1, 300); // max 5 minutes

    Log.info(
      'Auto-retry ${item.retryCount + 1}/${settings.maxAutoRetries} '
      'for ${item.fileName} in ${capped}s',
      tag: 'DL_MGR',
    );

    Timer(Duration(seconds: capped), () async {
      if (_disposed) return;
      await _db.incrementRetryCount(item.fileId);
      await retryDownload(item.fileId);
    });
  }

  // ── Scheduled downloads ──────────────────────────────────────

  Future<void> _processScheduledItems() async {
    final due = await _db.getDueScheduledItems();
    for (final item in due) {
      // Clear the scheduled_at so it won't be picked up again.
      await _db.updateStatus(item.fileId, DownloadStatus.queued);
    }
    if (due.isNotEmpty) {
      _notifyChange();
      await _processQueue();
    }
  }

  // ── Auto-sync mirror rules ───────────────────────────────────

  Future<void> _checkAutoSyncRules() async {
    if (_disposed) return;
    final settings = _ref.read(settingsControllerProvider);
    final controller = _ref.read(settingsControllerProvider.notifier);

    for (int i = 0; i < settings.mirrorRules.length; i++) {
      final rule = settings.mirrorRules[i];
      if (!rule.enabled) continue;
      if (!rule.isDueForSync) continue;

      Log.info(
        'Auto-sync: syncing ${rule.channelTitle} (interval=${rule.autoSyncInterval.label})',
        tag: 'DL_MGR',
      );

      try {
        final count = await _mirror.syncRule(rule);
        Log.info(
          'Auto-sync: ${rule.channelTitle} enqueued $count items',
          tag: 'DL_MGR',
        );

        // Update lastSyncedAt timestamp.
        await controller.updateMirrorRule(
          i,
          rule.copyWith(lastSyncedAt: DateTime.now()),
        );
      } catch (e) {
        Log.error(
          'Auto-sync failed for ${rule.channelTitle}: $e',
          tag: 'DL_MGR',
        );
      }
    }
  }

  // ── Auto-cleanup ─────────────────────────────────────────────

  Future<void> _runAutoCleanupIfNeeded() async {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.autoCleanupEnabled) return;

    final result = await CleanupService.run(
      db: _db,
      afterDays: settings.autoCleanupAfterDays,
      minFreeMb: settings.autoCleanupMinFreeMb,
      downloadBasePath: settings.downloadBasePath,
    );

    if (result.deletedCount > 0) {
      Log.info(
        'Auto-cleanup: removed ${result.deletedCount} files, '
        'freed ${result.freedBytes ~/ 1024}KB',
        tag: 'DL_MGR',
      );
      _notifyChange();
    }
  }

  /// Manually trigger a cleanup pass.
  Future<CleanupResult> runCleanupNow({Set<int> keepFileIds = const {}}) async {
    final settings = _ref.read(settingsControllerProvider);
    final result = await CleanupService.run(
      db: _db,
      afterDays: settings.autoCleanupAfterDays,
      minFreeMb: settings.autoCleanupMinFreeMb,
      keepFileIds: keepFileIds,
      downloadBasePath: settings.downloadBasePath,
    );
    _notifyChange();
    return result;
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
    if (_resourceMonitor.isPausedByResource) return;
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.isWithinSchedule) return;

    final send = _ref.read(tdlibSendProvider);
    await _db.updateStatus(fileId, DownloadStatus.downloading);
    _notifyChange();
    _speed.start();

    // TDLib priority 1–32. We use 32 (max) for user-initiated downloads.
    // Background/mirror downloads use lower priority so user downloads
    // always get bandwidth first. There is no TDLib API for a hard speed
    // cap — priority is the only native throttle mechanism available.
    final item = await _db.getByFileId(fileId);
    final priority = item?.mirrorChannelId != 0 ? 1 : 32;

    final result = await send(DownloadFile(
      fileId: fileId,
      priority: priority,
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

  /// Update global bandwidth throttle limit.
  /// NOTE: TDLib has no native speed-cap API. This updates the setting
  /// for display purposes; actual throttling is not possible without
  /// causing TCP session drops. Use concurrent download count to limit
  /// overall bandwidth usage instead.
  void updateSpeedLimit(int bps) {
    Log.info(
      'Speed limit setting: ${bps == 0 ? "unlimited" : "${bps ~/ 1024}KB/s"} '
      '(display only — use concurrent downloads to limit bandwidth)',
      tag: 'DL_MGR',
    );
  }

  Future<void> pauseDownload(int fileId) async {
    final send = _ref.read(tdlibSendProvider);
    await _db.updateStatus(fileId, DownloadStatus.paused);
    _notifyChange();
    await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
    _speed.removeFile(fileId);
    _pushProgressToService();
    await _processQueue();
  }

  Future<void> resumeDownload(int fileId) async {
    if (_resourceMonitor.isPausedByResource) return;
    await _db.updateStatus(fileId, DownloadStatus.queued);
    _notifyChange();
    await _processQueue();
  }

  Future<void> retryDownload(int fileId) async {
    if (_resourceMonitor.isPausedByResource) return;

    final item = await _db.getByFileId(fileId);
    if (item == null) return;

    final send = _ref.read(tdlibSendProvider);
    await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
    await send(DeleteFile(fileId: fileId));

    int currentFileId = fileId;

    if (item.chatId != 0 && item.messageId != 0) {
      try {
        final messageResult = await send(GetMessage(
          chatId: item.chatId,
          messageId: item.messageId,
        ));
        
        if (messageResult is Message) {
          final media = MediaMessage.fromTdlibMessage(messageResult);
          if (media != null && media.fileId != currentFileId) {
            await _db.migrateFileId(oldFileId: currentFileId, newFileId: media.fileId);
            currentFileId = media.fileId;
          }
        }
      } catch (e) {
        Log.error('Failed to rebuild file mapping: $e', tag: 'DL_MGR');
      }
    }

    await _db.resetForRetry(currentFileId);
    _speed.removeFile(currentFileId);
    _notifyChange();

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _processQueue();
  }

  /// Manual retry — resets the retry counter so the user gets fresh attempts.
  Future<void> manualRetry(int fileId) async {
    await _db.resetRetryCount(fileId);
    await retryDownload(fileId);
  }

  Future<void> setPriority(int fileId, int priority) async {
    await _db.updatePriority(fileId, priority);
    _notifyChange();
  }

  /// Set a per-file bandwidth cap.
  /// NOTE: TDLib has no safe speed-cap API — this is a no-op kept for
  /// API compatibility. Use concurrent download count to limit bandwidth.
  void setFileSpeedLimit(int fileId, int bps) {
    Log.info('setFileSpeedLimit: no-op (TDLib has no safe speed-cap API)',
        tag: 'DL_MGR');
  }

  Future<void> removeFromQueue(int fileId) async {
    final item = await _db.getByFileId(fileId);
    if (item != null) {
      final send = _ref.read(tdlibSendProvider);
      if (item.isActive) {
        await send(CancelDownloadFile(fileId: fileId, onlyIfPending: false));
        _speed.removeFile(fileId);
      }
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

    // Respect the download schedule.
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.isWithinSchedule) {
      Log.info('Outside schedule window — queue paused', tag: 'DL_MGR');
      return;
    }

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
      if (Platform.isAndroid) {
        if (!await Permission.storage.isGranted) {
          await Permission.storage.request();
        }
        if (!await Permission.manageExternalStorage.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      }

      // Mirror downloads go to the rule's localFolder, not the global path.
      // Non-mirror downloads use the global resolveDownloadPath (with smart
      // categorization applied).
      final String targetPath;
      if (item.mirrorChannelId != 0 && item.localPath.isNotEmpty) {
        // item.localPath was set to "<localFolder>/<fileName>" by MirrorController.
        // Use it directly — it already encodes the user's chosen folder.
        targetPath = item.localPath;
      } else {
        targetPath = settingsNotifier.resolveDownloadPath(item.fileName);
      }
      Log.info('Export target: $targetPath', tag: 'DL_MGR');

      final targetFile = IOFile(targetPath);

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
    if (!app_settings.SettingsState.isArchive(item.fileName)) return;
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

  Future<void> _handleTdlibResult(int fileId, TdObject? result) async {
    if (result is TdError) {
      Log.error('TDLib download error for fileId=$fileId: '
          '${result.code} ${result.message}');
      
      // Haptic feedback for error
      try {
        final haptic = _ref.read(hapticHelperProvider);
        haptic.error();
      } catch (_) {
        // Ignore haptic errors
      }

      // Notification for error
      try {
        final item = await _db.getByFileId(fileId);
        if (item != null) {
          final notificationService = _ref.read(notificationServiceProvider);
          await notificationService.notifyDownloadError(
            fileId: fileId,
            fileName: item.fileName,
            errorReason: result.message,
          );
        }
      } catch (e) {
        Log.error('Failed to send error notification: $e', tag: 'DL_MGR');
      }
      
      _db.updateStatus(fileId, DownloadStatus.error);
      _speed.removeFile(fileId);
      _notifyChange();
    } else if (result is File) {
      // Directly loop synchronous load completions back through the state map.
      await _handleFileUpdate(result);
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
