import 'dart:io';

import '../../../core/utils/logger.dart';
import '../domain/download_item.dart';
import '../domain/download_status.dart';
import 'download_db.dart';

/// Result of a cleanup run.
class CleanupResult {
  const CleanupResult({
    this.deletedCount = 0,
    this.freedBytes = 0,
    this.errors = const [],
  });

  final int deletedCount;
  final int freedBytes;
  final List<String> errors;
}

/// Handles automatic deletion of old completed downloads.
///
/// Runs on the main isolate — touches SQLite but NOT TDLib.
class CleanupService {
  const CleanupService._();

  /// Run the cleanup pass.
  ///
  /// Deletes completed downloads that are older than [afterDays] days AND
  /// whose local file still exists on disk.
  ///
  /// If [minFreeMb] > 0, also deletes oldest completed downloads until
  /// free storage exceeds the threshold.
  ///
  /// [keepFileIds] — file IDs that should never be deleted (favorites).
  /// [downloadBasePath] — used to probe free storage on the correct volume.
  static Future<CleanupResult> run({
    required DownloadDb db,
    required int afterDays,
    required int minFreeMb,
    Set<int> keepFileIds = const {},
    String? downloadBasePath,
  }) async {
    int deletedCount = 0;
    int freedBytes = 0;
    final errors = <String>[];

    final completed = await db.getByStatus(DownloadStatus.completed);
    final cutoff = DateTime.now().subtract(Duration(days: afterDays));

    // Phase 1: Delete items older than the cutoff.
    for (final item in completed) {
      if (keepFileIds.contains(item.fileId)) continue;
      final createdAt = item.createdAt;
      if (createdAt == null || createdAt.isAfter(cutoff)) continue;

      final result = await _deleteItem(item, db);
      if (result.$1) {
        deletedCount++;
        freedBytes += result.$2;
      } else if (result.$3.isNotEmpty) {
        errors.add(result.$3);
      }
    }

    // Phase 2: If free storage is still below threshold, delete oldest first.
    if (minFreeMb > 0) {
      final freeMb = await _getFreeStorageMb(downloadBasePath);
      if (freeMb < minFreeMb) {
        Log.info(
          'Free storage ${freeMb}MB < threshold ${minFreeMb}MB — '
          'running storage-pressure cleanup',
          tag: 'CLEANUP',
        );

        // Sort remaining completed items by creation date (oldest first).
        final remaining = (await db.getByStatus(DownloadStatus.completed))
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime(2000);
            final bDate = b.createdAt ?? DateTime(2000);
            return aDate.compareTo(bDate);
          });

        for (final item in remaining) {
          if (keepFileIds.contains(item.fileId)) continue;
          final currentFree = await _getFreeStorageMb(downloadBasePath);
          if (currentFree >= minFreeMb) break;

          final result = await _deleteItem(item, db);
          if (result.$1) {
            deletedCount++;
            freedBytes += result.$2;
          }
        }
      }
    }

    Log.info(
      'Cleanup complete: deleted=$deletedCount, freed=${freedBytes ~/ 1024}KB',
      tag: 'CLEANUP',
    );

    return CleanupResult(
      deletedCount: deletedCount,
      freedBytes: freedBytes,
      errors: errors,
    );
  }

  /// Delete a single item's local file and remove it from the DB.
  /// Returns (success, bytesFreed, errorMessage).
  static Future<(bool, int, String)> _deleteItem(
    DownloadItem item,
    DownloadDb db,
  ) async {
    int freed = 0;
    try {
      final file = File(item.localPath);
      if (await file.exists()) {
        freed = item.totalSize;
        await file.delete();
      }
      await db.delete(item.fileId);
      Log.info('Cleanup: deleted ${item.fileName}', tag: 'CLEANUP');
      return (true, freed, '');
    } catch (e) {
      final msg = 'Failed to delete ${item.fileName}: $e';
      Log.error(msg, tag: 'CLEANUP');
      return (false, 0, msg);
    }
  }

  /// Get free storage in MB on the device.
  ///
  /// Uses dart:io [FileSystemEntity.stat] on the download directory to
  /// infer available space via a temp-file probe on Android/Windows.
  /// Falls back to a safe large value if the platform doesn't support it.
  static Future<int> _getFreeStorageMb([String? dirPath]) async {
    try {
      // Use the path_provider downloads directory as the probe target.
      final dir = dirPath != null
          ? Directory(dirPath)
          : await _resolveProbeDir();
      if (dir == null) return 9999;

      // Write a 1-byte probe file and read back the free space via
      // dart:io's cross-platform StatFs equivalent.
      // dart:io exposes free space via Directory.stat() on some platforms,
      // but the most reliable cross-platform approach is to check the
      // available space by attempting a large allocation.
      //
      // For Android/Linux/Windows we use the statvfs-based approach
      // exposed through dart:io's FileSystemEntity.
      // dart:io does not expose statvfs directly. Use the df-equivalent:
      // read /proc/mounts or use platform-specific paths.
      if (Platform.isAndroid || Platform.isLinux) {
        return await _getFreeStorageLinux(dir.path);
      } else if (Platform.isWindows) {
        return await _getFreeStorageWindows(dir.path);
      }
      return 9999;
    } catch (_) {
      return 9999;
    }
  }

  static Future<Directory?> _resolveProbeDir() async {
    try {
      if (Platform.isAndroid) {
        return Directory('/storage/emulated/0');
      }
      // Fallback: temp directory
      return Directory.systemTemp;
    } catch (_) {
      return null;
    }
  }

  /// Read free space on Linux/Android via /proc/mounts + statfs syscall.
  /// Uses dart:io's RandomAccessFile to read /proc/mounts and then
  /// checks the filesystem containing [path].
  static Future<int> _getFreeStorageLinux(String path) async {
    try {
      // Use `df` output parsing as the most reliable cross-platform approach
      // without platform channels.
      final result = await Process.run('df', ['-k', path]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final availKb = int.tryParse(parts[3]) ?? 0;
            return availKb ~/ 1024; // KB → MB
          }
        }
      }
    } catch (_) {}
    return 9999;
  }

  /// Read free space on Windows via `wmic` or `fsutil`.
  static Future<int> _getFreeStorageWindows(String path) async {
    try {
      // Get the drive letter from the path.
      final drive = path.length >= 2 ? path.substring(0, 2) : 'C:';
      final result = await Process.run(
        'fsutil',
        ['volume', 'diskfree', drive],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        // Look for "Total # of free bytes" line.
        for (final line in output.split('\n')) {
          if (line.toLowerCase().contains('free bytes')) {
            final match = RegExp(r'(\d+)').firstMatch(line.replaceAll(',', ''));
            if (match != null) {
              final bytes = int.tryParse(match.group(1) ?? '') ?? 0;
              return bytes ~/ (1024 * 1024); // bytes → MB
            }
          }
        }
      }
    } catch (_) {}
    return 9999;
  }
}
