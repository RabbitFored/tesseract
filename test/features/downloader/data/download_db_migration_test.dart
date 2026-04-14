import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for desktop testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DownloadDb Migration Tests', () {
    late String dbPath;

    setUp(() async {
      // Create unique database path for each test
      final testDbPath = await databaseFactory.getDatabasesPath();
      dbPath = join(testDbPath, 'test_migration_${DateTime.now().millisecondsSinceEpoch}.db');
    });

    tearDown(() async {
      // Clean up test database
      try {
        await databaseFactory.deleteDatabase(dbPath);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('migration from v3 to v7 preserves existing data', () async {
      // Step 1: Create v3 database with test data
      final v3Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            // Create v3 schema
            await db.execute('''
              CREATE TABLE downloads (
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
              'CREATE INDEX idx_status_priority ON downloads (status, priority DESC)',
            );
          },
        ),
      );

      // Insert test data into v3 database
      final testData = [
        {
          'file_id': 1,
          'local_path': '/test/video1.mp4',
          'total_size': 1000000,
          'downloaded_size': 500000,
          'status': 'downloading',
          'priority': 5,
          'file_name': 'test_video.mp4',
          'chat_id': 123,
          'message_id': 456,
          'created_at': DateTime.now().toIso8601String(),
          'error_reason': '',
          'retry_count': 0,
          'checksum_md5': 'abc123',
          'speed_limit_bps': 0,
          'scheduled_at': '',
          'mirror_channel_id': 0,
        },
        {
          'file_id': 2,
          'local_path': '/test/document.pdf',
          'total_size': 500000,
          'downloaded_size': 500000,
          'status': 'completed',
          'priority': 0,
          'file_name': 'important_doc.pdf',
          'chat_id': 789,
          'message_id': 101,
          'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          'error_reason': '',
          'retry_count': 0,
          'checksum_md5': 'def456',
          'speed_limit_bps': 0,
          'scheduled_at': '',
          'mirror_channel_id': 0,
        },
        {
          'file_id': 3,
          'local_path': '/test/music.mp3',
          'total_size': 300000,
          'downloaded_size': 0,
          'status': 'queued',
          'priority': 10,
          'file_name': 'favorite_song.mp3',
          'chat_id': 111,
          'message_id': 222,
          'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
          'error_reason': '',
          'retry_count': 0,
          'checksum_md5': '',
          'speed_limit_bps': 0,
          'scheduled_at': '',
          'mirror_channel_id': 0,
        },
      ];

      for (final data in testData) {
        await v3Db.insert('downloads', data);
      }

      // Verify data was inserted
      final v3Data = await v3Db.query('downloads');
      expect(v3Data.length, 3, reason: 'Should have 3 rows in v3 database');

      await v3Db.close();

      // Step 2: Open database with v7 schema (triggers migration)
      final v7Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, version) async {
            // This shouldn't be called since database already exists
            fail('onCreate should not be called for existing database');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            // Simulate the migration logic from download_db.dart
            if (oldVersion < 4) {
              await db.execute(
                'ALTER TABLE downloads ADD COLUMN is_favorite INTEGER DEFAULT 0',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_favorite ON downloads (is_favorite)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_status ON downloads (status)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_created_at ON downloads (created_at)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
              );
            }
            if (oldVersion < 5) {
              await db.execute(
                "ALTER TABLE downloads ADD COLUMN tags TEXT DEFAULT ''",
              );
            }
            if (oldVersion < 6) {
              await db.execute(
                'ALTER TABLE downloads ADD COLUMN last_viewed_at INTEGER',
              );
            }
            if (oldVersion < 7) {
              // Check if index already exists before creating
              final existingIndexes = await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_downloads_file_name'",
              );
              if (existingIndexes.isEmpty) {
                await db.execute(
                  'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
                );
              }
            }
          },
        ),
      );

      // Step 3: Verify migration completed successfully
      final v7Data = await v7Db.query('downloads', orderBy: 'file_id ASC');
      expect(v7Data.length, 3, reason: 'All data should be preserved after migration');

      // Step 4: Verify all original data is intact
      expect(v7Data[0]['file_id'], 1);
      expect(v7Data[0]['file_name'], 'test_video.mp4');
      expect(v7Data[0]['total_size'], 1000000);
      expect(v7Data[0]['downloaded_size'], 500000);
      expect(v7Data[0]['status'], 'downloading');
      expect(v7Data[0]['priority'], 5);
      expect(v7Data[0]['checksum_md5'], 'abc123');

      expect(v7Data[1]['file_id'], 2);
      expect(v7Data[1]['file_name'], 'important_doc.pdf');
      expect(v7Data[1]['status'], 'completed');

      expect(v7Data[2]['file_id'], 3);
      expect(v7Data[2]['file_name'], 'favorite_song.mp3');
      expect(v7Data[2]['priority'], 10);

      // Step 5: Verify new columns exist with default values
      expect(v7Data[0]['is_favorite'], 0, reason: 'is_favorite should default to 0');
      expect(v7Data[0]['tags'], '', reason: 'tags should default to empty string');
      expect(v7Data[0]['last_viewed_at'], null, reason: 'last_viewed_at should default to null');

      expect(v7Data[1]['is_favorite'], 0);
      expect(v7Data[1]['tags'], '');
      expect(v7Data[1]['last_viewed_at'], null);

      expect(v7Data[2]['is_favorite'], 0);
      expect(v7Data[2]['tags'], '');
      expect(v7Data[2]['last_viewed_at'], null);

      // Step 6: Verify all indexes were created
      final indexes = await v7Db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='downloads'",
      );

      final indexNames = indexes.map((row) => row['name'] as String).toList();
      expect(indexNames, contains('idx_downloads_favorite'),
          reason: 'idx_downloads_favorite index should exist');
      expect(indexNames, contains('idx_downloads_status'),
          reason: 'idx_downloads_status index should exist');
      expect(indexNames, contains('idx_downloads_created_at'),
          reason: 'idx_downloads_created_at index should exist');
      expect(indexNames, contains('idx_downloads_file_name'),
          reason: 'idx_downloads_file_name index should exist');
      expect(indexNames, contains('idx_status_priority'),
          reason: 'Original idx_status_priority index should still exist');

      // Step 7: Verify new columns are writable
      await v7Db.update(
        'downloads',
        {'is_favorite': 1, 'tags': 'important,work'},
        where: 'file_id = ?',
        whereArgs: [2],
      );

      final updatedRow = await v7Db.query(
        'downloads',
        where: 'file_id = ?',
        whereArgs: [2],
      );

      expect(updatedRow.first['is_favorite'], 1,
          reason: 'Should be able to update is_favorite');
      expect(updatedRow.first['tags'], 'important,work',
          reason: 'Should be able to update tags');

      await v7Db.close();
    });

    test('migration from v4 to v7 works correctly', () async {
      // Create v4 database (already has is_favorite and indexes)
      final v4Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE downloads (
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
                mirror_channel_id INTEGER DEFAULT 0,
                is_favorite       INTEGER DEFAULT 0
              )
            ''');
            await db.execute(
              'CREATE INDEX idx_status_priority ON downloads (status, priority DESC)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_favorite ON downloads (is_favorite)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_status ON downloads (status)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_created_at ON downloads (created_at)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
            );
          },
        ),
      );

      // Insert test data with favorite
      await v4Db.insert('downloads', {
        'file_id': 1,
        'local_path': '/test/video.mp4',
        'total_size': 1000000,
        'downloaded_size': 0,
        'status': 'queued',
        'priority': 0,
        'file_name': 'test.mp4',
        'chat_id': 1,
        'message_id': 1,
        'created_at': DateTime.now().toIso8601String(),
        'is_favorite': 1,
      });

      await v4Db.close();

      // Migrate to v7
      final v7Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 5) {
              await db.execute(
                "ALTER TABLE downloads ADD COLUMN tags TEXT DEFAULT ''",
              );
            }
            if (oldVersion < 6) {
              await db.execute(
                'ALTER TABLE downloads ADD COLUMN last_viewed_at INTEGER',
              );
            }
            if (oldVersion < 7) {
              final existingIndexes = await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_downloads_file_name'",
              );
              if (existingIndexes.isEmpty) {
                await db.execute(
                  'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
                );
              }
            }
          },
        ),
      );

      // Verify data preserved
      final data = await v7Db.query('downloads');
      expect(data.length, 1);
      expect(data.first['is_favorite'], 1, reason: 'Favorite status should be preserved');
      expect(data.first['tags'], '', reason: 'tags should be added with default value');
      expect(data.first['last_viewed_at'], null, reason: 'last_viewed_at should be added');

      await v7Db.close();
    });

    test('new columns work correctly after migration', () async {
      // Create v3 database
      final v3Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE downloads (
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
          },
        ),
      );

      await v3Db.insert('downloads', {
        'file_id': 1,
        'local_path': '/test/file.mp4',
        'total_size': 1000000,
        'file_name': 'test.mp4',
        'chat_id': 1,
        'message_id': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      await v3Db.close();

      // Migrate to v7
      final v7Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 4) {
              await db.execute(
                'ALTER TABLE downloads ADD COLUMN is_favorite INTEGER DEFAULT 0',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_favorite ON downloads (is_favorite)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_status ON downloads (status)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_created_at ON downloads (created_at)',
              );
              await db.execute(
                'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
              );
            }
            if (oldVersion < 5) {
              await db.execute(
                "ALTER TABLE downloads ADD COLUMN tags TEXT DEFAULT ''",
              );
            }
            if (oldVersion < 6) {
              await db.execute(
                'ALTER TABLE downloads ADD COLUMN last_viewed_at INTEGER',
              );
            }
            if (oldVersion < 7) {
              final existingIndexes = await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_downloads_file_name'",
              );
              if (existingIndexes.isEmpty) {
                await db.execute(
                  'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
                );
              }
            }
          },
        ),
      );

      // Test is_favorite functionality
      await v7Db.update(
        'downloads',
        {'is_favorite': 1},
        where: 'file_id = ?',
        whereArgs: [1],
      );

      var result = await v7Db.query('downloads', where: 'file_id = ?', whereArgs: [1]);
      expect(result.first['is_favorite'], 1);

      // Test tags functionality
      await v7Db.update(
        'downloads',
        {'tags': 'work,important,urgent'},
        where: 'file_id = ?',
        whereArgs: [1],
      );

      result = await v7Db.query('downloads', where: 'file_id = ?', whereArgs: [1]);
      expect(result.first['tags'], 'work,important,urgent');

      // Test last_viewed_at functionality
      final now = DateTime.now().millisecondsSinceEpoch;
      await v7Db.update(
        'downloads',
        {'last_viewed_at': now},
        where: 'file_id = ?',
        whereArgs: [1],
      );

      result = await v7Db.query('downloads', where: 'file_id = ?', whereArgs: [1]);
      expect(result.first['last_viewed_at'], now);

      // Test querying by is_favorite
      await v7Db.insert('downloads', {
        'file_id': 2,
        'local_path': '/test/file2.mp4',
        'total_size': 2000000,
        'file_name': 'test2.mp4',
        'chat_id': 2,
        'message_id': 2,
        'created_at': DateTime.now().toIso8601String(),
        'is_favorite': 0,
      });

      final favorites = await v7Db.query(
        'downloads',
        where: 'is_favorite = ?',
        whereArgs: [1],
      );

      expect(favorites.length, 1);
      expect(favorites.first['file_id'], 1);

      await v7Db.close();
    });

    test('indexes improve query performance', () async {
      // Create v7 database with indexes
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE downloads (
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
                mirror_channel_id INTEGER DEFAULT 0,
                is_favorite       INTEGER DEFAULT 0,
                tags              TEXT    DEFAULT '',
                last_viewed_at    INTEGER
              )
            ''');
            await db.execute(
              'CREATE INDEX idx_status_priority ON downloads (status, priority DESC)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_favorite ON downloads (is_favorite)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_status ON downloads (status)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_created_at ON downloads (created_at)',
            );
            await db.execute(
              'CREATE INDEX idx_downloads_file_name ON downloads (file_name)',
            );
          },
        ),
      );

      // Insert test data
      for (int i = 1; i <= 100; i++) {
        await db.insert('downloads', {
          'file_id': i,
          'local_path': '/test/file$i.mp4',
          'total_size': i * 1000000,
          'file_name': 'file$i.mp4',
          'status': i % 3 == 0 ? 'completed' : 'queued',
          'is_favorite': i % 10 == 0 ? 1 : 0,
          'chat_id': i,
          'message_id': i,
          'created_at': DateTime.now().subtract(Duration(days: i)).toIso8601String(),
        });
      }

      // Verify index usage with EXPLAIN QUERY PLAN
      final favoritesPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM downloads WHERE is_favorite = 1',
      );
      final planDetail = favoritesPlan.first['detail'] as String;
      expect(planDetail.toLowerCase(), contains('idx_downloads_favorite'),
          reason: 'Query should use idx_downloads_favorite index');

      // Verify query returns correct results
      final favorites = await db.query(
        'downloads',
        where: 'is_favorite = ?',
        whereArgs: [1],
      );
      expect(favorites.length, 10, reason: 'Should find 10 favorites');

      // Test file_name search
      // Note: LIKE with leading wildcard may not use index, but index still helps with sorting
      final searchResults = await db.query(
        'downloads',
        where: 'LOWER(file_name) LIKE LOWER(?)',
        whereArgs: ['%file5%'],
      );
      expect(searchResults.length, greaterThan(0), reason: 'Should find files matching search');

      await db.close();
    });
  });
}
