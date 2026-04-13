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

/// Maps our MediaType enum to TDLib's SearchMessagesFilter.
/// Using TDLib filters means the server returns only the relevant type —
/// no wasted bandwidth fetching text messages we discard.
SearchMessagesFilter? _tdlibFilterFor(MediaType? type) => switch (type) {
      MediaType.video => const SearchMessagesFilterVideo(),
      MediaType.audio => const SearchMessagesFilterAudio(),
      MediaType.photo => const SearchMessagesFilterPhoto(),
      MediaType.document => const SearchMessagesFilterDocument(),
      MediaType.voiceNote => const SearchMessagesFilterVoiceNote(),
      MediaType.videoNote => const SearchMessagesFilterVideoNote(),
      MediaType.animation => const SearchMessagesFilterAnimation(),
      null => null, // null = all types, handled by GetChatHistory
    };

/// State for media messages in a specific chat.
class ChatMediaState {
  const ChatMediaState({
    this.media = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error = '',
    this.chatId = 0,
    this.activeFilter,
    this.isSearchMode = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isSearching = false,
    this.searchHasMore = true,
  });

  final List<MediaMessage> media;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String error;
  final int chatId;

  /// Active type filter — when set, only this type is fetched from TDLib.
  final MediaType? activeFilter;

  final bool isSearchMode;
  final String searchQuery;
  final List<MediaMessage> searchResults;
  final bool isSearching;
  final bool searchHasMore;

  List<MediaMessage> get displayMedia =>
      isSearchMode ? searchResults : media;

  ChatMediaState copyWith({
    List<MediaMessage>? media,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? chatId,
    Object? activeFilter = _sentinel,
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
        activeFilter: activeFilter == _sentinel
            ? this.activeFilter
            : activeFilter as MediaType?,
        isSearchMode: isSearchMode ?? this.isSearchMode,
        searchQuery: searchQuery ?? this.searchQuery,
        searchResults: searchResults ?? this.searchResults,
        isSearching: isSearching ?? this.isSearching,
        searchHasMore: searchHasMore ?? this.searchHasMore,
      );
}

// Sentinel for nullable copyWith fields.
const _sentinel = Object();

/// Family provider: one controller per config.
final chatMediaControllerProvider = StateNotifierProvider.family.autoDispose<
    ChatMediaController, ChatMediaState, ChatMediaConfig>(
  (ref, config) => ChatMediaController(ref, config),
);

/// Fetches media messages for a chat using TDLib's native type filters.
///
/// Key improvements over the previous implementation:
/// - Uses `SearchMessagesFilter` so TDLib returns only the requested type
///   (no wasted fetches of text messages that get discarded locally)
/// - Filter changes trigger a fresh fetch from the server, not just local
///   filtering of an already-loaded subset
/// - Search uses the same filter so results are type-consistent
class ChatMediaController extends StateNotifier<ChatMediaState> {
  ChatMediaController(this._ref, this._config)
      : super(ChatMediaState(chatId: _config.chatId));

  final Ref _ref;
  final ChatMediaConfig _config;
  int get _chatId => _config.chatId;
  int get _messageThreadId => _config.messageThreadId;
  static const int _pageSize = 50;

  int _oldestMessageId = 0;
  int _searchOldestMessageId = 0;
  bool _hasMoreAfterFetch = true;

  // ── Public API ───────────────────────────────────────────────

  Future<void> reload() async {
    if (!mounted) return;
    _oldestMessageId = 0;
    state = state.copyWith(isLoading: false, error: '');
    await loadMedia();
  }

  Future<void> loadMedia() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: '');
    _oldestMessageId = 0;

    try {
      final messages = await _fetchPage(fromMessageId: 0);
      if (!mounted) return;
      state = state.copyWith(
        media: messages,
        isLoading: false,
        hasMore: true,
      );
      // Auto-load next page if first batch was sparse (cache warmup).
      if (messages.length < 3 && mounted) {
        await loadMore();
      }
    } catch (e) {
      Log.error('Failed to load media', error: e, tag: 'CHAT_MEDIA');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isSearchMode) return loadMoreSearch();
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final messages = await _fetchPage(fromMessageId: _oldestMessageId);
      if (!mounted) return;
      final existingIds = state.media.map((m) => m.messageId).toSet();
      final fresh =
          messages.where((m) => !existingIds.contains(m.messageId)).toList();

      state = state.copyWith(
        media: [...state.media, ...fresh],
        isLoadingMore: false,
        hasMore: _hasMoreAfterFetch,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Switch the active type filter and reload from scratch.
  Future<void> setFilter(MediaType? type) async {
    if (state.activeFilter == type) return;
    if (!mounted) return;
    state = state.copyWith(
      activeFilter: type,
      media: [],
      hasMore: true,
      error: '',
    );
    _oldestMessageId = 0;
    if (!mounted) return;
    await loadMedia();
  }

  // ── Search ───────────────────────────────────────────────────

  Future<void> searchMedia(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) { clearSearch(); return; }

    _searchOldestMessageId = 0;
    state = state.copyWith(
      isSearchMode: true,
      searchQuery: trimmed,
      searchResults: [],
      isSearching: true,
      searchHasMore: true,
    );

    try {
      final results = await _searchPage(query: trimmed, fromMessageId: 0);
      if (!mounted) return;
      state = state.copyWith(
        searchResults: results,
        isSearching: false,
        searchHasMore: results.isNotEmpty,
      );
    } catch (e) {
      Log.error('Search failed', error: e, tag: 'CHAT_MEDIA');
      if (!mounted) return;
      state = state.copyWith(isSearching: false, error: e.toString());
    }
  }

  Future<void> loadMoreSearch() async {
    if (!state.isSearchMode || state.isSearching || !state.searchHasMore) return;
    state = state.copyWith(isSearching: true);

    try {
      final results = await _searchPage(
        query: state.searchQuery,
        fromMessageId: _searchOldestMessageId,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        state = state.copyWith(isSearching: false, searchHasMore: false);
        return;
      }
      final existingIds = state.searchResults.map((m) => m.messageId).toSet();
      final fresh =
          results.where((m) => !existingIds.contains(m.messageId)).toList();
      state = state.copyWith(
        searchResults: [...state.searchResults, ...fresh],
        isSearching: false,
        searchHasMore: fresh.isNotEmpty,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isSearching: false);
    }
  }

  void clearSearch() {
    state = state.copyWith(
      isSearchMode: false,
      searchQuery: '',
      searchResults: [],
      isSearching: false,
      searchHasMore: true,
    );
  }

  // ── Private fetch helpers ────────────────────────────────────

  /// Fetch one page of media using TDLib's native filter.
  ///
  /// When [activeFilter] is set, uses `SearchChatMessages` with the
  /// corresponding `SearchMessagesFilter` — the server returns only that
  /// type, so we never waste bandwidth fetching text messages.
  ///
  /// When no filter is set, uses `GetChatHistory` and discards non-media.
  Future<List<MediaMessage>> _fetchPage({required int fromMessageId}) async {
    final send = _ref.read(tdlibSendProvider);
    final filter = state.activeFilter;
    final tdFilter = _tdlibFilterFor(filter);
    final collected = <MediaMessage>[];

    // With a TDLib filter, one SearchChatMessages call returns only the
    // relevant type — no need to loop through batches of text messages.
    if (tdFilter != null || _messageThreadId != 0) {
      // Use SearchChatMessages for filtered or threaded fetches.
      final result = await send(SearchChatMessages(
        chatId: _chatId,
        query: '',
        senderId: null,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: _pageSize,
        filter: tdFilter,
        messageThreadId: _messageThreadId,
      ));

      if (result is FoundChatMessages) {
        for (final msg in result.messages) {
          final media = MediaMessage.fromTdlibMessage(msg);
          if (media != null) collected.add(media);
        }
        if (result.messages.isNotEmpty) {
          _oldestMessageId = result.messages.last.id;
        }
        _hasMoreAfterFetch = result.messages.length >= _pageSize;
      } else {
        _hasMoreAfterFetch = false;
      }

      // Cache warmup retry for empty first-page results.
      if (collected.isEmpty && fromMessageId == 0) {
        await Future.delayed(const Duration(milliseconds: 1200));
        final retry = await send(SearchChatMessages(
          chatId: _chatId,
          query: '',
          senderId: null,
          fromMessageId: 0,
          offset: 0,
          limit: _pageSize,
          filter: tdFilter,
          messageThreadId: _messageThreadId,
        ));
        if (retry is FoundChatMessages) {
          for (final msg in retry.messages) {
            final media = MediaMessage.fromTdlibMessage(msg);
            if (media != null) collected.add(media);
          }
          if (retry.messages.isNotEmpty) {
            _oldestMessageId = retry.messages.last.id;
          }
          _hasMoreAfterFetch = retry.messages.length >= _pageSize;
        }
      }
      return collected;
    }

    // No filter — use GetChatHistory and filter locally.
    // Loop up to 20 batches to find enough media in text-heavy chats.
    int currentFromId = fromMessageId;
    bool exhausted = false;

    for (int batch = 0; batch < 20; batch++) {
      final result = await send(GetChatHistory(
        chatId: _chatId,
        fromMessageId: currentFromId,
        offset: 0,
        limit: _pageSize,
        onlyLocal: false,
      ));

      if (result is! Messages) { exhausted = true; break; }
      final msgs = result.messages;

      // Cache warmup retry.
      if (msgs.isEmpty && batch == 0 && currentFromId == 0) {
        await Future.delayed(const Duration(milliseconds: 900));
        final retry = await send(GetChatHistory(
          chatId: _chatId,
          fromMessageId: 0,
          offset: 0,
          limit: _pageSize,
          onlyLocal: false,
        ));
        if (retry is Messages && retry.messages.isNotEmpty) {
          for (final msg in retry.messages) {
            final media = MediaMessage.fromTdlibMessage(msg);
            if (media != null) collected.add(media);
          }
          _oldestMessageId = retry.messages.last.id;
          currentFromId = _oldestMessageId;
          if (retry.messages.length < _pageSize) { exhausted = true; break; }
          if (collected.length >= _pageSize) break;
          continue;
        }
        _hasMoreAfterFetch = true;
        return collected;
      }

      if (msgs.isEmpty) { exhausted = true; break; }

      for (final msg in msgs) {
        final media = MediaMessage.fromTdlibMessage(msg);
        if (media != null) collected.add(media);
      }
      _oldestMessageId = msgs.last.id;
      currentFromId = _oldestMessageId;

      if (msgs.length < _pageSize) { exhausted = true; break; }
      if (collected.length >= _pageSize) break;
    }

    _hasMoreAfterFetch = !exhausted;
    return collected;
  }

  /// Search with optional type filter.
  Future<List<MediaMessage>> _searchPage({
    required String query,
    required int fromMessageId,
  }) async {
    final send = _ref.read(tdlibSendProvider);
    final tdFilter = _tdlibFilterFor(state.activeFilter);
    final collected = <MediaMessage>[];

    // Fetch up to 3 batches to find enough media results.
    int currentFromId = fromMessageId;
    for (int batch = 0; batch < 3; batch++) {
      final result = await send(SearchChatMessages(
        chatId: _chatId,
        query: query,
        senderId: null,
        fromMessageId: currentFromId,
        offset: 0,
        limit: _pageSize,
        filter: tdFilter,
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
