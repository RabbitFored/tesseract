import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/presentation/statistics_screen.dart';
import '../../downloader/data/download_manager.dart';
import '../../downloader/domain/download_item.dart';
import '../../downloader/domain/download_provider.dart';
import '../../downloader/domain/download_status.dart';
import 'widgets/download_item_card.dart';
import 'widgets/shared_widgets.dart';
import '../../browser/presentation/chat_list_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/add_link_dialog.dart';
import 'widgets/stats_header.dart';

/// Main dashboard screen with TabBar separating Active/Queued from Completed.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Downloads',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Statistics',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StatisticsScreen(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_rounded),
              tooltip: 'Browse Chats',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChatListScreen(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: const Color(0xFF2AABEE),
            labelColor: const Color(0xFF2AABEE),
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorSize: TabBarIndicatorSize.label,
            dividerHeight: 0.5,
            tabs: const [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: const Column(
          children: [
            StatsHeader(),
            Expanded(
              child: TabBarView(
                children: [
                  _ActiveTab(),
                  _CompletedTab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('Browse Chats'),
                      subtitle: const Text('Find files in your Telegram chats'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChatListScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.link_rounded),
                      title: const Text('Paste Link'),
                      subtitle: const Text('Download from a Telegram message link'),
                      onTap: () {
                        Navigator.pop(ctx);
                        showDialog(
                          context: context,
                          builder: (_) => const AddLinkDialog(),
                        ).then((added) {
                          if (added == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Downloading file from link'),
                                backgroundColor: Color(0xFF2AABEE),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Download'),
          backgroundColor: const Color(0xFF2AABEE),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

// ── Active / Queued / Paused tab ────────────────────────────────

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(downloadQueueProvider);

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (allItems) {
        final items = allItems
            .where((i) =>
                i.status == DownloadStatus.downloading ||
                i.status == DownloadStatus.queued ||
                i.status == DownloadStatus.paused ||
                i.status == DownloadStatus.error)
            .toList();

        if (items.isEmpty) {
          return const EmptyDownloadState(
            icon: Icons.cloud_download_outlined,
            title: 'No active downloads',
            subtitle: 'Browse chats to find files to download',
          );
        }

        final manager = ref.read(downloadManagerProvider);

        return Column(
          children: [
            BulkActionBar(
              items: items,
              onPauseAll: manager.pauseAll,
              onResumeAll: manager.resumeAll,
            ),
            Expanded(
              child: _AnimatedDownloadList(
                items: items,
                listKey: 'active',
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Completed tab ───────────────────────────────────────────────

class _CompletedTab extends ConsumerStatefulWidget {
  const _CompletedTab();

  @override
  ConsumerState<_CompletedTab> createState() => _CompletedTabState();
}

class _CompletedTabState extends ConsumerState<_CompletedTab> {
  final Set<int> _selected = {};
  bool _isSelectionMode = false;

  void _toggleSelection(int fileId) {
    setState(() {
      if (_selected.contains(fileId)) {
        _selected.remove(fileId);
        if (_selected.isEmpty) _isSelectionMode = false;
      } else {
        _selected.add(fileId);
      }
    });
  }

  void _selectAll(List<DownloadItem> items) {
    setState(() {
      _selected.addAll(items.map((i) => i.fileId));
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;

    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete files?'),
        content: Text(
          'Remove $count completed ${count == 1 ? 'file' : 'files'} from the download list?\n\n'
          'Downloaded files on storage will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final manager = ref.read(downloadManagerProvider);
    await manager.removeMultiple(_selected.toList());
    _clearSelection();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $count files'),
          backgroundColor: const Color(0xFF2AABEE),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = ref.watch(completedDownloadsProvider);
    final theme = Theme.of(context);

    if (completed.isEmpty) {
      return const EmptyDownloadState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No completed downloads',
        subtitle: 'Finished files will appear here',
      );
    }

    return Column(
      children: [
        // ── Selection action bar ─────────────────────────────
        if (_isSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clearSelection,
                  tooltip: 'Cancel',
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  '${_selected.length} selected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _selectAll(completed),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: const Text('All'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2AABEE),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

        // ── List ─────────────────────────────────────────────
        Expanded(
          child: _isSelectionMode
              ? ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 80),
                  itemCount: completed.length,
                  itemBuilder: (context, index) {
                    final item = completed[index];
                    final isSelected = _selected.contains(item.fileId);
                    return InkWell(
                      onTap: () => _toggleSelection(item.fileId),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(item.fileId),
                              activeColor: const Color(0xFF2AABEE),
                            ),
                          ),
                          Expanded(child: DownloadItemCard(item: item)),
                        ],
                      ),
                    );
                  },
                )
              : _AnimatedDownloadList(
                  items: completed,
                  listKey: 'completed',
                  onLongPress: (fileId) {
                    setState(() {
                      _isSelectionMode = true;
                      _selected.add(fileId);
                    });
                  },
                ),
        ),
      ],
    );
  }
}

// ── Animated list wrapper ───────────────────────────────────────

class _AnimatedDownloadList extends StatelessWidget {
  const _AnimatedDownloadList({
    required this.items,
    required this.listKey,
    this.onLongPress,
  });

  final List<DownloadItem> items;
  final String listKey;
  final void Function(int fileId)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onLongPress: onLongPress != null
              ? () => onLongPress!(item.fileId)
              : null,
          child: DownloadItemCard(item: item),
        );
      },
    );
  }
}
