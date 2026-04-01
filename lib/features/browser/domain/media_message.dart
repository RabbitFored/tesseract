import 'package:tdlib/td_api.dart';

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

  /// Extracts a [MediaMessage] from a TDLib [Message], or null if
  /// the message has no downloadable media.
  static MediaMessage? fromTdlibMessage(Message msg) {
    final chatId = msg.chatId;
    final content = msg.content;

    return switch (content) {
      MessageDocument(document: final doc, caption: final cap) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: doc.document.id,
          fileName: doc.fileName,
          fileSize: doc.document.expectedSize,
          mediaType: MediaType.document,
          mimeType: doc.mimeType,
          caption: cap.text,
          date: msg.date,
        ),
      MessageVideo(video: final vid, caption: final cap) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: vid.video.id,
          fileName: vid.fileName.isNotEmpty
              ? vid.fileName
              : 'video_${msg.id}.mp4',
          fileSize: vid.video.expectedSize,
          mediaType: MediaType.video,
          mimeType: vid.mimeType,
          caption: cap.text,
          date: msg.date,
          thumbnailFileId: vid.thumbnail?.file.id,
        ),
      MessageAudio(audio: final aud, caption: final cap) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: aud.audio.id,
          fileName: aud.fileName.isNotEmpty
              ? aud.fileName
              : '${aud.title.isNotEmpty ? aud.title : 'audio_${msg.id}'}.mp3',
          fileSize: aud.audio.expectedSize,
          mediaType: MediaType.audio,
          mimeType: aud.mimeType,
          caption: cap.text,
          date: msg.date,
          thumbnailFileId: aud.albumCoverThumbnail?.file.id,
        ),
      MessagePhoto(photo: final photo, caption: final cap) => () {
          final sizes = photo.sizes;
          if (sizes.isEmpty) return null;
          final largest = sizes.last;
          return MediaMessage(
            messageId: msg.id,
            chatId: chatId,
            fileId: largest.photo.id,
            fileName: 'photo_${msg.id}.jpg',
            fileSize: largest.photo.expectedSize,
            mediaType: MediaType.photo,
            caption: cap.text,
            date: msg.date,
          );
        }(),
      MessageAnimation(animation: final anim, caption: final cap) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: anim.animation.id,
          fileName: anim.fileName.isNotEmpty
              ? anim.fileName
              : 'animation_${msg.id}.mp4',
          fileSize: anim.animation.expectedSize,
          mediaType: MediaType.animation,
          mimeType: anim.mimeType,
          caption: cap.text,
          date: msg.date,
          thumbnailFileId: anim.thumbnail?.file.id,
        ),
      MessageVoiceNote(voiceNote: final vn, caption: final cap) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: vn.voice.id,
          fileName: 'voice_${msg.id}.ogg',
          fileSize: vn.voice.expectedSize,
          mediaType: MediaType.voiceNote,
          mimeType: vn.mimeType,
          caption: cap.text,
          date: msg.date,
        ),
      MessageVideoNote(videoNote: final vn) => MediaMessage(
          messageId: msg.id,
          chatId: chatId,
          fileId: vn.video.id,
          fileName: 'videonote_${msg.id}.mp4',
          fileSize: vn.video.expectedSize,
          mediaType: MediaType.videoNote,
          date: msg.date,
          thumbnailFileId: vn.thumbnail?.file.id,
        ),
      _ => null,
    };
  }
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
