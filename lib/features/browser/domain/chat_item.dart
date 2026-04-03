/// Lightweight model representing a Telegram chat for the browser list.
class ChatItem {
  const ChatItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.photoPath = '',
    this.unreadCount = 0,
    this.lastMessageDate = 0,
    this.memberCount = 0,
    this.isChannel = false,
    this.isGroup = false,
    this.isForum = false,
    this.hasMedia = true,
  });

  final int id;
  final String title;
  final String subtitle;
  final String photoPath;
  final int unreadCount;
  final int lastMessageDate;
  final int memberCount;
  final bool isChannel;
  final bool isGroup;
  final bool isForum;
  final bool hasMedia;

  /// Initials for avatar placeholder.
  String get initials {
    final parts = title.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return title.isNotEmpty ? title[0].toUpperCase() : '?';
  }
}
