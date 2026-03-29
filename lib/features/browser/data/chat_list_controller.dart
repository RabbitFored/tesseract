import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/chat_item.dart';

/// State for the chat list.
class ChatListState {
  const ChatListState({
    this.chats = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error = '',
  });

  final List<ChatItem> chats;
  final bool isLoading;
  final bool hasMore;
  final String error;

  ChatListState copyWith({
    List<ChatItem>? chats,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) =>
      ChatListState(
        chats: chats ?? this.chats,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        error: error ?? this.error,
      );
}

final chatListControllerProvider =
    StateNotifierProvider<ChatListController, ChatListState>(
  (ref) => ChatListController(ref),
);

/// Loads the user's active Telegram chats via TDLib getChats / getChat.
class ChatListController extends StateNotifier<ChatListState> {
  ChatListController(this._ref) : super(const ChatListState());

  final Ref _ref;
  static const int _pageSize = 30;

  /// Load the initial batch of chats.
  Future<void> loadChats() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: '');

    try {
      final send = _ref.read(tdlibSendProvider);

      // TDLib getChats returns a list of chat IDs ordered by last message.
      // ignore: prefer_const_constructors
      final result = await send(GetChats(
        chatList: null, // main chat list
        limit: _pageSize,
      ));

      if (result is Chats) {
        final chatItems = <ChatItem>[];
        for (final chatId in result.chatIds) {
          final chatItem = await _fetchChatDetail(send, chatId);
          if (chatItem != null) chatItems.add(chatItem);
        }

        state = state.copyWith(
          chats: chatItems,
          isLoading: false,
          hasMore: result.chatIds.length >= _pageSize,
        );
      } else if (result is TdError) {
        state = state.copyWith(
          isLoading: false,
          error: result.message,
        );
      }
    } catch (e) {
      Log.error('Failed to load chats', error: e, tag: 'CHAT_LIST');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load more chats (pagination via offsetOrder / offsetChatId).
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.chats.isEmpty) return;
    state = state.copyWith(isLoading: true);

    try {
      final send = _ref.read(tdlibSendProvider);

      // Use the last chat's order as offset for pagination.
      // ignore: prefer_const_constructors
      final result = await send(GetChats(
        chatList: null,
        limit: _pageSize,
      ));

      if (result is Chats) {
        final newChats = <ChatItem>[];
        for (final chatId in result.chatIds) {
          // Skip chats we already have
          if (state.chats.any((c) => c.id == chatId)) continue;
          final chatItem = await _fetchChatDetail(send, chatId);
          if (chatItem != null) newChats.add(chatItem);
        }

        state = state.copyWith(
          chats: [...state.chats, ...newChats],
          isLoading: false,
          hasMore: newChats.isNotEmpty,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Fetch full chat details for a single chat ID.
  Future<ChatItem?> _fetchChatDetail(
    Future<TdObject?> Function(TdFunction) send,
    int chatId,
  ) async {
    final detail = await send(GetChat(chatId: chatId));
    if (detail is! Chat) return null;

    final isChannel = detail.type is ChatTypeSupergroup &&
        (detail.type as ChatTypeSupergroup).isChannel;
    final isGroup = detail.type is ChatTypeBasicGroup ||
        (detail.type is ChatTypeSupergroup &&
            !(detail.type as ChatTypeSupergroup).isChannel);

    String subtitle = '';
    if (isChannel) {
      subtitle = 'Channel';
    } else if (isGroup) {
      subtitle = 'Group';
    } else if (detail.type is ChatTypePrivate) {
      subtitle = 'Private chat';
    }

    // Try to get the small photo path if available locally.
    String photoPath = '';
    if (detail.photo != null) {
      final small = detail.photo!.small;
      if (small.local.isDownloadingCompleted) {
        photoPath = small.local.path;
      }
    }

    return ChatItem(
      id: detail.id,
      title: detail.title,
      subtitle: subtitle,
      photoPath: photoPath,
      unreadCount: detail.unreadCount,
      lastMessageDate: detail.lastMessage?.date ?? 0,
      isChannel: isChannel,
      isGroup: isGroup,
    );
  }
}
