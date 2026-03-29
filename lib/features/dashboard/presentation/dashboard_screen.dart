import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../downloader/data/download_manager.dart';
import '../../downloader/domain/download_item.dart';
import '../../downloader/domain/download_provider.dart';
import '../../downloader/domain/download_status.dart';
import 'widgets/download_item_card.dart';
import 'widgets/shared_widgets.dart';
import '../../browser/presentation/chat_list_screen.dart';
import '../../settings/presentation/settings_screen.dart';
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

class _CompletedTab extends ConsumerWidget {
  const _CompletedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(completedDownloadsProvider);

    if (completed.isEmpty) {
      return const EmptyDownloadState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No completed downloads',
        subtitle: 'Finished files will appear here',
      );
    }

    return _AnimatedDownloadList(
      items: completed,
      listKey: 'completed',
    );
  }
}

// ── Animated list wrapper ───────────────────────────────────────

class _AnimatedDownloadList extends StatefulWidget {
  const _AnimatedDownloadList({
    required this.items,
    required this.listKey,
  });

  final List<DownloadItem> items;
  final String listKey;

  @override
  State<_AnimatedDownloadList> createState() => _AnimatedDownloadListState();
}

class _AnimatedDownloadListState extends State<_AnimatedDownloadList> {
  final _listKey = GlobalKey<AnimatedListState>();
  List<DownloadItem> _currentItems = [];

  @override
  void initState() {
    super.initState();
    _currentItems = List.of(widget.items);
  }

  @override
  void didUpdateWidget(_AnimatedDownloadList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _diffAndAnimate(oldWidget.items, widget.items);
  }

  void _diffAndAnimate(
      List<DownloadItem> oldList, List<DownloadItem> newList) {
    final oldIds = oldList.map((e) => e.fileId).toSet();
    final newIds = newList.map((e) => e.fileId).toSet();

    // Removed items (animate out)
    final removed = oldIds.difference(newIds);
    for (final id in removed) {
      final index = _currentItems.indexWhere((e) => e.fileId == id);
      if (index != -1) {
        final item = _currentItems.removeAt(index);
        _listKey.currentState?.removeItem(
          index,
          (context, animation) => _buildAnimatedItem(item, animation),
          duration: const Duration(milliseconds: 300),
        );
      }
    }

    // Added items (animate in)
    final added = newIds.difference(oldIds);
    for (final id in added) {
      final newItem = newList.firstWhere((e) => e.fileId == id);
      _currentItems.add(newItem);
      final insertIndex = _currentItems.length - 1;
      _listKey.currentState?.insertItem(
        insertIndex,
        duration: const Duration(milliseconds: 300),
      );
    }

    // Updated items (replace in place, no animation — handled by RepaintBoundary)
    for (int i = 0; i < _currentItems.length; i++) {
      final updated = newList
          .cast<DownloadItem?>()
          .firstWhere((e) => e!.fileId == _currentItems[i].fileId,
              orElse: () => null);
      if (updated != null) {
        _currentItems[i] = updated;
      }
    }

    // Rebuild to pick up in-place updates
    if (mounted) setState(() {});
  }

  Widget _buildAnimatedItem(DownloadItem item, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: DownloadItemCard(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _currentItems.length,
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemBuilder: (context, index, animation) {
        if (index >= _currentItems.length) return const SizedBox.shrink();
        return _buildAnimatedItem(_currentItems[index], animation);
      },
    );
  }
}
