/// Represents a single downloadable media attachment extracted from a
/// Telegram message. Only messages with document/video/audio/photo
/// content produce these.
class MediaMessage {
  const MediaMessage({
    required this.messageId,
    required this.chatId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mediaType,
    this.mimeType = '',
    this.caption = '',
    this.date = 0,
    this.thumbnailFileId,
  });

  final int messageId;
  final int chatId;
  final int fileId;
  final String fileName;
  final int fileSize;
  final MediaType mediaType;
  final String mimeType;
  final String caption;
  final int date; // unix timestamp
  final int? thumbnailFileId;

  /// Human-readable media type label.
  String get typeLabel => switch (mediaType) {
        MediaType.document => 'Document',
        MediaType.video => 'Video',
        MediaType.audio => 'Audio',
        MediaType.photo => 'Photo',
        MediaType.voiceNote => 'Voice',
        MediaType.videoNote => 'Video Note',
        MediaType.animation => 'GIF',
      };
}

enum MediaType {
  document,
  video,
  audio,
  photo,
  voiceNote,
  videoNote,
  animation,
}
