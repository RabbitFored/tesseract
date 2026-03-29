import 'download_status.dart';

/// Represents a single file in the download queue.
class DownloadItem {
  const DownloadItem({
    this.id,
    required this.fileId,
    required this.localPath,
    required this.totalSize,
    this.downloadedSize = 0,
    this.status = DownloadStatus.queued,
    this.priority = 0,
    this.fileName = '',
    this.chatId = 0,
    this.messageId = 0,
    this.createdAt,
    this.currentSpeed = 0,
    this.errorReason = '',
  });

  /// Auto-incremented row ID in SQLite (null before insertion).
  final int? id;

  /// TDLib file identifier.
  final int fileId;

  /// Destination path on local storage.
  final String localPath;

  /// Total file size in bytes.
  final int totalSize;

  /// Bytes downloaded so far.
  final int downloadedSize;

  /// Current queue status.
  final DownloadStatus status;

  /// Higher value = higher priority (processed first).
  final int priority;

  /// Human-readable file name for display.
  final String fileName;

  /// Originating chat ID (for reference).
  final int chatId;

  /// Originating message ID (for reference).
  final int messageId;

  /// Timestamp when the item was added to the queue.
  final DateTime? createdAt;

  /// Live download speed in bytes/second (not persisted in DB).
  final int currentSpeed;

  /// Specific error reason (persisted in DB). Empty string = no error detail.
  /// Values: '', 'corrupted_archive', 'password_required',
  ///         'unsupported_format', 'file_not_found', 'extraction_failed'.
  final String errorReason;

  /// Progress as a fraction 0.0 – 1.0.
  double get progress =>
      totalSize > 0 ? (downloadedSize / totalSize).clamp(0.0, 1.0) : 0.0;

  /// Whether the download is currently active.
  bool get isActive => status == DownloadStatus.downloading;

  /// Estimated time remaining in seconds, or null if not downloading.
  int? get etaSeconds {
    if (!isActive || currentSpeed <= 0) return null;
    final remaining = totalSize - downloadedSize;
    if (remaining <= 0) return 0;
    return (remaining / currentSpeed).ceil();
  }

  // ── Serialization ────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'file_id': fileId,
        'local_path': localPath,
        'total_size': totalSize,
        'downloaded_size': downloadedSize,
        'status': status.name,
        'priority': priority,
        'file_name': fileName,
        'chat_id': chatId,
        'message_id': messageId,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'error_reason': errorReason,
        // currentSpeed is transient — not stored in DB.
      };

  factory DownloadItem.fromMap(Map<String, dynamic> map) => DownloadItem(
        id: map['id'] as int?,
        fileId: map['file_id'] as int,
        localPath: map['local_path'] as String,
        totalSize: map['total_size'] as int,
        downloadedSize: map['downloaded_size'] as int? ?? 0,
        status: DownloadStatus.fromString(map['status'] as String),
        priority: map['priority'] as int? ?? 0,
        fileName: map['file_name'] as String? ?? '',
        chatId: map['chat_id'] as int? ?? 0,
        messageId: map['message_id'] as int? ?? 0,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
        errorReason: map['error_reason'] as String? ?? '',
      );

  DownloadItem copyWith({
    int? id,
    int? fileId,
    String? localPath,
    int? totalSize,
    int? downloadedSize,
    DownloadStatus? status,
    int? priority,
    String? fileName,
    int? chatId,
    int? messageId,
    DateTime? createdAt,
    int? currentSpeed,
    String? errorReason,
  }) =>
      DownloadItem(
        id: id ?? this.id,
        fileId: fileId ?? this.fileId,
        localPath: localPath ?? this.localPath,
        totalSize: totalSize ?? this.totalSize,
        downloadedSize: downloadedSize ?? this.downloadedSize,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        fileName: fileName ?? this.fileName,
        chatId: chatId ?? this.chatId,
        messageId: messageId ?? this.messageId,
        createdAt: createdAt ?? this.createdAt,
        currentSpeed: currentSpeed ?? this.currentSpeed,
        errorReason: errorReason ?? this.errorReason,
      );

  @override
  String toString() =>
      'DownloadItem(fileId: $fileId, status: ${status.name}, '
      '${downloadedSize}/${totalSize} bytes, speed: ${currentSpeed}B/s)';
}
