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
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.chatTitle} Topics'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(child: Text('Error: $_error'));
    }

    if (_topics.isEmpty) {
      return const Center(child: Text('No topics found.'));
    }

    return ListView.builder(
      itemCount: _topics.length,
      itemBuilder: (context, index) {
        final topic = _topics[index];
        return ListTile(
          title: Text(topic.name),
          trailing: const Icon(Icons.chevron_right_rounded),
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
    );
  }
}
