import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/media_message.dart';

class ChatMediaConfig {
  const ChatMediaConfig(this.chatId, this.messageThreadId);
  final int chatId;
  final int messageThreadId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMediaConfig &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          messageThreadId == other.messageThreadId;

  @override
  int get hashCode => Object.hash(chatId, messageThreadId);
}

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

/// Family provider: one controller per config.
final chatMediaControllerProvider = StateNotifierProvider.family<
    ChatMediaController, ChatMediaState, ChatMediaConfig>(
  (ref, config) => ChatMediaController(ref, config),
);

/// Fetches message history for a selected chat, filters to only
/// messages containing downloadable media (document, video, audio, photo).
///
/// Supports two modes:
///   - **Default Mode**: Infinite-scroll history via `GetChatHistory`
///   - **Search Mode**: Query-based results via `SearchChatMessages`
///
/// Clearing the search reverts instantly to the cached history state.
///
/// ## TDLib Cache Warmup
/// On the first `GetChatHistory` call for a chat, TDLib may return an empty
/// list because the local cache isn't populated yet — the server fetch is
/// triggered in the background. The controller handles this by retrying once
/// after a short delay, and by always allowing `loadMore()` after initial load.
class ChatMediaController extends StateNotifier<ChatMediaState> {
  ChatMediaController(this._ref, this._config)
      : super(ChatMediaState(chatId: _config.chatId));

  final Ref _ref;
  final ChatMediaConfig _config;
  int get _chatId => _config.chatId;
  int get _messageThreadId => _config.messageThreadId;
  static const int _pageSize = 50;

  // ── History pagination state ─────────────────────────────────
  int _oldestMessageId = 0;

  // ── Search pagination state ──────────────────────────────────
  int _searchOldestMessageId = 0;

  // ══════════════════════════════════════════════════════════════
  //  DEFAULT MODE — History browsing
  // ══════════════════════════════════════════════════════════════

  /// Force-reload media (used by pull-to-refresh).
  Future<void> reload() async {
    state = state.copyWith(isLoading: false); // Reset guard
    _oldestMessageId = 0;
    await loadMedia();
  }

  /// Load the initial batch of media messages.
  ///
  /// Always sets [hasMore] = true after the first load so that
  /// [loadMore] can be triggered even for chats where TDLib's cache
  /// warmup caused the first page to be sparse.
  Future<void> loadMedia() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: '');
    _oldestMessageId = 0;

    try {
      final messages = await _fetchAndFilter(fromMessageId: 0);
      state = state.copyWith(
        media: messages,
        isLoading: false,
        // Always allow loadMore after first load — TDLib cache may have been
        // empty on the first call, so we cannot trust an empty result as "done".
        hasMore: true,
      );

      // If fewer than 3 media items were found, automatically try to load
      // the next page. This covers the common case where TDLib's cache
      // warmup returns nothing on the first call but has data immediately after.
      if (messages.length < 3 && mounted) {
        await loadMore();
      }
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
        // Only mark as done if we also know the batch was short
        // (i.e., TDLib returned fewer messages than requested).
        // The _fetchAndFilter method sets _exhausted to communicate this.
        state = state.copyWith(
          isLoadingMore: false,
          hasMore: _hasMoreAfterFetch,
        );
        return;
      }

      final existingIds = state.media.map((m) => m.messageId).toSet();
      final newMedia =
          messages.where((m) => !existingIds.contains(m.messageId)).toList();

      state = state.copyWith(
        media: [...state.media, ...newMedia],
        isLoadingMore: false,
        hasMore: _hasMoreAfterFetch,
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

  /// Tracks whether the last fetch hit the true end of history.
  /// True = there may be more messages; False = TDLib returned a short batch.
  bool _hasMoreAfterFetch = true;

  /// Fetch history batches and filter for media.
  ///
  /// Retries once with a short delay if TDLib returns an empty list on the
  /// first call, which happens when the local cache hasn't been warmed up yet.
  Future<List<MediaMessage>> _fetchAndFilter({
    required int fromMessageId,
    int batchFetchCount = 5,
  }) async {
    final send = _ref.read(tdlibSendProvider);
    final collected = <MediaMessage>[];

    int currentFromId = fromMessageId;
    bool definitivelyExhausted = false;

    for (int batch = 0; batch < batchFetchCount; batch++) {
      TdObject? result;
      if (_messageThreadId != 0) {
        result = await send(GetMessageThreadHistory(
          chatId: _chatId,
          messageId: _messageThreadId,
          fromMessageId: currentFromId,
          offset: 0,
          limit: _pageSize,
        ));
      } else {
        result = await send(GetChatHistory(
          chatId: _chatId,
          fromMessageId: currentFromId,
          offset: 0,
          limit: _pageSize,
          onlyLocal: false,
        ));
      }

      if (result is! Messages) break;

      final msgs = result.messages;

      // ── TDLib Cache Warmup Retry ─────────────────────────────
      // On the very first call (fromMessageId == 0), TDLib may return an
      // empty list because the server fetch is still in progress in the
      // background. Wait briefly and retry (more aggressively for topic threads).
      if (msgs.isEmpty && batch == 0 && currentFromId == 0) {
        final isThread = _messageThreadId != 0;
        final maxRetries = isThread ? 3 : 1;
        Log.info(
          '${isThread ? "GetMessageThreadHistory" : "GetChatHistory"} returned empty on first call — retrying ($maxRetries attempts)',
          tag: 'CHAT_MEDIA',
        );

        for (int retry = 0; retry < maxRetries; retry++) {
          await Future.delayed(Duration(milliseconds: 900 + (retry * 500)));

          TdObject? retryResult;
          if (isThread) {
            retryResult = await send(GetMessageThreadHistory(
              chatId: _chatId,
              messageId: _messageThreadId,
              fromMessageId: 0,
              offset: 0,
              limit: _pageSize,
            ));
          } else {
            retryResult = await send(GetChatHistory(
              chatId: _chatId,
              fromMessageId: 0,
              offset: 0,
              limit: _pageSize,
              onlyLocal: false,
            ));
          }

          if (retryResult is Messages && retryResult.messages.isNotEmpty) {
            // Use retry result.
            for (final msg in retryResult.messages) {
              final media = MediaMessage.fromTdlibMessage(msg);
              if (media != null) collected.add(media);
            }
            _oldestMessageId = retryResult.messages.last.id;
            currentFromId = _oldestMessageId;

            if (retryResult.messages.length < _pageSize) {
              definitivelyExhausted = true;
            }
            break; // Got data, stop retrying.
          }
        }

        if (collected.isEmpty) {
          // Genuinely empty — allow another attempt later from UI refresh.
          _hasMoreAfterFetch = true;
          return collected;
        }
        if (definitivelyExhausted) break;
        continue;
      }

      if (msgs.isEmpty) {
        definitivelyExhausted = true;
        break;
      }

      for (final msg in msgs) {
        final media = MediaMessage.fromTdlibMessage(msg);
        if (media != null) collected.add(media);
      }

      _oldestMessageId = msgs.last.id;
      currentFromId = _oldestMessageId;

      // A short batch means TDLib has no more history.
      if (msgs.length < _pageSize) {
        definitivelyExhausted = true;
        break;
      }

      // Stop fetching more batches once we have enough to display.
      if (collected.length >= _pageSize) break;
    }

    _hasMoreAfterFetch = !definitivelyExhausted;
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
        filter: null, // Search across all message types, then filter locally
        messageThreadId: _messageThreadId,
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
