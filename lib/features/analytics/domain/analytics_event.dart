import 'dart:convert';

/// Types of analytics events
enum EventType {
  downloadStarted,
  downloadCompleted,
  downloadFailed,
  downloadPaused,
  downloadResumed,
}

/// An analytics event representing a download action
class AnalyticsEvent {
  const AnalyticsEvent({
    this.id,
    required this.eventType,
    this.fileId,
    this.fileSize = 0,
    this.channelId,
    this.category,
    required this.timestamp,
    this.metadata,
  });

  final int? id;
  final EventType eventType;
  final int? fileId;
  final int fileSize;
  final int? channelId;
  final String? category;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'event_type': eventType.name,
        'file_id': fileId,
        'file_size': fileSize,
        'channel_id': channelId,
        'category': category,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
      };

  factory AnalyticsEvent.fromMap(Map<String, dynamic> map) => AnalyticsEvent(
        id: map['id'] as int?,
        eventType: EventType.values.firstWhere(
          (e) => e.name == map['event_type'],
          orElse: () => EventType.downloadStarted,
        ),
        fileId: map['file_id'] as int?,
        fileSize: map['file_size'] as int? ?? 0,
        channelId: map['channel_id'] as int?,
        category: map['category'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        metadata: map['metadata'] != null
            ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
            : null,
      );
}
