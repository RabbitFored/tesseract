import 'package:flutter_test/flutter_test.dart';
import 'package:tesseract/features/downloader/domain/download_filter.dart';
import 'package:tesseract/features/downloader/domain/download_item.dart';
import 'package:tesseract/features/downloader/domain/download_status.dart';

void main() {
  group('FileType', () {
    test('fromFileName detects video files', () {
      expect(FileType.fromFileName('video.mp4'), FileType.video);
      expect(FileType.fromFileName('movie.mkv'), FileType.video);
      expect(FileType.fromFileName('clip.avi'), FileType.video);
    });

    test('fromFileName detects audio files', () {
      expect(FileType.fromFileName('song.mp3'), FileType.audio);
      expect(FileType.fromFileName('track.flac'), FileType.audio);
    });

    test('fromFileName detects image files', () {
      expect(FileType.fromFileName('photo.jpg'), FileType.image);
      expect(FileType.fromFileName('picture.png'), FileType.image);
    });

    test('fromFileName detects document files', () {
      expect(FileType.fromFileName('report.pdf'), FileType.document);
      expect(FileType.fromFileName('notes.txt'), FileType.document);
    });

    test('fromFileName detects archive files', () {
      expect(FileType.fromFileName('archive.zip'), FileType.archive);
      expect(FileType.fromFileName('backup.tar.gz'), FileType.archive);
    });

    test('fromFileName detects app files', () {
      expect(FileType.fromFileName('app.apk'), FileType.app);
      expect(FileType.fromFileName('installer.exe'), FileType.app);
    });

    test('fromFileName returns other for unknown types', () {
      expect(FileType.fromFileName('unknown.xyz'), FileType.other);
      expect(FileType.fromFileName('noextension'), FileType.other);
    });
  });

  group('SizeRange', () {
    test('contains returns true for values in range', () {
      const range = SizeRange(minBytes: 100, maxBytes: 1000);
      expect(range.contains(100), true);
      expect(range.contains(500), true);
      expect(range.contains(1000), true);
    });

    test('contains returns false for values outside range', () {
      const range = SizeRange(minBytes: 100, maxBytes: 1000);
      expect(range.contains(99), false);
      expect(range.contains(1001), false);
    });

    test('equality works correctly', () {
      const range1 = SizeRange(minBytes: 100, maxBytes: 1000);
      const range2 = SizeRange(minBytes: 100, maxBytes: 1000);
      const range3 = SizeRange(minBytes: 200, maxBytes: 1000);
      
      expect(range1, range2);
      expect(range1 == range3, false);
    });
  });

  group('DateRange', () {
    test('contains returns true for dates in range', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 12, 31);
      final range = DateRange(start: start, end: end);
      
      expect(range.contains(DateTime(2024, 6, 15)), true);
      expect(range.contains(start), true);
      expect(range.contains(end), true);
    });

    test('contains returns false for dates outside range', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 12, 31);
      final range = DateRange(start: start, end: end);
      
      expect(range.contains(DateTime(2023, 12, 31)), false);
      expect(range.contains(DateTime(2025, 1, 1)), false);
    });
  });

  group('DownloadFilter', () {
    final testItem = DownloadItem(
      fileId: 1,
      localPath: '/path/video.mp4',
      totalSize: 5000000,
      fileName: 'video.mp4',
      status: DownloadStatus.downloading,
      createdAt: DateTime(2024, 6, 15),
    );

    test('empty filter has no active filters', () {
      const filter = DownloadFilter.empty;
      expect(filter.hasActiveFilters, false);
      expect(filter.activeFilterCount, 0);
    });

    test('hasActiveFilters returns true when filters are set', () {
      const filter = DownloadFilter(
        statusFilter: {DownloadStatus.downloading},
      );
      expect(filter.hasActiveFilters, true);
      expect(filter.activeFilterCount, 1);
    });

    test('activeFilterCount counts all active filters', () {
      const filter = DownloadFilter(
        statusFilter: {DownloadStatus.downloading},
        typeFilter: {FileType.video},
        sizeRange: SizeRange(minBytes: 0, maxBytes: 10000000),
        favoritesOnly: true,
      );
      expect(filter.activeFilterCount, 4);
    });

    test('matches returns true when item matches status filter', () {
      const filter = DownloadFilter(
        statusFilter: {DownloadStatus.downloading, DownloadStatus.queued},
      );
      expect(filter.matches(testItem), true);
    });

    test('matches returns false when item does not match status filter', () {
      const filter = DownloadFilter(
        statusFilter: {DownloadStatus.completed},
      );
      expect(filter.matches(testItem), false);
    });

    test('matches returns true when item matches type filter', () {
      const filter = DownloadFilter(
        typeFilter: {FileType.video},
      );
      expect(filter.matches(testItem), true);
    });

    test('matches returns false when item does not match type filter', () {
      const filter = DownloadFilter(
        typeFilter: {FileType.audio},
      );
      expect(filter.matches(testItem), false);
    });

    test('matches returns true when item matches size filter', () {
      const filter = DownloadFilter(
        sizeRange: SizeRange(minBytes: 1000000, maxBytes: 10000000),
      );
      expect(filter.matches(testItem), true);
    });

    test('matches returns false when item does not match size filter', () {
      const filter = DownloadFilter(
        sizeRange: SizeRange(minBytes: 10000000, maxBytes: 20000000),
      );
      expect(filter.matches(testItem), false);
    });

    test('matches returns true when item matches date filter', () {
      final filter = DownloadFilter(
        dateRange: DateRange(
          start: DateTime(2024, 1, 1),
          end: DateTime(2024, 12, 31),
        ),
      );
      expect(filter.matches(testItem), true);
    });

    test('matches returns false when item does not match date filter', () {
      final filter = DownloadFilter(
        dateRange: DateRange(
          start: DateTime(2025, 1, 1),
          end: DateTime(2025, 12, 31),
        ),
      );
      expect(filter.matches(testItem), false);
    });

    test('matches returns true when all filters match', () {
      final filter = DownloadFilter(
        statusFilter: const {DownloadStatus.downloading},
        typeFilter: const {FileType.video},
        sizeRange: const SizeRange(minBytes: 1000000, maxBytes: 10000000),
        dateRange: DateRange(
          start: DateTime(2024, 1, 1),
          end: DateTime(2024, 12, 31),
        ),
      );
      expect(filter.matches(testItem), true);
    });

    test('matches returns false when any filter does not match', () {
      const filter = DownloadFilter(
        statusFilter: {DownloadStatus.downloading},
        typeFilter: {FileType.audio}, // This won't match
        sizeRange: SizeRange(minBytes: 1000000, maxBytes: 10000000),
      );
      expect(filter.matches(testItem), false);
    });

    test('copyWith creates new filter with updated values', () {
      const original = DownloadFilter(
        statusFilter: {DownloadStatus.downloading},
      );
      final updated = original.copyWith(
        typeFilter: {FileType.video},
      );
      
      expect(updated.statusFilter, {DownloadStatus.downloading});
      expect(updated.typeFilter, {FileType.video});
    });

    test('copyWith can clear optional filters', () {
      const original = DownloadFilter(
        sizeRange: SizeRange(minBytes: 0, maxBytes: 1000),
      );
      final updated = original.copyWith(clearSizeRange: true);
      
      expect(updated.sizeRange, null);
    });
  });
}
