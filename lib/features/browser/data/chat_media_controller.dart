import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/media_message.dart';

/// State for media messages in a specific chat.
/// Supports both default history browsing and search mode.
class ChatMediaState {
  const ChatMediaState({
    this.media = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error = '',
    this.chatId = 0,
    this.isSearchMode = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.searchHasMore = true,
  });

  /// Default history media (preserved while searching).
  final List<MediaMessage> media;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String error;
  final int chatId;

  /// Search mode state.
  final bool isSearchMode;
  final String searchQuery;
  final List<MediaMessage> searchResults;
  final bool isSearching;
  final bool searchHasMore;

  /// Active display list: search results when searching, history otherwise.
  List<MediaMessage> get displayMedia =>
      isSearchMode ? searchResults : media;

  ChatMediaState copyWith({
    List<MediaMessage>? media,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? chatId,
    bool? isSearchMode,
    String? searchQuery,
    List<MediaMessage>? searchResults,
    bool? isSearching,
    bool? searchHasMore,
  }) =>
      ChatMediaState(
        media: media ?? this.media,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: error ?? this.error,
        chatId: chatId ?? this.chatId,
        isSearchMode: isSearchMode ?? this.isSearchMode,
        searchQuery: searchQuery ?? this.searchQuery,
        searchResults: searchResults ?? this.searchResults,
        isSearching: isSearching ?? this.isSearching,
        searchHasMore: searchHasMore ?? this.searchHasMore,
      );
}

/// Family provider: one controller per chatId.
final chatMediaControllerProvider = StateNotifierProvider.family<
    ChatMediaController, ChatMediaState, int>(
  (ref, chatId) => ChatMediaController(ref, chatId),
);

/// Fetches message history for a selected chat, filters to only
/// messages containing downloadable media (document, video, audio, photo).
///
/// Supports two modes:
///   - **Default Mode**: Infinite-scroll history via `GetChatHistory`
///   - **Search Mode**: Query-based results via `SearchChatMessages`
///
/// Clearing the search reverts instantly to the cached history state.
class ChatMediaController extends StateNotifier<ChatMediaState> {
  ChatMediaController(this._ref, this._chatId)
      : super(ChatMediaState(chatId: _chatId));

  final Ref _ref;
  final int _chatId;
  static const int _pageSize = 50;

  // ── History pagination state ─────────────────────────────────
  int _oldestMessageId = 0;

  // ── Search pagination state ──────────────────────────────────
  int _searchOldestMessageId = 0;

  // ══════════════════════════════════════════════════════════════
  //  DEFAULT MODE — History browsing
  // ══════════════════════════════════════════════════════════════

  /// Load the initial batch of media messages.
  Future<void> loadMedia() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: '');
    _oldestMessageId = 0;

    try {
      final messages = await _fetchAndFilter(fromMessageId: 0);
      state = state.copyWith(
        media: messages,
        isLoading: false,
        hasMore: messages.length >= 1,
      );
    } catch (e) {
      Log.error('Failed to load media', error: e, tag: 'CHAT_MEDIA');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load more (older) media messages for infinite scroll.
  Future<void> loadMore() async {
    // In search mode, delegate to search pagination.
    if (state.isSearchMode) {
      return loadMoreSearch();
    }

    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final messages = await _fetchAndFilter(fromMessageId: _oldestMessageId);

      if (messages.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }

      final existingIds = state.media.map((m) => m.messageId).toSet();
      final newMedia =
          messages.where((m) => !existingIds.contains(m.messageId)).toList();

      state = state.copyWith(
        media: [...state.media, ...newMedia],
        isLoadingMore: false,
        hasMore: newMedia.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  SEARCH MODE — TDLib searchChatMessages
  // ══════════════════════════════════════════════════════════════

  /// Execute a search query. Filters results to media-only.
  Future<void> searchMedia(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }

    _searchOldestMessageId = 0;
    state = state.copyWith(
      isSearchMode: true,
      searchQuery: trimmed,
      searchResults: [],
      isSearching: true,
      searchHasMore: true,
    );

    try {
      final results = await _searchAndFilter(
        query: trimmed,
        fromMessageId: 0,
      );

      state = state.copyWith(
        searchResults: results,
        isSearching: false,
        searchHasMore: results.isNotEmpty,
      );
    } catch (e) {
      Log.error('Search failed', error: e, tag: 'CHAT_MEDIA');
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
      );
    }
  }

  /// Load more search results (pagination).
  Future<void> loadMoreSearch() async {
    if (!state.isSearchMode || state.isSearching || !state.searchHasMore) {
      return;
    }

    state = state.copyWith(isSearching: true);

    try {
      final results = await _searchAndFilter(
        query: state.searchQuery,
        fromMessageId: _searchOldestMessageId,
      );

      if (results.isEmpty) {
        state = state.copyWith(isSearching: false, searchHasMore: false);
        return;
      }

      final existingIds =
          state.searchResults.map((m) => m.messageId).toSet();
      final newResults =
          results.where((m) => !existingIds.contains(m.messageId)).toList();

      state = state.copyWith(
        searchResults: [...state.searchResults, ...newResults],
        isSearching: false,
        searchHasMore: newResults.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Clear search and revert to cached history instantly.
  void clearSearch() {
    state = state.copyWith(
      isSearchMode: false,
      searchQuery: '',
      searchResults: [],
      isSearching: false,
      searchHasMore: true,
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  PRIVATE — Fetch helpers
  // ══════════════════════════════════════════════════════════════

  /// Fetch history batches and filter for media.
  Future<List<MediaMessage>> _fetchAndFilter({
    required int fromMessageId,
    int batchFetchCount = 5,
  }) async {
    final send = _ref.read(tdlibSendProvider);
    final collected = <MediaMessage>[];

    int currentFromId = fromMessageId;

    for (int batch = 0; batch < batchFetchCount; batch++) {
      final result = await send(GetChatHistory(
        chatId: _chatId,
        fromMessageId: currentFromId,
        offset: 0,
        limit: _pageSize,
        onlyLocal: false,
      ));

      if (result is! Messages) break;

      final msgs = result.messages;
      if (msgs.isEmpty) break;

      for (final msg in msgs) {
        final media = MediaMessage.fromTdlibMessage(msg);
        if (media != null) collected.add(media);
      }

      _oldestMessageId = msgs.last.id;
      currentFromId = _oldestMessageId;

      if (msgs.length < _pageSize) break;
      if (collected.length >= _pageSize) break;
    }

    return collected;
  }

  /// Search messages and filter for media.
  Future<List<MediaMessage>> _searchAndFilter({
    required String query,
    required int fromMessageId,
    int batchFetchCount = 3,
  }) async {
    final send = _ref.read(tdlibSendProvider);
    final collected = <MediaMessage>[];

    int currentFromId = fromMessageId;

    for (int batch = 0; batch < batchFetchCount; batch++) {
      final result = await send(SearchChatMessages(
        chatId: _chatId,
        query: query,
        senderId: null,
        fromMessageId: currentFromId,
        offset: 0,
        limit: _pageSize,
        filter: null, // No TDLib filter — we apply our own media filter.
        messageThreadId: 0,
      ));

      if (result is! FoundChatMessages) break;

      final msgs = result.messages;
      if (msgs.isEmpty) break;

      for (final msg in msgs) {
        final media = MediaMessage.fromTdlibMessage(msg);
        if (media != null) collected.add(media);
      }

      _searchOldestMessageId = msgs.last.id;
      currentFromId = _searchOldestMessageId;

      if (msgs.length < _pageSize) break;
      if (collected.length >= _pageSize) break;
    }

    return collected;
  }
}
