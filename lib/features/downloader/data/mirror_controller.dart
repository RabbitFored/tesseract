import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_client.dart';
import '../../../core/utils/logger.dart';
import '../../browser/domain/media_message.dart';
import '../../settings/data/settings_controller.dart';
import '../../settings/domain/settings_state.dart';
import '../domain/download_item.dart';
import 'download_manager.dart';

/// Listens to TDLib [UpdateNewMessage] events and automatically enqueues
/// downloads for channels that have an active [MirrorRule].
///
/// Lifecycle: created and started by [DownloadManager.initialize()].
class MirrorController {
  MirrorController(this._ref);

  final Ref _ref;
  StreamSubscription<TdObject>? _sub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

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
    if (rule.minFileSizeBytes > 0 && media.fileSize < rule.minFileSizeBytes) {
      return;
    }
    if (rule.maxFileSizeBytes > 0 && media.fileSize > rule.maxFileSizeBytes) {
      return;
    }

    final localPath = '${rule.localFolder}/${media.fileName}';

    Log.info(
      'Mirror: enqueuing ${media.fileName} from channel ${rule.channelTitle}',
      tag: 'MIRROR',
    );

    final manager = _ref.read(downloadManagerProvider);
    await manager.enqueue(DownloadItem(
      fileId: media.fileId,
      localPath: localPath,
      totalSize: media.fileSize,
      fileName: media.fileName,
      chatId: media.chatId,
      messageId: media.messageId,
      mirrorChannelId: rule.channelId,
      priority: -1, // lower priority than manual downloads
    ));
  }

  String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
