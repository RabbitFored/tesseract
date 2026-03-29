import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../downloader/domain/download_item.dart';
import '../../downloader/domain/download_status.dart';

/// Empty state widget for download list tabs.
class EmptyDownloadState extends StatelessWidget {
  const EmptyDownloadState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulk action bar for active/queued tab.
class BulkActionBar extends ConsumerWidget {
  const BulkActionBar({
    super.key,
    required this.items,
    required this.onPauseAll,
    required this.onResumeAll,
  });

  final List<DownloadItem> items;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasActive =
        items.any((i) => i.status == DownloadStatus.downloading);
    final hasPaused = items.any((i) => i.status == DownloadStatus.paused);

    if (!hasActive && !hasPaused) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasActive)
            TextButton.icon(
              onPressed: onPauseAll,
              icon: const Icon(Icons.pause_rounded, size: 16),
              label: const Text('Pause All'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFFAB00),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (hasActive && hasPaused) const SizedBox(width: 8),
          if (hasPaused)
            TextButton.icon(
              onPressed: onResumeAll,
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: const Text('Resume All'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2AABEE),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
