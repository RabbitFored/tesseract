import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/logger.dart';
import '../domain/analytics_event.dart';
import '../domain/daily_stats.dart';

/// Analytics database for tracking download events and statistics.
class AnalyticsDb {
  static const String _dbName = 'analytics.db';
  static const int _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Analytics events table
    await db.execute('''
      CREATE TABLE analytics_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        file_id INTEGER,
        file_size INTEGER,
        channel_id INTEGER,
        category TEXT,
        timestamp INTEGER NOT NULL,
        metadata TEXT
      )
    ''');

    // Daily stats table
    await db.execute('''
      CREATE TABLE daily_stats (
        date TEXT PRIMARY KEY,
        total_downloads INTEGER DEFAULT 0,
        total_bytes INTEGER DEFAULT 0,
        failed_downloads INTEGER DEFAULT 0,
        avg_speed_bps INTEGER DEFAULT 0,
        unique_channels INTEGER DEFAULT 0
      )
    ''');

    // Indexes for performance
    await db.execute(
        'CREATE INDEX idx_events_timestamp ON analytics_events(timestamp)');
    await db.execute(
        'CREATE INDEX idx_events_type ON analytics_events(event_type)');
    await db.execute(
        'CREATE INDEX idx_events_channel ON analytics_events(channel_id)');

    Log.info('Analytics database created', tag: 'ANALYTICS_DB');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future schema upgrades
  }

  // ── Event Tracking ────────────────────────────────────────────

  /// Record a download event
  Future<void> recordEvent(AnalyticsEvent event) async {
    try {
      final db = await database;
      await db.insert('analytics_events', event.toMap());

      // Update daily stats
      await _updateDailyStats(event);
    } catch (e) {
      Log.error('Failed to record analytics event: $e', tag: 'ANALYTICS_DB');
    }
  }

  /// Update daily statistics
  Future<void> _updateDailyStats(AnalyticsEvent event) async {
    final db = await database;
    final date = _formatDate(event.timestamp);

    final existing = await db.query(
      'daily_stats',
      where: 'date = ?',
      whereArgs: [date],
    );

    if (existing.isEmpty) {
      // Create new daily stats
      await db.insert('daily_stats', {
        'date': date,
        'total_downloads': event.eventType == EventType.downloadStarted ? 1 : 0,
        'total_bytes':
            event.eventType == EventType.downloadCompleted ? event.fileSize : 0,
        'failed_downloads':
            event.eventType == EventType.downloadFailed ? 1 : 0,
        'avg_speed_bps': 0,
        'unique_channels': event.channelId != null ? 1 : 0,
      });
    } else {
      // Update existing stats
      final stats = DailyStats.fromMap(existing.first);
      final updated = stats.copyWith(
        totalDownloads: stats.totalDownloads +
            (event.eventType == EventType.downloadStarted ? 1 : 0),
        totalBytes: stats.totalBytes +
            (event.eventType == EventType.downloadCompleted ? event.fileSize : 0),
        failedDownloads: stats.failedDownloads +
            (event.eventType == EventType.downloadFailed ? 1 : 0),
      );

      await db.update(
        'daily_stats',
        updated.toMap(),
        where: 'date = ?',
        whereArgs: [date],
      );
    }
  }

  // ── Query Methods ─────────────────────────────────────────────

  /// Get events within a date range
  Future<List<AnalyticsEvent>> getEvents({
    DateTime? startDate,
    DateTime? endDate,
    EventType? eventType,
    int? channelId,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (startDate != null) {
      where.add('timestamp >= ?');
      whereArgs.add(startDate.millisecondsSinceEpoch);
    }

    if (endDate != null) {
      where.add('timestamp <= ?');
      whereArgs.add(endDate.millisecondsSinceEpoch);
    }

    if (eventType != null) {
      where.add('event_type = ?');
      whereArgs.add(eventType.name);
    }

    if (channelId != null) {
      where.add('channel_id = ?');
      whereArgs.add(channelId);
    }

    final results = await db.query(
      'analytics_events',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
    );

    return results.map((map) => AnalyticsEvent.fromMap(map)).toList();
  }

  /// Get daily stats within a date range
  Future<List<DailyStats>> getDailyStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (startDate != null) {
      where.add('date >= ?');
      whereArgs.add(_formatDate(startDate));
    }

    if (endDate != null) {
      where.add('date <= ?');
      whereArgs.add(_formatDate(endDate));
    }

    final results = await db.query(
      'daily_stats',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'date DESC',
    );

    return results.map((map) => DailyStats.fromMap(map)).toList();
  }

  /// Get total statistics
  Future<Map<String, dynamic>> getTotalStats() async {
    final db = await database;

    final totalDownloads = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM analytics_events WHERE event_type = 'downloadStarted'",
      ),
    );

    final completedDownloads = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM analytics_events WHERE event_type = 'downloadCompleted'",
      ),
    );

    final failedDownloads = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM analytics_events WHERE event_type = 'downloadFailed'",
      ),
    );

    final totalBytes = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT SUM(file_size) FROM analytics_events WHERE event_type = 'downloadCompleted'",
      ),
    );

    final uniqueChannels = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(DISTINCT channel_id) FROM analytics_events WHERE channel_id IS NOT NULL',
      ),
    );

    return {
      'totalDownloads': totalDownloads ?? 0,
      'completedDownloads': completedDownloads ?? 0,
      'failedDownloads': failedDownloads ?? 0,
      'totalBytes': totalBytes ?? 0,
      'uniqueChannels': uniqueChannels ?? 0,
      'successRate': totalDownloads! > 0
          ? (completedDownloads! / totalDownloads * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// Get top channels by download count
  Future<List<Map<String, dynamic>>> getTopChannels({int limit = 10}) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT 
        channel_id,
        COUNT(*) as download_count,
        SUM(file_size) as total_bytes
      FROM analytics_events
      WHERE channel_id IS NOT NULL AND event_type = 'downloadCompleted'
      GROUP BY channel_id
      ORDER BY download_count DESC
      LIMIT ?
    ''', [limit]);

    return results;
  }

  /// Get downloads by category
  Future<List<Map<String, dynamic>>> getDownloadsByCategory() async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT 
        category,
        COUNT(*) as count,
        SUM(file_size) as total_bytes
      FROM analytics_events
      WHERE category IS NOT NULL AND event_type = 'downloadCompleted'
      GROUP BY category
      ORDER BY count DESC
    ''');

    return results;
  }

  /// Get download timeline (last 30 days)
  Future<List<DailyStats>> getDownloadTimeline({
    int days = 30,
  }) async {
    final db = await database;
    final startDate = DateTime.now().subtract(Duration(days: days));

    final results = await db.query(
      'daily_stats',
      where: 'date >= ?',
      whereArgs: [_formatDate(startDate)],
      orderBy: 'date ASC',
    );

    return results.map((row) => DailyStats.fromMap(row)).toList();
  }

  // ── Cleanup ───────────────────────────────────────────────────

  /// Delete old events (keep last N days)
  Future<void> cleanupOldEvents({int keepDays = 90}) async {
    final db = await database;
    final cutoffDate =
        DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;

    await db.delete(
      'analytics_events',
      where: 'timestamp < ?',
      whereArgs: [cutoffDate],
    );

    await db.delete(
      'daily_stats',
      where: 'date < ?',
      whereArgs: [_formatDate(DateTime.now().subtract(Duration(days: keepDays)))],
    );

    Log.info('Cleaned up analytics older than $keepDays days',
        tag: 'ANALYTICS_DB');
  }

  /// Close database
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
