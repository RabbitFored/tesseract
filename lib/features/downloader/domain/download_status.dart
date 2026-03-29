/// Status of a download item in the queue.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  extracting,
  error;

  /// Convert to/from the string stored in SQLite.
  static DownloadStatus fromString(String value) =>
      DownloadStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => DownloadStatus.error,
      );
}
