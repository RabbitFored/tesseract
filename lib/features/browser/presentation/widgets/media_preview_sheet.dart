
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:video_player/video_player.dart';

import '../../../../core/tdlib/tdlib_client.dart';
import '../../../../core/tdlib/tdlib_provider.dart';
import '../../../../core/utils/logger.dart';
import '../../../dashboard/presentation/utils/display_helpers.dart';
import '../../../downloader/data/download_manager.dart';
import '../../../downloader/domain/download_item.dart';
import '../../domain/media_message.dart';

// ─────────────────────────────────────────────────────────────────
// Format detection
// ─────────────────────────────────────────────────────────────────

enum _Kind { image, video, audio, pdf, text, other }

_Kind _kindOf(String name) {
  final ext = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' ||
    'tiff' || 'tif' || 'ico' || 'heic' || 'heif' || 'avif' =>
      _Kind.image,
    'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' || 'm4v' ||
    'wmv' || 'ts' || 'mpg' || 'mpeg' || '3gp' || 'ogv' || 'rmvb' =>
      _Kind.video,
    'mp3' || 'aac' || 'ogg' || 'wav' || 'flac' || 'm4a' || 'opus' ||
    'wma' || 'aiff' || 'alac' || 'oga' || 'amr' =>
      _Kind.audio,
    'pdf' => _Kind.pdf,
    'txt' || 'md' || 'log' || 'csv' || 'json' || 'xml' || 'yaml' ||
    'yml' || 'toml' || 'ini' || 'cfg' || 'conf' || 'sh' || 'bat' ||
    'dart' || 'py' || 'js' || 'ts' || 'html' || 'css' || 'sql' ||
    'kt' || 'java' || 'swift' || 'c' || 'cpp' || 'h' =>
      _Kind.text,
    // Archives and all other formats: show metadata + download button.
    // ZIP central directory is at the file end — requires full download
    // to list contents, which defeats the purpose of preview.
    _ => _Kind.other,
  };
}

// Minimum bytes needed before we can open the player.
int _minBytesFor(_Kind kind) => switch (kind) {
      _Kind.video => 1 * 1024 * 1024,  // 1 MB — moov atom
      _Kind.audio => 64 * 1024,         // 64 KB — audio header
      _Kind.image => 256 * 1024,        // 256 KB — visible partial render
      _ => 0,
    };

// ─────────────────────────────────────────────────────────────────
// Sheet widget
// ─────────────────────────────────────────────────────────────────

class MediaPreviewSheet extends ConsumerStatefulWidget {
  const MediaPreviewSheet({super.key, required this.media});
  final MediaMessage media;

  @override
  ConsumerState<MediaPreviewSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<MediaPreviewSheet> {
  late final _Kind _kind;

  // Download tracking
  String? _cachePath;       // TDLib local cache path (may be partial)
  int _downloadedBytes = 0;
  bool _downloadComplete = false;
  StreamSubscription<td.TdObject>? _updateSub;

  // Player state
  bool _playerReady = false;
  String? _error;

  // Video
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;

  // Audio
  AudioPlayer? _audioPlayer;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _audioPlaying = false;

  // Image — bytes for progressive render
  Uint8List? _imageBytes;

  // Text
  String? _textContent;

  @override
  void initState() {
    super.initState();
    _kind = _kindOf(widget.media.fileName);
    _begin();
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  // ── Entry point ─────────────────────────────────────────────────

  Future<void> _begin() async {
    switch (_kind) {
      case _Kind.other:
        // No download needed — show metadata immediately.
        if (mounted) setState(() => _playerReady = true);
      default:
        // Start background download; open player as soon as enough bytes buffered.
        await _startBackgroundDownload();
    }
  }

  // ── Background download + partial open ─────────────────────────

  Future<void> _startBackgroundDownload() async {
    try {
      final send = ref.read(tdlibSendProvider);
      final client = ref.read(tdlibClientProvider);
      final minBytes = _minBytesFor(_kind);

      // Subscribe to UpdateFile for live progress + partial open trigger.
      _updateSub = client.updates.listen((e) async {
        if (e is! td.UpdateFile) return;
        if (e.file.id != widget.media.fileId) return;
        if (!mounted) return;

        final local = e.file.local;
        final downloaded = local.downloadedSize;

        setState(() => _downloadedBytes = downloaded);

        // Capture path as soon as TDLib gives us one.
        if (_cachePath == null && local.path.isNotEmpty) {
          _cachePath = local.path;
        }

        // Mark complete.
        if (local.isDownloadingCompleted && !_downloadComplete) {
          _downloadComplete = true;
          _cachePath = local.path;
        }

        // Open player once we have enough bytes.
        if (!_playerReady && _cachePath != null && downloaded >= minBytes) {
          await _openPlayer(_cachePath!);
        }

        // Progressive image update.
        if (_kind == _Kind.image && _cachePath != null && downloaded > 0) {
          _refreshImage(_cachePath!);
        }
      });

      // Start async download — TDLib writes to cache file immediately.
      // limit=0 means full file; synchronous=false returns immediately.
      final startResult = await send(td.DownloadFile(
        fileId: widget.media.fileId,
        priority: 32,
        offset: 0,
        limit: 0,
        synchronous: false,
      ));

      // If already cached (completed), handle immediately.
      if (startResult is td.File) {
        final local = startResult.local;
        if (local.path.isNotEmpty) _cachePath = local.path;
        _downloadedBytes = local.downloadedSize;

        if (local.isDownloadingCompleted) {
          _downloadComplete = true;
          await _updateSub?.cancel();
          _updateSub = null;
          if (_cachePath != null && !_playerReady) {
            await _openPlayer(_cachePath!);
          }
        } else if (_cachePath != null && local.downloadedSize >= minBytes && !_playerReady) {
          await _openPlayer(_cachePath!);
        }
      }
    } catch (e) {
      Log.error('Preview start failed: $e', tag: 'PREVIEW');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ── Player setup ────────────────────────────────────────────────

  Future<void> _openPlayer(String path) async {
    if (_playerReady || !mounted) return;

    switch (_kind) {
      case _Kind.image:
        await _refreshImage(path);
        if (mounted) setState(() => _playerReady = true);

      case _Kind.video:
        _videoCtrl = VideoPlayerController.file(io.File(path));
        try {
          await _videoCtrl!.initialize();
        } catch (e) {
          // Not enough data yet — wait for more bytes.
          Log.info('Video init failed (partial): $e — waiting', tag: 'PREVIEW');
          _videoCtrl?.dispose();
          _videoCtrl = null;
          return;
        }
        if (!mounted) return;
        _chewieCtrl = ChewieController(
          videoPlayerController: _videoCtrl!,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          aspectRatio: _videoCtrl!.value.aspectRatio,
        );
        setState(() => _playerReady = true);

      case _Kind.audio:
        _audioPlayer = AudioPlayer();
        _audioPlayer!.onDurationChanged.listen((d) {
          if (mounted) setState(() => _audioDuration = d);
        });
        _audioPlayer!.onPositionChanged.listen((p) {
          if (mounted) setState(() => _audioPosition = p);
        });
        _audioPlayer!.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _audioPlaying = s == PlayerState.playing);
        });
        _audioPlayer!.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _audioPosition = Duration.zero);
        });
        try {
          await _audioPlayer!.setSourceDeviceFile(path);
        } catch (e) {
          Log.info('Audio init failed (partial): $e — waiting', tag: 'PREVIEW');
          _audioPlayer?.dispose();
          _audioPlayer = null;
          return;
        }
        if (mounted) setState(() => _playerReady = true);

      case _Kind.pdf:
        if (mounted) setState(() => _playerReady = true);

      case _Kind.text:
        try {
          final bytes = await io.File(path).openRead(0, 100 * 1024).toList();
          _textContent = String.fromCharCodes(bytes.expand((b) => b));
        } catch (e) {
          _textContent = 'Could not read: $e';
        }
        if (mounted) setState(() => _playerReady = true);

      default:
        if (mounted) setState(() => _playerReady = true);
    }
  }

  Future<void> _refreshImage(String path) async {
    try {
      final bytes = await io.File(path).readAsBytes();
      if (mounted) setState(() => _imageBytes = bytes);
    } catch (_) {}
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.media;
    final totalSize = m.fileSize;
    final progress = totalSize > 0
        ? (_downloadedBytes / totalSize).clamp(0.0, 1.0)
        : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sanitizeText(m.fileName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          // Only show download progress for kinds that download.
                          (_kind != _Kind.other && !_downloadComplete && _downloadedBytes > 0)
                              ? '${formatBytes(_downloadedBytes)} / ${formatBytes(totalSize)}'
                                  ' · ${(progress * 100).round()}%'
                                  '${_playerReady ? "" : " · Buffering..."}'
                              : '${m.typeLabel} · ${formatBytes(totalSize)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Download progress bar — only for downloading kinds.
            if (_kind != _Kind.other && !_downloadComplete)
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2AABEE)),
              )
            else
              const SizedBox(height: 2),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme, scrollCtrl)),
            _ActionBar(
              media: m,
              localPath: _cachePath,
              onDownload: () => _enqueue(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ScrollController scrollCtrl) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: Color(0xFFFF1744)),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () { setState(() { _error = null; _playerReady = false; }); _begin(); },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Show image progressively even before player is "ready".
    if (_kind == _Kind.image && _imageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5, maxScale: 8.0,
        child: Center(
          child: Image.memory(_imageBytes!, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded, size: 64, color: Color(0xFF78909C))),
        ),
      );
    }

    if (!_playerReady) {
      // Buffering indicator with progress.
      final progress = widget.media.fileSize > 0
          ? (_downloadedBytes / widget.media.fileSize).clamp(0.0, 1.0)
          : 0.0;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64, height: 64,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 3,
                  ),
                ),
                if (progress > 0)
                  Text('${(progress * 100).round()}%',
                      style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _kind == _Kind.video
                  ? 'Buffering ${formatBytes(_downloadedBytes)}...'
                  : 'Loading...',
              style: theme.textTheme.bodyMedium,
            ),
            if (_kind == _Kind.video) ...[
              const SizedBox(height: 8),
              Text(
                'Playback starts automatically once enough data is buffered',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return switch (_kind) {
      _Kind.video => _chewieCtrl != null
          ? Chewie(controller: _chewieCtrl!)
          : const Center(child: CircularProgressIndicator()),
      _Kind.audio => _AudioWidget(
          player: _audioPlayer!,
          duration: _audioDuration,
          position: _audioPosition,
          isPlaying: _audioPlaying,
          fileName: widget.media.fileName,
        ),
      _Kind.pdf => SfPdfViewer.file(io.File(_cachePath!)),
      _Kind.text => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _textContent ?? '',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12, height: 1.5),
          ),
        ),
      _ => _MetadataView(media: widget.media, scrollCtrl: scrollCtrl),
    };
  }

  Future<void> _enqueue(BuildContext context) async {
    final manager = ref.read(downloadManagerProvider);
    final appDir = await getApplicationDocumentsDirectory();
    final m = widget.media;
    await manager.enqueue(DownloadItem(
      fileId: m.fileId,
      localPath: '${appDir.path}/downloads/${m.fileName}',
      totalSize: m.fileSize,
      fileName: m.fileName,
      chatId: m.chatId,
      messageId: m.messageId,
    ));
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added "${sanitizeText(m.fileName)}" to queue'),
        backgroundColor: const Color(0xFF2AABEE),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _AudioWidget extends StatelessWidget {
  const _AudioWidget({
    required this.player, required this.duration, required this.position,
    required this.isPlaying, required this.fileName,
  });
  final AudioPlayer player;
  final Duration duration, position;
  final bool isPlaying;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prog = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.audiotrack_rounded,
                size: 48, color: Color(0xFF2AABEE)),
          ),
          const SizedBox(height: 24),
          Text(sanitizeText(fileName), maxLines: 2, textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: prog,
              activeColor: const Color(0xFF2AABEE),
              onChanged: (v) => player.seek(
                  Duration(milliseconds: (v * duration.inMilliseconds).round())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position), style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(_fmt(duration), style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32, icon: const Icon(Icons.replay_10_rounded),
                onPressed: () {
                  final t = position - const Duration(seconds: 10);
                  player.seek(t < Duration.zero ? Duration.zero : t);
                },
              ),
              const SizedBox(width: 8),
              Container(
                width: 56, height: 56,
                decoration: const BoxDecoration(
                    color: Color(0xFF2AABEE), shape: BoxShape.circle),
                child: IconButton(
                  iconSize: 28, color: Colors.white,
                  icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: () => isPlaying ? player.pause() : player.resume(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 32, icon: const Icon(Icons.forward_10_rounded),
                onPressed: () {
                  final t = position + const Duration(seconds: 10);
                  player.seek(t > duration ? duration : t);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.media, required this.scrollCtrl});
  final MediaMessage media;
  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(FileTypeIcon.iconFor(media.fileName), size: 40,
                color: FileTypeIcon.colorFor(media.fileName)),
          ),
        ),
        const SizedBox(height: 20),
        _row('Name', sanitizeText(media.fileName), theme),
        _row('Type', media.typeLabel, theme),
        _row('Size', formatBytes(media.fileSize), theme),
        if (media.mimeType.isNotEmpty) _row('MIME', media.mimeType, theme),
        if (media.caption.isNotEmpty)
          _row('Caption', sanitizeText(media.caption), theme),
        if (media.date > 0)
          _row('Date',
              DateTime.fromMillisecondsSinceEpoch(media.date * 1000)
                  .toLocal().toString().substring(0, 16),
              theme),
      ],
    );
  }

  static Widget _row(String label, String value, ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label, style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(value, style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.media, required this.localPath, required this.onDownload,
  });
  final MediaMessage media;
  final String? localPath;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Save to device'),
              ),
            ),
            if (localPath != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => OpenFilex.open(localPath!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                icon: const Icon(Icons.share_rounded, size: 18),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                      files: [XFile(localPath!)], text: media.fileName),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
