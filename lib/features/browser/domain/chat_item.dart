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
    this.isBot = false,
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
  final bool isBot;
  final bool hasMedia;

  /// Initials for avatar placeholder — surrogate-safe.
  String get initials {
    final t = title.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    // Use runes to avoid splitting surrogate pairs.
    String firstChar(String s) {
      final r = s.runes;
      if (r.isEmpty) return '';
      final cp = r.first;
      // Skip replacement characters and control chars.
      if (cp == 0xFFFD || cp < 0x20) return '';
      return String.fromCharCode(cp).toUpperCase();
    }
    if (parts.length >= 2) {
      final a = firstChar(parts[0]);
      final b = firstChar(parts[1]);
      if (a.isNotEmpty && b.isNotEmpty) return '$a$b';
    }
    return firstChar(parts[0]).isNotEmpty ? firstChar(parts[0]) : '?';
  }
}
