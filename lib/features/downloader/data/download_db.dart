import 'dart:async';
import 'dart:io' show Platform;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/download_item.dart';
import '../domain/download_status.dart';

// ── Pending progress write ────────────────────────────────────────────────────

/// Buffered progress update waiting to be flushed to SQLite.
class _PendingProgress {
  _PendingProgress({
    required this.downloadedSize,
    required this.status,
  });
  int downloadedSize;
  DownloadStatus status;
}

/// SQLite database wrapper for the download queue.
///
/// Table schema (v3):
///   id                INTEGER PRIMARY KEY AUTOINCREMENT
///   file_id           INTEGER NOT NULL UNIQUE
///   local_path        TEXT    NOT NULL
///   total_size        INTEGER NOT NULL
///   downloaded_size   INTEGER DEFAULT 0
///   status            TEXT    DEFAULT 'queued'
///   priority          INTEGER DEFAULT 0
///   file_name         TEXT    DEFAULT ''
///   chat_id           INTEGER DEFAULT 0
///   message_id        INTEGER DEFAULT 0
///   created_at        TEXT
///   error_reason      TEXT    DEFAULT ''
///   retry_count       INTEGER DEFAULT 0
///   checksum_md5      TEXT    DEFAULT ''
///   speed_limit_bps   INTEGER DEFAULT 0
///   scheduled_at      TEXT    DEFAULT ''
///   mirror_channel_id INTEGER DEFAULT 0
class DownloadDb {
  static const _dbName = 'download_queue.db';
  static const _dbVersion = 3;
  static const _table = 'downloads';

  /// How often buffered progress writes are flushed to SQLite.
  static const _flushInterval = Duration(milliseconds: 500);

  Database? _db;

  // ── Write-coalescing buffer ───────────────────────────────────
  // Accumulates in-flight progress updates so we write to SQLite at most
  // once per [_flushInterval] per file instead of on every UpdateFile event.
  // Status transitions (completed/error/paused) bypass the buffer and write
  // immediately so the UI reflects them without delay.
  final Map<int, _PendingProgress> _pendingProgress = {};
  Timer? _flushTimer;

  /// Start the periodic flush timer. Called once after [database] is ready.
  void _startFlushTimer() {
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => _flushPending());
  }

  /// Write all buffered progress rows to SQLite in a single transaction.
  Future<void> _flushPending() async {
    if (_pendingProgress.isEmpty) return;
    final snapshot = Map<int, _PendingProgress>.from(_pendingProgress);
    _pendingProgress.clear();

    final db = await database;
    await db.transaction((txn) async {
      for (final entry in snapshot.entries) {
        final fileId = entry.key;
        final p = entry.value;
        final fields = <String, dynamic>{
          'downloaded_size': p.downloadedSize,
          'status': p.status.name,
        };
        await txn.update(
          _table,
          fields,
          where: 'file_id = ?',
          whereArgs: [fileId],
        );
      }
    });
  }

  /// Singleton-friendly access; safe to call multiple times.
  Future<Database> get database async {
    if (_db == null) {
      _db = await _open();
      _startFlushTimer();
    }
    return _db!;
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      // WAL mode: readers never block writers and writers never block readers.
      // This eliminates the "database locked" warning during concurrent
      // progress reads (downloadQueueProvider) and writes (_flushPending).
      onOpen: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
        await db.execute('PRAGMA cache_size=-4096'); // 4 MB page cache
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id           INTEGER NOT NULL UNIQUE,
            local_path        TEXT    NOT NULL,
            total_size        INTEGER NOT NULL,
            downloaded_size   INTEGER DEFAULT 0,
            status            TEXT    DEFAULT 'queued',
            priority          INTEGER DEFAULT 0,
            file_name         TEXT    DEFAULT '',
            chat_id           INTEGER DEFAULT 0,
            message_id        INTEGER DEFAULT 0,
            created_at        TEXT,
            error_reason      TEXT    DEFAULT '',
            retry_count       INTEGER DEFAULT 0,
            checksum_md5      TEXT    DEFAULT '',
            speed_limit_bps   INTEGER DEFAULT 0,
            scheduled_at      TEXT    DEFAULT '',
            mirror_channel_id INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_status_priority ON $_table (status, priority DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN error_reason TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          // v3: retry tracking, checksum, per-file speed limit, scheduling, mirror.
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN retry_count INTEGER DEFAULT 0',
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN checksum_md5 TEXT DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN speed_limit_bps INTEGER DEFAULT 0',
          );
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN scheduled_at TEXT DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN mirror_channel_id INTEGER DEFAULT 0',
          );
        }
      },
    );
  }

  // ── CRUD ─────────────────────────────────────────────────────

  /// Insert a new download item. Returns the row id.
  Future<int> insert(DownloadItem item) async {
    final db = await database;
    return db.insert(
      _table,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Buffer a progress update (downloaded_size + status).
  /// Writes are coalesced and flushed every [_flushInterval].
  /// Call [updateProgressImmediate] for status transitions that must be
  /// visible in the UI without delay (completed, error, paused).
  Future<void> updateProgress(
    int fileId, {
    required int downloadedSize,
    required DownloadStatus status,
  }) async {
    // Status transitions bypass the buffer — write immediately.
    if (status != DownloadStatus.downloading) {
      await _flushPending(); // flush any buffered progress first
      return updateProgressImmediate(fileId,
          downloadedSize: downloadedSize, status: status);
    }
    // Coalesce: overwrite any existing pending entry for this file.
    _pendingProgress[fileId] = _PendingProgress(
      downloadedSize: downloadedSize,
      status: status,
    );
  }

  /// Buffer a progress + path update (used on download completion).
  /// Always writes immediately since it accompanies a status transition.
  Future<void> updateProgressAndPath(
    int fileId, {
    required int downloadedSize,
    required DownloadStatus status,
    required String localPath,
  }) async {
    await _flushPending(); // flush any buffered progress first
    final db = await database;
    await db.update(
      _table,
      {
        'downloaded_size': downloadedSize,
        'status': status.name,
        'local_path': localPath,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Write a progress update immediately, bypassing the coalesce buffer.
  /// Used for status transitions (completed, error, paused).
  Future<void> updateProgressImmediate(
    int fileId, {
    required int downloadedSize,
    required DownloadStatus status,
  }) async {
    final db = await database;
    await db.update(
      _table,
      {
        'downloaded_size': downloadedSize,
        'status': status.name,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Update only the status of a download item.
  Future<int> updateStatus(int fileId, DownloadStatus status) async {
    final db = await database;
    return db.update(
      _table,
      {'status': status.name},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Update status and error reason atomically.
  /// Used by the extraction pipeline to set specific error badges.
  Future<int> updateStatusWithReason(
    int fileId,
    DownloadStatus status,
    String errorReason,
  ) async {
    final db = await database;
    return db.update(
      _table,
      {
        'status': status.name,
        'error_reason': errorReason,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Update the priority of a download item.
  Future<int> updatePriority(int fileId, int priority) async {
    final db = await database;
    return db.update(
      _table,
      {'priority': priority},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Fetch a single item by file_id, or null if not found.
  Future<DownloadItem?> getByFileId(int fileId) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'file_id = ?',
      whereArgs: [fileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DownloadItem.fromMap(rows.first);
  }

  /// Return all items ordered by priority (desc) then creation time.
  Future<List<DownloadItem>> getAll() async {
    final db = await database;
    final rows = await db.query(
      _table,
      orderBy: 'priority DESC, created_at ASC',
    );
    return rows.map(DownloadItem.fromMap).toList();
  }

  /// Return items matching a specific status.
  Future<List<DownloadItem>> getByStatus(DownloadStatus status) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'priority DESC, created_at ASC',
    );
    return rows.map(DownloadItem.fromMap).toList();
  }

  /// Count of items currently downloading.
  Future<int> activeCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_table WHERE status = ?',
      [DownloadStatus.downloading.name],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get next queued items respecting priority, up to [limit].
  Future<List<DownloadItem>> nextQueued({int limit = 3}) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'status = ?',
      whereArgs: [DownloadStatus.queued.name],
      orderBy: 'priority DESC, created_at ASC',
      limit: limit,
    );
    return rows.map(DownloadItem.fromMap).toList();
  }

  /// Delete a download item by file_id.
  Future<int> delete(int fileId) async {
    final db = await database;
    return db.delete(_table, where: 'file_id = ?', whereArgs: [fileId]);
  }

  /// Bug 3 fix: Reset a failed download for retry — clears progress and error.
  Future<int> resetForRetry(int fileId) async {
    final db = await database;
    return db.update(
      _table,
      {
        'downloaded_size': 0,
        'status': DownloadStatus.queued.name,
        'error_reason': '',
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Increment the retry counter for a file.
  Future<void> incrementRetryCount(int fileId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $_table SET retry_count = retry_count + 1 WHERE file_id = ?',
      [fileId],
    );
  }

  /// Reset retry counter (used when user manually retries).
  Future<void> resetRetryCount(int fileId) async {
    final db = await database;
    await db.update(
      _table,
      {'retry_count': 0},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  /// Return all items that are scheduled and whose scheduled_at has passed.
  Future<List<DownloadItem>> getDueScheduledItems() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      _table,
      where: "status = 'queued' AND scheduled_at != '' AND scheduled_at <= ?",
      whereArgs: [now],
    );
    return rows.map(DownloadItem.fromMap).toList();
  }

  /// Hot-swaps the underlying `file_id` mapping when TDLib invalidates the cache geometry 
  /// (used for corrupted chunk recovery).
  Future<int> migrateFileId({required int oldFileId, required int newFileId}) async {
    final db = await database;
    // Don't error out if they are the same
    if (oldFileId == newFileId) return 0;
    
    return db.update(
      _table,
      {'file_id': newFileId},
      where: 'file_id = ?',
      whereArgs: [oldFileId],
    );
  }

  /// Reset all "downloading" items back to "queued" (crash recovery).
  Future<int> resetStaleDownloads() async {
    final db = await database;
    return db.update(
      _table,
      {'status': DownloadStatus.queued.name},
      where: 'status = ?',
      whereArgs: [DownloadStatus.downloading.name],
    );
  }

  /// Close the database connection.
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    // Flush any remaining buffered progress before closing.
    await _flushPending();
    await _db?.close();
    _db = null;
  }
}
