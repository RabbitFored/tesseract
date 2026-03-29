import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/download_item.dart';
import '../domain/download_status.dart';

/// SQLite database wrapper for the download queue.
///
/// Table schema (v2):
///   id              INTEGER PRIMARY KEY AUTOINCREMENT
///   file_id         INTEGER NOT NULL UNIQUE
///   local_path      TEXT    NOT NULL
///   total_size      INTEGER NOT NULL
///   downloaded_size INTEGER DEFAULT 0
///   status          TEXT    DEFAULT 'queued'
///   priority        INTEGER DEFAULT 0
///   file_name       TEXT    DEFAULT ''
///   chat_id         INTEGER DEFAULT 0
///   message_id      INTEGER DEFAULT 0
///   created_at      TEXT
///   error_reason    TEXT    DEFAULT ''  (Phase 10)
class DownloadDb {
  static const _dbName = 'download_queue.db';
  static const _dbVersion = 2;
  static const _table = 'downloads';

  Database? _db;

  /// Singleton-friendly access; safe to call multiple times.
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            file_id         INTEGER NOT NULL UNIQUE,
            local_path      TEXT    NOT NULL,
            total_size      INTEGER NOT NULL,
            downloaded_size INTEGER DEFAULT 0,
            status          TEXT    DEFAULT 'queued',
            priority        INTEGER DEFAULT 0,
            file_name       TEXT    DEFAULT '',
            chat_id         INTEGER DEFAULT 0,
            message_id      INTEGER DEFAULT 0,
            created_at      TEXT,
            error_reason    TEXT    DEFAULT ''
          )
        ''');
        // Index for quick lookups by status and priority.
        await db.execute(
          'CREATE INDEX idx_status_priority ON $_table (status, priority DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Phase 10: Add error_reason column for extraction error tracking.
          await db.execute(
            "ALTER TABLE $_table ADD COLUMN error_reason TEXT DEFAULT ''",
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

  /// Update progress (downloaded_size) and status for a given file_id.
  Future<int> updateProgress(
    int fileId, {
    required int downloadedSize,
    required DownloadStatus status,
  }) async {
    final db = await database;
    return db.update(
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
    await _db?.close();
    _db = null;
  }
}
