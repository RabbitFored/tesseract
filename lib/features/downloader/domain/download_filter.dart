import 'download_item.dart';
import 'download_status.dart';

/// File type categories for filtering downloads.
enum FileType {
  video,
  audio,
  image,
  document,
  archive,
  app,
  other;

  /// Detect file type from file name extension.
  static FileType fromFileName(String fileName) {
    final ext = fileName.toLowerCase().split('.').lastOrNull ?? '';
    
    // Video extensions
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', 'm4v', 'mpg', 'mpeg']
        .contains(ext)) {
      return FileType.video;
    }
    
    // Audio extensions
    if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma', 'opus']
        .contains(ext)) {
      return FileType.audio;
    }
    
    // Image extensions
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff']
        .contains(ext)) {
      return FileType.image;
    }
    
    // Document extensions
    if (['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'xls', 'xlsx', 'ppt', 
         'pptx', 'csv', 'md']
        .contains(ext)) {
      return FileType.document;
    }
    
    // Archive extensions
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz']
        .contains(ext)) {
      return FileType.archive;
    }
    
    // App/executable extensions
    if (['apk', 'exe', 'msi', 'dmg', 'deb', 'rpm', 'appimage']
        .contains(ext)) {
      return FileType.app;
    }
    
    return FileType.other;
  }
}

/// Size range filter for downloads (in bytes).
class SizeRange {
  const SizeRange({
    required this.minBytes,
    required this.maxBytes,
  }) : assert(minBytes >= 0 && maxBytes >= minBytes,
            'Invalid size range: min must be >= 0 and max >= min');

  final int minBytes;
  final int maxBytes;

  /// Check if a file size falls within this range.
  bool contains(int bytes) => bytes >= minBytes && bytes <= maxBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SizeRange &&
          runtimeType == other.runtimeType &&
          minBytes == other.minBytes &&
          maxBytes == other.maxBytes;

  @override
  int get hashCode => Object.hash(minBytes, maxBytes);

  @override
  String toString() => 'SizeRange($minBytes - $maxBytes bytes)';
}

/// Date range filter for downloads.
class DateRange {
  const DateRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;

  /// Check if a date falls within this range.
  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange(${start.toIso8601String()} - ${end.toIso8601String()})';
}

/// Filter configuration for download queue queries.
class DownloadFilter {
  const DownloadFilter({
    this.statusFilter = const {},
    this.typeFilter = const {},
    this.sizeRange,
    this.dateRange,
    this.favoritesOnly = false,
  });

  /// Filter by download status (empty = no filter).
  final Set<DownloadStatus> statusFilter;

  /// Filter by file type (empty = no filter).
  final Set<FileType> typeFilter;

  /// Filter by file size range (null = no filter).
  final SizeRange? sizeRange;

  /// Filter by creation date range (null = no filter).
  final DateRange? dateRange;

  /// Show only favorite downloads.
  final bool favoritesOnly;

  /// Check if any filters are active.
  bool get hasActiveFilters =>
      statusFilter.isNotEmpty ||
      typeFilter.isNotEmpty ||
      sizeRange != null ||
      dateRange != null ||
      favoritesOnly;

  /// Count the number of active filter categories.
  int get activeFilterCount {
    int count = 0;
    if (statusFilter.isNotEmpty) count++;
    if (typeFilter.isNotEmpty) count++;
    if (sizeRange != null) count++;
    if (dateRange != null) count++;
    if (favoritesOnly) count++;
    return count;
  }

  /// Check if a download item matches all active filters.
  bool matches(DownloadItem item) {
    // Status filter
    if (statusFilter.isNotEmpty && !statusFilter.contains(item.status)) {
      return false;
    }

    // Type filter
    if (typeFilter.isNotEmpty) {
      final itemType = FileType.fromFileName(item.fileName);
      if (!typeFilter.contains(itemType)) {
        return false;
      }
    }

    // Size filter
    if (sizeRange != null && !sizeRange!.contains(item.totalSize)) {
      return false;
    }

    // Date filter
    if (dateRange != null) {
      final createdAt = item.createdAt;
      if (createdAt == null || !dateRange!.contains(createdAt)) {
        return false;
      }
    }

    // Favorites filter (Note: isFavorite field doesn't exist yet in DownloadItem)
    // This will be implemented when task 2.6 adds the isFavorite field
    // if (favoritesOnly && !item.isFavorite) {
    //   return false;
    // }

    return true;
  }

  /// Create a copy with modified filters.
  DownloadFilter copyWith({
    Set<DownloadStatus>? statusFilter,
    Set<FileType>? typeFilter,
    SizeRange? sizeRange,
    bool clearSizeRange = false,
    DateRange? dateRange,
    bool clearDateRange = false,
    bool? favoritesOnly,
  }) {
    return DownloadFilter(
      statusFilter: statusFilter ?? this.statusFilter,
      typeFilter: typeFilter ?? this.typeFilter,
      sizeRange: clearSizeRange ? null : (sizeRange ?? this.sizeRange),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }

  /// Create an empty filter (no filters active).
  static const DownloadFilter empty = DownloadFilter();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadFilter &&
          runtimeType == other.runtimeType &&
          _setEquals(statusFilter, other.statusFilter) &&
          _setEquals(typeFilter, other.typeFilter) &&
          sizeRange == other.sizeRange &&
          dateRange == other.dateRange &&
          favoritesOnly == other.favoritesOnly;

  @override
  int get hashCode => Object.hash(
        statusFilter,
        typeFilter,
        sizeRange,
        dateRange,
        favoritesOnly,
      );

  @override
  String toString() => 'DownloadFilter('
      'status: ${statusFilter.isEmpty ? 'all' : statusFilter.map((s) => s.name).join(', ')}, '
      'type: ${typeFilter.isEmpty ? 'all' : typeFilter.map((t) => t.name).join(', ')}, '
      'size: ${sizeRange ?? 'any'}, '
      'date: ${dateRange ?? 'any'}, '
      'favoritesOnly: $favoritesOnly)';

  /// Helper to compare sets for equality.
  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
