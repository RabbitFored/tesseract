import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart' hide Text;

import '../../../core/tdlib/tdlib_provider.dart';
import 'chat_media_screen.dart';

class TopicListScreen extends ConsumerStatefulWidget {
  const TopicListScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  final int chatId;
  final String chatTitle;

  @override
  ConsumerState<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends ConsumerState<TopicListScreen> {
  bool _isLoading = true;
  String _error = '';
  List<ForumTopicInfo> _topics = [];

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final send = ref.read(tdlibSendProvider);
    try {
      final result = await send(GetForumTopics(
        chatId: widget.chatId,
        query: '',
        offsetDate: 0,
        offsetMessageId: 0,
        offsetMessageThreadId: 0,
        limit: 100,
      ));

      if (!mounted) return;

      if (result is ForumTopics) {
        setState(() {
          _topics = result.topics.map((t) => t.info).toList();
          _isLoading = false;
        });
      } else if (result is TdError) {
        setState(() {
          _error = result.message;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Unexpected response';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chatTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3),
            ),
            Text(
              _isLoading ? 'Loading topics...' : '${_topics.length} topics',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        // Also allow viewing all media in the chat (ignoring topics).
        actions: [
          IconButton(
            icon: const Icon(Icons.perm_media_outlined),
            tooltip: 'All Media',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatMediaScreen(
                  chatId: widget.chatId,
                  chatTitle: '${widget.chatTitle} (All)',
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load topics', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadTopics,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_topics.isEmpty) {
      return const Center(child: Text('No topics found.'));
    }

    return RefreshIndicator(
      onRefresh: _loadTopics,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _topics.length,
        separatorBuilder: (_, __) => Divider(
          height: 0.5,
          indent: 16,
          endIndent: 16,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          final topic = _topics[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tag_rounded, color: Color(0xFF2AABEE), size: 20),
            ),
            title: Text(
              topic.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatMediaScreen(
                    chatId: widget.chatId,
                    chatTitle: topic.name,
                    messageThreadId: topic.messageThreadId,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
