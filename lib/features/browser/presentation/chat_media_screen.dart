import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../dashboard/presentation/utils/display_helpers.dart';
import '../../downloader/data/download_manager.dart';
import '../../downloader/domain/download_item.dart';
import '../data/chat_media_controller.dart';
import '../domain/media_message.dart';
import 'widgets/media_file_tile.dart';

/// Screen showing filtered media files from a specific chat.
/// Supports infinite scroll via TDLib pagination and debounced search.
class ChatMediaScreen extends ConsumerStatefulWidget {
  const ChatMediaScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.messageThreadId = 0,
  });

  final int chatId;
  final String chatTitle;
  final int messageThreadId;

  @override
  ConsumerState<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends ConsumerState<ChatMediaScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  MediaType? _filterType;
  bool _isSearchBarVisible = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
          .loadMedia();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
          .loadMore();
    }
  }

  /// 500ms debounce on search input.
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isEmpty) {
        ref
            .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
            .clearSearch();
      } else {
        ref
            .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
            .searchMedia(query);
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchBarVisible = !_isSearchBarVisible;
      if (!_isSearchBarVisible) {
        _searchController.clear();
        _debounce?.cancel();
        ref
            .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
            .clearSearch();
      } else {
        // Auto-focus the search field.
        Future.microtask(() => _searchFocusNode.requestFocus());
      }
    });
  }

  void _clearSearchField() {
    _searchController.clear();
    _debounce?.cancel();
    ref
        .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
        .clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)));
    final theme = Theme.of(context);

    // Use the state's active display list (search or history).
    final displayMedia = state.displayMedia;

    // Apply local type filter on top of active list.
    final filteredMedia = _filterType == null
        ? displayMedia
        : displayMedia.where((m) => m.mediaType == _filterType).toList();

    final isLoadingAny = state.isSearchMode
        ? state.isSearching
        : state.isLoadingMore;

    return Scaffold(
      appBar: AppBar(
        title: _isSearchBarVisible
            ? _SearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onClear: _clearSearchField,
              )
            : _TitleColumn(
                title: widget.chatTitle,
                subtitle: state.isSearchMode
                    ? '${state.searchResults.length} results for "${state.searchQuery}"'
                    : state.isLoading
                        ? 'Loading...'
                        : '${state.media.length} media files',
                theme: theme,
              ),
        actions: [
          // Search toggle
          IconButton(
            icon: Icon(
              _isSearchBarVisible ? Icons.close_rounded : Icons.search_rounded,
            ),
            tooltip: _isSearchBarVisible ? 'Close search' : 'Search files',
            onPressed: _toggleSearch,
          ),
          // Download all visible media
          if (filteredMedia.isNotEmpty && !_isSearchBarVisible)
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded),
              tooltip: 'Add all to queue',
              onPressed: () => _addAllToQueue(context, ref, filteredMedia),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Search mode indicator ─────────────────────────
          if (state.isSearchMode && !_isSearchBarVisible)
            _SearchIndicator(
              query: state.searchQuery,
              resultCount: state.searchResults.length,
              onClear: () {
                _searchController.clear();
                ref
                    .read(
                        chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
                    .clearSearch();
              },
            ),

          // ── Filter chips ──────────────────────────────────
          _FilterBar(
            selectedType: _filterType,
            mediaCounts: _countByType(displayMedia),
            onSelected: (type) => setState(() {
              _filterType = _filterType == type ? null : type;
            }),
          ),

          // ── Media list ────────────────────────────────────
          Expanded(
            child: _buildList(state, filteredMedia, isLoadingAny, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    ChatMediaState state,
    List<MediaMessage> media,
    bool isLoadingMore,
    ThemeData theme,
  ) {
    // Initial loading
    if ((state.isLoading && state.media.isEmpty && !state.isSearchMode) ||
        (state.isSearching && state.searchResults.isEmpty && state.isSearchMode)) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error
    if (state.error.isNotEmpty && state.media.isEmpty && !state.isSearchMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load media',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(state.error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => ref
                    .read(
                        chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
                    .loadMedia(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Empty
    if (media.isEmpty) {
      final emptyText = state.isSearchMode
          ? 'No media files matching "${state.searchQuery}"'
          : _filterType != null
              ? 'No ${_filterType!.name} files found'
              : 'No media files in this chat';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isSearchMode
                    ? Icons.search_off_rounded
                    : Icons.perm_media_outlined,
                size: 56,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 16),
              Text(
                emptyText,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(chatMediaControllerProvider(ChatMediaConfig(widget.chatId, widget.messageThreadId)).notifier)
          .reload(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: media.length + (isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          indent: 72,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          if (index >= media.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return MediaFileTile(media: media[index]);
        },
      ),
    );
  }

  Map<MediaType, int> _countByType(List<MediaMessage> media) {
    final counts = <MediaType, int>{};
    for (final m in media) {
      counts[m.mediaType] = (counts[m.mediaType] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _addAllToQueue(
    BuildContext context,
    WidgetRef ref,
    List<MediaMessage> media,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add all to queue?'),
        content: Text(
          'This will add ${media.length} files '
          '(${formatBytes(media.fold(0, (sum, m) => sum + m.fileSize))}) '
          'to the download queue.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add All')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final manager = ref.read(downloadManagerProvider);
    final appDir = await getApplicationDocumentsDirectory();

    int added = 0;
    for (final m in media) {
      final localPath = '${appDir.path}/downloads/${m.fileName}';
      await manager.enqueue(DownloadItem(
        fileId: m.fileId,
        localPath: localPath,
        totalSize: m.fileSize,
        fileName: m.fileName,
        chatId: m.chatId,
        messageId: m.messageId,
      ));
      added++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $added files to download queue'),
          backgroundColor: const Color(0xFF2AABEE),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Search text field ───────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search files...',
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }
}

// ── Title column (default AppBar title) ─────────────────────────

class _TitleColumn extends StatelessWidget {
  const _TitleColumn({
    required this.title,
    required this.subtitle,
    required this.theme,
  });

  final String title;
  final String subtitle;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ── Search mode indicator chip ──────────────────────────────────

class _SearchIndicator extends StatelessWidget {
  const _SearchIndicator({
    required this.query,
    required this.resultCount,
    required this.onClear,
  });

  final String query;
  final int resultCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF2AABEE).withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 16, color: Color(0xFF2AABEE)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$resultCount results for "$query"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF2AABEE),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF2AABEE),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip bar ─────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedType,
    required this.mediaCounts,
    required this.onSelected,
  });

  final MediaType? selectedType;
  final Map<MediaType, int> mediaCounts;
  final void Function(MediaType) onSelected;

  @override
  Widget build(BuildContext context) {
    if (mediaCounts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final type in MediaType.values)
            if (mediaCounts.containsKey(type))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  selected: selectedType == type,
                  label: Text(
                    '${_chipLabel(type)} (${mediaCounts[type]})',
                    style: TextStyle(
                      fontSize: 12,
                      color: selectedType == type
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  selectedColor: const Color(0xFF2AABEE),
                  checkmarkColor: Colors.white,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHigh,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelected(type),
                ),
              ),
        ],
      ),
    );
  }

  String _chipLabel(MediaType type) => switch (type) {
        MediaType.document => 'Docs',
        MediaType.video => 'Videos',
        MediaType.audio => 'Audio',
        MediaType.photo => 'Photos',
        MediaType.voiceNote => 'Voice',
        MediaType.videoNote => 'V.Notes',
        MediaType.animation => 'GIFs',
      };
}
