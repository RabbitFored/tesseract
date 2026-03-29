import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../dashboard/presentation/utils/display_helpers.dart';
import '../../../downloader/data/download_manager.dart';
import '../../../downloader/domain/download_item.dart';
import '../../../downloader/domain/download_provider.dart';
import '../../domain/media_message.dart';

/// A single media file row with "Add to Queue" / already-queued indicator.
class MediaFileTile extends ConsumerWidget {
  const MediaFileTile({
    super.key,
    required this.media,
  });

  final MediaMessage media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Check if this file is already in the download queue.
    final isQueued = ref.watch(
      downloadQueueProvider.select((async) => async.whenOrNull(
            data: (items) => items.any((i) => i.fileId == media.fileId),
          ) ??
          false),
    );

    final iconData = _iconForType(media.mediaType);
    final iconColor = _colorForType(media.mediaType);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(iconData, color: iconColor, size: 22),
      ),
      title: Text(
        media.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: Row(
        children: [
          // Media type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              media.typeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatBytes(media.fileSize),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (media.caption.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                media.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: isQueued
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF00E676),
                size: 20,
              ),
            )
          : SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.download_rounded),
                color: const Color(0xFF2AABEE),
                tooltip: 'Add to download queue',
                onPressed: () => _addToQueue(context, ref),
                padding: EdgeInsets.zero,
              ),
            ),
    );
  }

  Future<void> _addToQueue(BuildContext context, WidgetRef ref) async {
    final manager = ref.read(downloadManagerProvider);
    final appDir = await getApplicationDocumentsDirectory();
    final localPath = '${appDir.path}/downloads/${media.fileName}';

    await manager.enqueue(DownloadItem(
      fileId: media.fileId,
      localPath: localPath,
      totalSize: media.fileSize,
      fileName: media.fileName,
      chatId: media.chatId,
      messageId: media.messageId,
    ));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${media.fileName}" to download queue'),
          backgroundColor: const Color(0xFF2AABEE),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => Navigator.of(context).popUntil(
              (route) => route.isFirst,
            ),
          ),
        ),
      );
    }
  }

  IconData _iconForType(MediaType type) => switch (type) {
        MediaType.video => Icons.movie_rounded,
        MediaType.audio => Icons.audiotrack_rounded,
        MediaType.photo => Icons.image_rounded,
        MediaType.document => Icons.insert_drive_file_rounded,
        MediaType.voiceNote => Icons.mic_rounded,
        MediaType.videoNote => Icons.videocam_rounded,
        MediaType.animation => Icons.gif_rounded,
      };

  Color _colorForType(MediaType type) => switch (type) {
        MediaType.video => const Color(0xFFE040FB),
        MediaType.audio => const Color(0xFFFF6D00),
        MediaType.photo => const Color(0xFF00E676),
        MediaType.document => const Color(0xFF448AFF),
        MediaType.voiceNote => const Color(0xFFFFAB00),
        MediaType.videoNote => const Color(0xFFE040FB),
        MediaType.animation => const Color(0xFF69F0AE),
      };
}
