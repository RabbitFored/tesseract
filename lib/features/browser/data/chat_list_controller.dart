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
///
/// Streams chats into state progressively — each resolved [ChatItem] is
/// added to state immediately instead of waiting for the full batch.
class ChatListController extends StateNotifier<ChatListState> {
  ChatListController(this._ref) : super(const ChatListState());

  final Ref _ref;

  /// Initial page size — small for a fast first render.
  static const int _initialPageSize = 10;

  /// Subsequent page size for pagination.
  static const int _pageSize = 20;

  /// Tracks how many chats we have asked TDLib for so far (for pagination).
  int _fetchedSoFar = 0;

  // ── Initial Load ────────────────────────────────────────────────

  /// Load the initial batch of chats progressively.
  /// Each chat is inserted into state as soon as its detail is resolved,
  /// so the list renders immediately instead of waiting for all futures.
  Future<void> loadChats() async {
    if (state.isLoading) return;
    state = const ChatListState(isLoading: true);
    _fetchedSoFar = 0;

    try {
      final send = _ref.read(tdlibSendProvider);

      // 1. Ask TDLib to fetch chats from the server into local cache.
      //    Code 404 = "already at the end", which is fine.
      // ignore: prefer_const_constructors
      final loadResult = await send(LoadChats(
        chatList: null,
        limit: _initialPageSize,
      ));

      if (loadResult is TdError && loadResult.code != 404) {
        state = state.copyWith(isLoading: false, error: loadResult.message);
        return;
      }

      // 2. Get the ordered list of chat IDs from TDLib's local cache.
      // ignore: prefer_const_constructors
      final result = await send(GetChats(
        chatList: null,
        limit: _initialPageSize,
      ));

      if (result is! Chats) {
        if (result is TdError) {
          state = state.copyWith(isLoading: false, error: result.message);
        } else {
          state = state.copyWith(isLoading: false);
        }
        return;
      }

      _fetchedSoFar = result.chatIds.length;

      // 3. Stream each ChatItem into state as soon as it resolves.
      //    This makes the list start populating within milliseconds of
      //    the first GetChat response, rather than after all 10–30 resolve.
      await _streamChatDetails(send, result.chatIds, replace: true);

      state = state.copyWith(
        isLoading: false,
        hasMore: result.chatIds.length >= _initialPageSize,
      );
    } catch (e) {
      Log.error('Failed to load chats', error: e, tag: 'CHAT_LIST');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Pagination ──────────────────────────────────────────────────

  /// Load more chats when the user scrolls to the bottom.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.chats.isEmpty) return;
    state = state.copyWith(isLoading: true);

    try {
      final send = _ref.read(tdlibSendProvider);

      // Ask TDLib for the next page from the server.
      // ignore: prefer_const_constructors
      final loadResult = await send(LoadChats(
        chatList: null,
        limit: _pageSize,
      ));

      if (loadResult is TdError && loadResult.code != 404) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // GetChats always returns from the beginning of TDLib's ordered list.
      // We request all chats up to our current position + one more page.
      final totalWanted = _fetchedSoFar + _pageSize;
      // ignore: prefer_const_constructors
      final result = await send(GetChats(
        chatList: null,
        limit: totalWanted,
      ));

      if (result is! Chats) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // Only process IDs that are new (not already shown).
      final existingIds = state.chats.map((c) => c.id).toSet();
      final newIds =
          result.chatIds.where((id) => !existingIds.contains(id)).toList();

      if (newIds.isEmpty) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      _fetchedSoFar = result.chatIds.length;

      await _streamChatDetails(send, newIds, replace: false);

      state = state.copyWith(
        isLoading: false,
        hasMore: newIds.length >= _pageSize,
      );
    } catch (e) {
      Log.error('Failed to load more chats', error: e, tag: 'CHAT_LIST');
      state = state.copyWith(isLoading: false);
    }
  }

  // ── Private helpers ─────────────────────────────────────────────

  /// Fetches [ChatItem] details for each ID and adds them to state
  /// one-by-one as each future resolves, giving a progressive/streaming UX.
  ///
  /// [replace] = true clears the existing list first (initial load).
  /// [replace] = false appends to the existing list (pagination).
  Future<void> _streamChatDetails(
    Future<TdObject?> Function(TdFunction) send,
    List<int> chatIds, {
    required bool replace,
  }) async {
    if (replace) {
      // Kick off the initial empty list so the skeleton disappears quickly.
      state = state.copyWith(chats: []);
    }

    // Fire all requests concurrently but add each result to state
    // as soon as it resolves, rather than collecting all and bulk-inserting.
    final futures = chatIds.map((id) async {
      final item = await _fetchChatDetail(send, id);
      if (item == null || !mounted) return;

      if (replace) {
        // Append to whatever is already in state (other futures may have
        // added items before this one resolved).
        state = state.copyWith(chats: [...state.chats, item]);
      } else {
        state = state.copyWith(chats: [...state.chats, item]);
      }
    });

    await Future.wait(futures);
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

    // Use the locally-cached small photo path if available.
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
