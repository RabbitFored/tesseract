/// Daily aggregated statistics
class DailyStats {
  const DailyStats({
    required this.date,
    this.totalDownloads = 0,
    this.totalBytes = 0,
    this.failedDownloads = 0,
    this.avgSpeedBps = 0,
    this.uniqueChannels = 0,
  });

  final String date; // YYYY-MM-DD format
  final int totalDownloads;
  final int totalBytes;
  final int failedDownloads;
  final int avgSpeedBps;
  final int uniqueChannels;

  int get successfulDownloads => totalDownloads - failedDownloads;

  double get successRate =>
      totalDownloads > 0 ? (successfulDownloads / totalDownloads * 100) : 0.0;

  Map<String, dynamic> toMap() => {
        'date': date,
        'total_downloads': totalDownloads,
        'total_bytes': totalBytes,
        'failed_downloads': failedDownloads,
        'avg_speed_bps': avgSpeedBps,
        'unique_channels': uniqueChannels,
      };

  factory DailyStats.fromMap(Map<String, dynamic> map) => DailyStats(
        date: map['date'] as String,
        totalDownloads: map['total_downloads'] as int? ?? 0,
        totalBytes: map['total_bytes'] as int? ?? 0,
        failedDownloads: map['failed_downloads'] as int? ?? 0,
        avgSpeedBps: map['avg_speed_bps'] as int? ?? 0,
        uniqueChannels: map['unique_channels'] as int? ?? 0,
      );

  DailyStats copyWith({
    String? date,
    int? totalDownloads,
    int? totalBytes,
    int? failedDownloads,
    int? avgSpeedBps,
    int? uniqueChannels,
  }) =>
      DailyStats(
        date: date ?? this.date,
        totalDownloads: totalDownloads ?? this.totalDownloads,
        totalBytes: totalBytes ?? this.totalBytes,
        failedDownloads: failedDownloads ?? this.failedDownloads,
        avgSpeedBps: avgSpeedBps ?? this.avgSpeedBps,
        uniqueChannels: uniqueChannels ?? this.uniqueChannels,
      );
}
