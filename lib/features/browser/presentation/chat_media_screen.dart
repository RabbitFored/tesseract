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
import 'widgets/media_preview_sheet.dart';

/// Screen showing media files from a specific chat with server-side type
/// filtering and in-app media preview.
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
  bool _isSearchBarVisible = false;
  Timer? _debounce;

  ChatMediaConfig get _config =>
      ChatMediaConfig(widget.chatId, widget.messageThreadId);

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(chatMediaControllerProvider(_config).notifier).loadMedia());
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
      ref.read(chatMediaControllerProvider(_config).notifier).loadMore();
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isEmpty) {
        ref.read(chatMediaControllerProvider(_config).notifier).clearSearch();
      } else {
        ref.read(chatMediaControllerProvider(_config).notifier).searchMedia(query);
      }
    });
  }

  void _toggleSearch() {
    setState(() => _isSearchBarVisible = !_isSearchBarVisible);
    if (!_isSearchBarVisible) {
      _searchController.clear();
      _debounce?.cancel();
      ref.read(chatMediaControllerProvider(_config).notifier).clearSearch();
    } else {
      Future.microtask(() => _searchFocusNode.requestFocus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatMediaControllerProvider(_config));
    final theme = Theme.of(context);
    final media = state.displayMedia;
    final isLoadingMore =
        state.isSearchMode ? state.isSearching : state.isLoadingMore;

    return Scaffold(
      appBar: AppBar(
        title: _isSearchBarVisible
            ? _SearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  ref.read(chatMediaControllerProvider(_config).notifier).clearSearch();
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sanitizeText(widget.chatTitle),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: -0.3),
                  ),
                  Text(
                    state.isLoading
                        ? 'Loading...'
                        : state.isSearchMode
                            ? '${state.searchResults.length} results'
                            : '${state.media.length} files',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearchBarVisible
                ? Icons.close_rounded
                : Icons.search_rounded),
            onPressed: _toggleSearch,
          ),
          if (media.isNotEmpty && !_isSearchBarVisible)
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded),
              tooltip: 'Queue all visible',
              onPressed: () => _addAllToQueue(context, media),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Type filter bar (server-side) ─────────────────
          _FilterBar(
            activeFilter: state.activeFilter,
            onFilterChanged: (type) =>
                ref.read(chatMediaControllerProvider(_config).notifier).setFilter(type),
          ),

          // ── Search active indicator ───────────────────────
          if (state.isSearchMode)
            _SearchBanner(
              query: state.searchQuery,
              count: state.searchResults.length,
              onClear: () {
                _searchController.clear();
                ref.read(chatMediaControllerProvider(_config).notifier).clearSearch();
              },
            ),

          Expanded(child: _buildBody(state, media, isLoadingMore, theme)),
        ],
      ),
    );
  }

  Widget _buildBody(
    ChatMediaState state,
    List<MediaMessage> media,
    bool isLoadingMore,
    ThemeData theme,
  ) {
    if (state.isLoading && media.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error.isNotEmpty && media.isEmpty) {
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
                onPressed: () =>
                    ref.read(chatMediaControllerProvider(_config).notifier).loadMedia(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (media.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(chatMediaControllerProvider(_config).notifier).reload(),
        child: LayoutBuilder(
          builder: (_, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.perm_media_outlined,
                          size: 56,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text(
                        state.activeFilter != null
                            ? 'No ${state.activeFilter!.name} files found'
                            : state.isSearchMode
                                ? 'No results for "${state.searchQuery}"'
                                : 'No media in this chat',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(chatMediaControllerProvider(_config).notifier).reload(),
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
          return MediaFileTile(
            media: media[index],
            onPreview: () => _showPreview(context, media[index]),
          );
        },
      ),
    );
  }

  void _showPreview(BuildContext context, MediaMessage media) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaPreviewSheet(media: media),
    );
  }

  Future<void> _addAllToQueue(
      BuildContext context, List<MediaMessage> media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Queue all visible?'),
        content: Text(
          'Add ${media.length} files '
          '(${formatBytes(media.fold(0, (s, m) => s + m.fileSize))}) '
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
      await manager.enqueue(DownloadItem(
        fileId: m.fileId,
        localPath: '${appDir.path}/downloads/${m.fileName}',
        totalSize: m.fileSize,
        fileName: m.fileName,
        chatId: m.chatId,
        messageId: m.messageId,
      ));
      added++;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added $added files to queue'),
        backgroundColor: const Color(0xFF2AABEE),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ── Filter bar ────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final MediaType? activeFilter;
  final ValueChanged<MediaType?> onFilterChanged;

  static const _filters = [
    (null, 'All', Icons.apps_rounded),
    (MediaType.video, 'Videos', Icons.movie_rounded),
    (MediaType.audio, 'Audio', Icons.audiotrack_rounded),
    (MediaType.photo, 'Photos', Icons.image_rounded),
    (MediaType.document, 'Docs', Icons.insert_drive_file_rounded),
    (MediaType.animation, 'GIFs', Icons.gif_rounded),
    (MediaType.voiceNote, 'Voice', Icons.mic_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: _filters.map((f) {
          final (type, label, icon) = f;
          final selected = activeFilter == type;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: selected,
              avatar: Icon(icon,
                  size: 14,
                  color: selected
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant),
              label: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant)),
              selectedColor: const Color(0xFF2AABEE),
              checkmarkColor: Colors.white,
              showCheckmark: false,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onFilterChanged(type),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Search banner ─────────────────────────────────────────────────

class _SearchBanner extends StatelessWidget {
  const _SearchBanner(
      {required this.query, required this.count, required this.onClear});
  final String query;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF2AABEE).withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 14, color: Color(0xFF2AABEE)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$count results for "$query"',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFF2AABEE)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded,
                size: 14, color: Color(0xFF2AABEE)),
          ),
        ],
      ),
    );
  }
}

// ── Search text field ─────────────────────────────────────────────

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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
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
