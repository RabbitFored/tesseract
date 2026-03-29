import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/chat_item.dart';

/// A single chat row in the ChatListScreen.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
  });

  final ChatItem chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _Avatar(chat: chat),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: Text(
        chat.subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: chat.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.chat});
  final ChatItem chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Deterministic color from chat ID.
    final colors = [
      const Color(0xFFE040FB),
      const Color(0xFF2AABEE),
      const Color(0xFF00E676),
      const Color(0xFFFF6D00),
      const Color(0xFFFF1744),
      const Color(0xFF448AFF),
      const Color(0xFFFFD740),
    ];
    final bgColor = colors[chat.id.abs() % colors.length];

    if (chat.photoPath.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: FileImage(File(chat.photoPath)),
        backgroundColor: bgColor.withValues(alpha: 0.3),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: bgColor.withValues(alpha: 0.2),
      child: Text(
        chat.initials,
        style: TextStyle(
          color: bgColor,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
