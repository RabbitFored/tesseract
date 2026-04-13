import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../downloader/data/download_manager.dart';
import '../../../downloader/domain/download_item.dart';
import '../../../downloader/domain/download_status.dart';
import '../utils/display_helpers.dart';

/// A single download item card with file icon, progress bar, speed,
/// ETA, size info, and action buttons (pause/resume/cancel/share).
class DownloadItemCard extends ConsumerWidget {
  const DownloadItemCard({
    super.key,
    required this.item,
  });

  final DownloadItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = StatusStyle.colorFor(item.status);
    final fileColor = FileTypeIcon.colorFor(item.fileName);
    final fileIcon = FileTypeIcon.iconFor(item.fileName);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: item.status == DownloadStatus.completed
            ? () => _openFile(context)
            : null,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── File type icon ────────────────────────────
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: fileColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(fileIcon, color: fileColor, size: 22),
                ),
                const SizedBox(width: 12),

                // ── Info column ───────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File name
                      Text(
                        sanitizeText(item.fileName.isNotEmpty
                            ? item.fileName
                            : 'File #${item.fileId}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Progress bar (for active/paused)
                      if (item.status == DownloadStatus.downloading ||
                          item.status == DownloadStatus.paused) ...[
                        RepaintBoundary(
                          child: _ProgressBar(
                            progress: item.progress,
                            color: statusColor,
                            backgroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.08),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Indeterminate progress for extracting status
                      if (item.status == DownloadStatus.extracting) ...[
                        RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              minHeight: 5,
                              backgroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFAB47BC),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Status + size + speed row
                      Row(
                        children: [
                          // Status badge — contextual for errors with reasons
                          if (item.status == DownloadStatus.error &&
                              item.errorReason.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ErrorBadgeStyle.colorFor(
                                        item.errorReason)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    ErrorBadgeStyle.iconFor(item.errorReason),
                                    size: 10,
                                    color: ErrorBadgeStyle.colorFor(
                                        item.errorReason),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    ErrorBadgeStyle.labelFor(
                                        item.errorReason),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: ErrorBadgeStyle.colorFor(
                                          item.errorReason),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Default status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                StatusStyle.labelFor(item.status),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),

                          // Mirror badge
                          if (item.mirrorChannelId != 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2AABEE)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sync_rounded,
                                      size: 9, color: Color(0xFF2AABEE)),
                                  SizedBox(width: 2),
                                  Text(
                                    'Mirror',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2AABEE),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],

                          // Retry count badge
                          if (item.retryCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFAB00)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '↺${item.retryCount}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFAB00),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],

                          // Size progress
                          Expanded(
                            child: Text(
                              item.status == DownloadStatus.completed
                                  ? formatBytes(item.totalSize)
                                  : formatSizeProgress(item),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),

                          // Speed + ETA (while downloading)
                          if (item.status == DownloadStatus.downloading) ...[
                            if (item.currentSpeed > 0) ...[
                              Text(
                                '${formatSpeed(item.currentSpeed)} ',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                              if (item.etaSeconds != null)
                                Text(
                                  formatEta(item.etaSeconds!),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ] else
                              Text(
                                formatProgress(item),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Action buttons ────────────────────────────
                _ActionButtons(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    final result = await OpenFilex.open(item.localPath);

    if (result.type != ResultType.done && context.mounted) {
      final message = switch (result.type) {
        ResultType.noAppToOpen =>
          'No app found to open this file type',
        ResultType.fileNotFound =>
          'File not found at ${item.localPath}',
        ResultType.permissionDenied =>
          'Permission denied — check storage access',
        _ => 'Failed to open file: ${result.message}',
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Isolated progress bar.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 5,
        backgroundColor: backgroundColor,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Context-aware action buttons based on download status.
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: switch (item.status) {
        DownloadStatus.downloading => [
            _IconBtn(
              icon: Icons.pause_rounded,
              tooltip: 'Pause',
              color: const Color(0xFFFFAB00),
              onPressed: () => manager.pauseDownload(item.fileId),
            ),
            _IconBtn(
              icon: Icons.close_rounded,
              tooltip: 'Cancel',
              color: const Color(0xFFFF1744),
              onPressed: () => _confirmRemove(context, ref),
            ),
          ],
        DownloadStatus.paused => [
            _IconBtn(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Resume',
              color: const Color(0xFF2AABEE),
              onPressed: () => manager.resumeDownload(item.fileId),
            ),
            _IconBtn(
              icon: Icons.close_rounded,
              tooltip: 'Remove',
              color: const Color(0xFFFF1744),
              onPressed: () => _confirmRemove(context, ref),
            ),
          ],
        DownloadStatus.queued => [
            _IconBtn(
              icon: Icons.arrow_upward_rounded,
              tooltip: 'Prioritize',
              color: const Color(0xFF78909C),
              onPressed: () =>
                  manager.setPriority(item.fileId, item.priority + 1),
            ),
            _IconBtn(
              icon: Icons.close_rounded,
              tooltip: 'Remove',
              color: const Color(0xFFFF1744),
              onPressed: () => _confirmRemove(context, ref),
            ),
          ],
        DownloadStatus.extracting => [
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFFAB47BC),
                  ),
                ),
              ),
            ),
          ],
        DownloadStatus.completed => [
            _IconBtn(
              icon: Icons.share_rounded,
              tooltip: 'Share',
              color: const Color(0xFF2AABEE),
              onPressed: () => _shareFile(context),
            ),
            _IconBtn(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Remove',
              color: const Color(0xFF78909C),
              onPressed: () => manager.removeFromQueue(item.fileId),
            ),
          ],
        DownloadStatus.error => [
            _IconBtn(
              icon: Icons.refresh_rounded,
              tooltip: 'Retry',
              color: const Color(0xFF2AABEE),
              onPressed: () => manager.manualRetry(item.fileId),
            ),
            _IconBtn(
              icon: Icons.close_rounded,
              tooltip: 'Remove',
              color: const Color(0xFFFF1744),
              onPressed: () => manager.removeFromQueue(item.fileId),
            ),
          ],
      },
    );
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(item.localPath)],
          text: item.fileName,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _confirmRemove(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text(
          item.isActive
              ? 'This will cancel the active download and remove it from the queue.'
              : 'Remove "${sanitizeText(item.fileName.isNotEmpty ? item.fileName : 'File #${item.fileId}')}" from the queue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(downloadManagerProvider).removeFromQueue(item.fileId);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1744),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: color,
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
