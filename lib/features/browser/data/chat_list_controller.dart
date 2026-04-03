import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/chat_item.dart';

class ChatListState {
  const ChatListState({
    this.chats = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error = '',
    this.isSearchMode = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.mediaOnly = false,
  });

  final List<ChatItem> chats;
  final bool isLoading;
  final bool hasMore;
  final String error;

  final bool isSearchMode;
  final String searchQuery;
  final List<ChatItem> searchResults;
  final bool isSearching;
  
  final bool mediaOnly;

  List<ChatItem> get displayChats {
    final list = isSearchMode ? searchResults : chats;
    if (mediaOnly) {
      return list.where((c) => c.hasMedia).toList();
    }
    return list;
  }

  ChatListState copyWith({
    List<ChatItem>? chats,
    bool? isLoading,
    bool? hasMore,
    String? error,
    bool? isSearchMode,
    String? searchQuery,
    List<ChatItem>? searchResults,
    bool? isSearching,
    bool? mediaOnly,
  }) =>
      ChatListState(
        chats: chats ?? this.chats,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        error: error ?? this.error,
        isSearchMode: isSearchMode ?? this.isSearchMode,
        searchQuery: searchQuery ?? this.searchQuery,
        searchResults: searchResults ?? this.searchResults,
        isSearching: isSearching ?? this.isSearching,
        mediaOnly: mediaOnly ?? this.mediaOnly,
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
  Future<void> loadChats() async {
    if (state.isLoading) return;
    state = const ChatListState(isLoading: true);
    _fetchedSoFar = 0;

    try {
      final send = _ref.read(tdlibSendProvider);

      final loadResult = await send(const LoadChats(
        chatList: null,
        limit: _initialPageSize,
      ));

      bool hasMoreChats = true;
      if (loadResult is TdError) {
        if (loadResult.code == 404) {
          hasMoreChats = false; // No more chats on the server
        } else {
          state = state.copyWith(isLoading: false, error: loadResult.message);
          return;
        }
      }

      // Initial load: Wait for local cache to populate if it's currently empty.
      Chats? result;
      for (int i = 0; i < 6; i++) {
        final res = await send(const GetChats(
          chatList: null,
          limit: _initialPageSize,
        ));
        if (res is Chats && res.chatIds.isNotEmpty) {
          result = res;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }

      if (result == null) {
        final res = await send(const GetChats(chatList: null, limit: _initialPageSize));
        if (res is Chats) {
          result = res;
        }
      }

      if (result == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      _fetchedSoFar = result.chatIds.length;

      await _streamChatDetails(send, result.chatIds, replace: true);

      // Only rely on LoadChats 404 error to stop pagination because local GetChats cache
      // might temporarily return fewer items than the server has actually sent.
      state = state.copyWith(
        isLoading: false,
        hasMore: hasMoreChats,
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

      final loadResult = await send(const LoadChats(
        chatList: null,
        limit: _pageSize,
      ));

      bool hasMoreChats = true;
      if (loadResult is TdError) {
        if (loadResult.code == 404) {
          hasMoreChats = false;
        } else {
          state = state.copyWith(isLoading: false);
          return;
        }
      }

      final totalWanted = _fetchedSoFar + _pageSize;
      
      // Pagination: Wait briefly for cache to update
      Chats? result;
      for (int i = 0; i < 4; i++) {
        final res = await send(GetChats(
          chatList: null,
          limit: totalWanted,
        ));
        if (res is Chats && res.chatIds.length > _fetchedSoFar) {
          result = res;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (result == null) {
        final res = await send(GetChats(chatList: null, limit: totalWanted));
        if (res is Chats) result = res;
      }

      if (result == null) {
        state = state.copyWith(isLoading: false, hasMore: false);
        return;
      }

      // Only process IDs that are new (not already shown).
      final existingIds = state.chats.map((c) => c.id).toSet();
      final newIds =
          result.chatIds.where((id) => !existingIds.contains(id)).toList();

      if (newIds.isEmpty) {
         // Either duplicate chats or truly no new chats fetched.
         // If we didn't fetch any new ones despite trying, we are likely at the end.
         state = state.copyWith(isLoading: false, hasMore: false);
         return;
      }

      _fetchedSoFar = result.chatIds.length;

      await _streamChatDetails(send, newIds, replace: false);

      state = state.copyWith(
        isLoading: false,
        hasMore: hasMoreChats,
      );
    } catch (e) {
      Log.error('Failed to load more chats', error: e, tag: 'CHAT_LIST');
      state = state.copyWith(isLoading: false);
    }
  }

  // ── Search & Filter ─────────────────────────────────────────────

  void toggleMediaOnly() {
    state = state.copyWith(mediaOnly: !state.mediaOnly);
  }

  Future<void> searchChats(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    state = state.copyWith(
      isSearchMode: true,
      searchQuery: trimmed,
      searchResults: [],
      isSearching: true,
      error: '',
    );

    try {
      final send = _ref.read(tdlibSendProvider);

      final result = await send(SearchChats(
        query: trimmed,
        limit: 50,
      ));

      if (result is Chats) {
        await _streamChatDetails(send, result.chatIds, replace: true, isSearch: true);
        state = state.copyWith(isSearching: false);
      } else if (result is TdError) {
        state = state.copyWith(isSearching: false, error: result.message);
      }
    } catch (e) {
      Log.error('Failed to search chats', error: e, tag: 'CHAT_LIST');
      state = state.copyWith(isSearching: false, error: e.toString());
    }
  }

  void clearSearch() {
    state = state.copyWith(
      isSearchMode: false,
      searchQuery: '',
      searchResults: [],
      isSearching: false,
    );
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
    bool isSearch = false,
  }) async {
    if (replace) {
      // Kick off the initial empty list so the skeleton disappears quickly.
      if (isSearch) {
        state = state.copyWith(searchResults: []);
      } else {
        state = state.copyWith(chats: []);
      }
    }

    // Fire all requests concurrently but add each result to state
    // as soon as it resolves, rather than collecting all and bulk-inserting.
    final futures = chatIds.map((id) async {
      final item = await _fetchChatDetail(send, id);
      if (item == null || !mounted) return;

      if (isSearch) {
        state = state.copyWith(searchResults: [...state.searchResults, item]);
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
    
    bool isForum = false;

    // Only fetch supergroup info for supergroups, with a timeout
    // to prevent blocking if TDLib is congested.
    if (detail.type is ChatTypeSupergroup) {
      try {
        final sgResult = await send(GetSupergroup(
          supergroupId: (detail.type as ChatTypeSupergroup).supergroupId,
        )).timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (sgResult is Supergroup) {
          isForum = sgResult.isForum;
        }
      } catch (_) {
        // Non-critical — default isForum=false is safe.
      }
    }

    // Skip the expensive SearchChatMessages probe here. It was causing
    // TDLib request congestion that prevented private/basic chats from
    // ever resolving. Default hasMedia=true; the mediaOnly toggle still
    // works but assumes all chats might have media.
    const hasMedia = true;

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
      isForum: isForum,
      hasMedia: hasMedia,
    );
  }
}
