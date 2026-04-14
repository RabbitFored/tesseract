import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_client.dart';
import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../../browser/domain/media_message.dart';
import '../../settings/data/settings_controller.dart';
import '../../settings/domain/settings_state.dart';
import '../domain/download_item.dart';

/// Listens to TDLib [UpdateNewMessage] events and automatically enqueues
/// downloads for channels that have an active [MirrorRule].
///
/// Lifecycle: created and started by [DownloadManager.initialize()].
///
/// IMPORTANT: [DownloadManager] is injected via [start()] rather than read
/// from the Riverpod ref, because MirrorController is owned by DownloadManager
/// (which IS downloadManagerProvider). Reading downloadManagerProvider from
/// inside a provider it belongs to causes a circular dependency assertion.
class MirrorController {
  MirrorController(this._ref);

  final Ref _ref;

  /// Set by [start()] — the owning DownloadManager, injected to avoid
  /// a circular provider dependency.
  late final EnqueuerCallback _enqueuer;

  StreamSubscription<TdObject>? _sub;
  bool _started = false;

  void start({required EnqueuerCallback enqueuer}) {
    if (_started) return;
    _started = true;
    _enqueuer = enqueuer;

    final client = _ref.read(tdlibClientProvider);
    _sub = client.updates.listen(_onUpdate);
    Log.info('MirrorController started', tag: 'MIRROR');
  }

  void dispose() {
    _sub?.cancel();
    _started = false;
  }

  void _onUpdate(TdObject event) {
    if (event is UpdateNewMessage) {
      _handleNewMessage(event.message);
    }
  }

  Future<void> _handleNewMessage(Message message) async {
    final settings = _ref.read(settingsControllerProvider);
    if (settings.mirrorRules.isEmpty) return;

    // Find a matching enabled rule for this chat.
    final rule = settings.mirrorRules.firstWhere(
      (r) => r.enabled && r.channelId == message.chatId,
      orElse: () => const MirrorRule(
        channelId: -1,
        channelTitle: '',
        localFolder: '',
      ),
    );
    if (rule.channelId == -1) return; // no matching rule

    final media = MediaMessage.fromTdlibMessage(message);
    if (media == null) return;

    // Apply extension filter.
    if (rule.filterExtensions.isNotEmpty) {
      final ext = _extension(media.fileName);
      if (!rule.filterExtensions.contains(ext)) {
        Log.info(
          'Mirror: skipping ${media.fileName} (ext=$ext not in filter)',
          tag: 'MIRROR',
        );
        return;
      }
    }

    // Apply size filters.
    if (rule.minFileSizeBytes > 0 && media.fileSize < rule.minFileSizeBytes) return;
    if (rule.maxFileSizeBytes > 0 && media.fileSize > rule.maxFileSizeBytes) return;

    final localPath = '${rule.localFolder}/${media.fileName}';
    Log.info(
      'Mirror: enqueuing ${media.fileName} from channel ${rule.channelTitle}',
      tag: 'MIRROR',
    );

    await _enqueuer(DownloadItem(
      fileId: media.fileId,
      localPath: localPath,
      totalSize: media.fileSize,
      fileName: media.fileName,
      chatId: media.chatId,
      messageId: media.messageId,
      mirrorChannelId: rule.channelId,
      priority: -1,
    ));
  }

  // ── Manual sync ──────────────────────────────────────────────

  /// Backfill historical messages for a single [rule].
  ///
  /// Walks backwards through the channel's message history (up to
  /// [maxMessages]) and enqueues any media that matches the rule's
  /// filters and hasn't already been downloaded.
  ///
  /// Returns the number of items newly enqueued.
  Future<int> syncRule(MirrorRule rule, {int maxMessages = 200}) async {
    if (!rule.enabled) return 0;

    final send = _ref.read(tdlibSendProvider);
    int enqueued = 0;
    int fromMessageId = 0; // 0 = start from the latest message

    Log.info(
      'Mirror sync: starting backfill for channel ${rule.channelTitle} '
      '(id=${rule.channelId}, max=$maxMessages)',
      tag: 'MIRROR',
    );

    int fetched = 0;
    while (fetched < maxMessages) {
      final batch = maxMessages - fetched;
      final limit = batch.clamp(1, 100); // TDLib max per call is 100

      final result = await send(GetChatHistory(
        chatId: rule.channelId,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
        onlyLocal: false,
      ));

      if (result is! Messages) break;
      final messages = result.messages;
      if (messages.isEmpty) break;

      for (final message in messages) {
        final media = MediaMessage.fromTdlibMessage(message);
        if (media == null) continue;

        if (rule.filterExtensions.isNotEmpty) {
          final ext = _extension(media.fileName);
          if (!rule.filterExtensions.contains(ext)) continue;
        }
        if (rule.minFileSizeBytes > 0 && media.fileSize < rule.minFileSizeBytes) continue;
        if (rule.maxFileSizeBytes > 0 && media.fileSize > rule.maxFileSizeBytes) continue;

        final localPath = '${rule.localFolder}/${media.fileName}';
        final added = await _enqueuer(DownloadItem(
          fileId: media.fileId,
          localPath: localPath,
          totalSize: media.fileSize,
          fileName: media.fileName,
          chatId: media.chatId,
          messageId: media.messageId,
          mirrorChannelId: rule.channelId,
          priority: -1,
        ));
        if (added) enqueued++;
      }

      fetched += messages.length;
      fromMessageId = messages.last.id;
      if (messages.length < limit) break; // end of history
    }

    Log.info(
      'Mirror sync: enqueued $enqueued new items from '
      '${rule.channelTitle} (scanned $fetched messages)',
      tag: 'MIRROR',
    );
    return enqueued;
  }

  /// Sync all enabled mirror rules. Returns total items enqueued.
  Future<int> syncAll({int maxMessagesPerChannel = 200}) async {
    final settings = _ref.read(settingsControllerProvider);
    final rules = settings.mirrorRules.where((r) => r.enabled).toList();
    int total = 0;
    for (final rule in rules) {
      total += await syncRule(rule, maxMessages: maxMessagesPerChannel);
    }
    return total;
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// Typedef for the enqueue callback injected from DownloadManager.
/// Using a typedef keeps MirrorController free of a direct import of
/// DownloadManager, breaking the circular dependency entirely.
typedef EnqueuerCallback = Future<bool> Function(DownloadItem item);
