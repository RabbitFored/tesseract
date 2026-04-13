import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_list_controller.dart';
import 'chat_media_screen.dart';
import 'topic_list_screen.dart';
import 'widgets/chat_tile.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _scrollController = ScrollController();
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(chatListControllerProvider.notifier).loadChats());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(chatListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatListControllerProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(chatListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  border: InputBorder.none,
                  hintStyle:
                      TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                onChanged: notifier.searchChats,
              )
            : const Text('Browse Chats',
                style: TextStyle(
                    fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() => _isSearching = !_isSearching);
              if (!_isSearching) {
                _searchController.clear();
                notifier.clearSearch();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Chat type filter bar ──────────────────────────
          _ChatFilterBar(
            activeFilter: state.chatTypeFilter,
            mediaOnly: state.mediaOnly,
            onFilterChanged: notifier.setChatTypeFilter,
            onMediaOnlyToggled: notifier.toggleMediaOnly,
          ),
          Expanded(child: _buildBody(state, theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ChatListState state, ThemeData theme) {
    if (state.isLoading && state.displayChats.isEmpty && !_isSearching) {
      return _SkeletonChatList(theme: theme);
    }

    if (state.error.isNotEmpty && state.displayChats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load chats',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(state.error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => ref
                    .read(chatListControllerProvider.notifier)
                    .loadChats(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.displayChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isSearching) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
            ] else
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 56,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              state.isSearching ? 'Searching...' : 'No chats found',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(chatListControllerProvider.notifier)
          .loadChats(forceRefresh: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.displayChats.length + (state.isLoading ? 3 : 0),
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          indent: 72,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          if (index >= state.displayChats.length) {
            return _SkeletonChatTile(theme: theme);
          }
          final chat = state.displayChats[index];
          return ChatTile(
            chat: chat,
            onTap: () {
              if (chat.isForum) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TopicListScreen(
                      chatId: chat.id, chatTitle: chat.title),
                ));
              } else {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatMediaScreen(
                      chatId: chat.id, chatTitle: chat.title),
                ));
              }
            },
          );
        },
      ),
    );
  }
}

// ── Chat filter bar ───────────────────────────────────────────────

class _ChatFilterBar extends StatelessWidget {
  const _ChatFilterBar({
    required this.activeFilter,
    required this.mediaOnly,
    required this.onFilterChanged,
    required this.onMediaOnlyToggled,
  });

  final ChatTypeFilter activeFilter;
  final bool mediaOnly;
  final ValueChanged<ChatTypeFilter> onFilterChanged;
  final VoidCallback onMediaOnlyToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          // Type filters
          for (final f in ChatTypeFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                selected: activeFilter == f,
                label: Text(f.label,
                    style: TextStyle(
                        fontSize: 12,
                        color: activeFilter == f
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant)),
                selectedColor: const Color(0xFF2AABEE),
                checkmarkColor: Colors.white,
                showCheckmark: false,
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onFilterChanged(f),
              ),
            ),
          // Media-only toggle
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: mediaOnly,
              avatar: Icon(Icons.perm_media_outlined,
                  size: 14,
                  color: mediaOnly
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant),
              label: Text('Media',
                  style: TextStyle(
                      fontSize: 12,
                      color: mediaOnly
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant)),
              selectedColor: const Color(0xFFAB47BC),
              checkmarkColor: Colors.white,
              showCheckmark: false,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onMediaOnlyToggled(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton loading widgets ─────────────────────────────────────

/// Full-page skeleton shown before any chats have loaded.
class _SkeletonChatList extends StatelessWidget {
  const _SkeletonChatList({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        indent: 72,
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
      itemBuilder: (_, __) => _SkeletonChatTile(theme: theme),
    );
  }
}

/// A single shimmer-like placeholder tile mimicking [ChatTile].
class _SkeletonChatTile extends StatefulWidget {
  const _SkeletonChatTile({required this.theme});
  final ThemeData theme;

  @override
  State<_SkeletonChatTile> createState() => _SkeletonChatTileState();
}

class _SkeletonChatTileState extends State<_SkeletonChatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.theme.colorScheme.onSurface.withValues(alpha: 0.06);
    final highlight = widget.theme.colorScheme.onSurface.withValues(alpha: 0.13);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = Color.lerp(base, highlight, _anim.value)!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar placeholder
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title line
                    Container(
                      height: 13,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 7),
                    // Subtitle line (shorter)
                    Container(
                      height: 11,
                      width: 120,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
