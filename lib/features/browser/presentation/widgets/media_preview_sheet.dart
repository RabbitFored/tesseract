import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/tdlib/tdlib_client.dart';
import '../../../../core/tdlib/tdlib_provider.dart';
import '../../../../core/utils/logger.dart';
import '../../../dashboard/presentation/utils/display_helpers.dart';
import '../../../downloader/data/download_manager.dart';
import '../../../downloader/domain/download_item.dart';
import '../../domain/media_message.dart';
import 'package:tdlib/td_api.dart' as td;

/// Bottom-sheet media preview with streaming video support.
///
/// - Photos: full-screen zoomable image
/// - Videos/GIFs: streaming playback — starts playing as TDLib downloads
/// - Audio/Voice: player with seek, +/-10s
/// - Documents/Other: metadata card
///
/// Video streaming works by:
///   1. Calling DownloadFile(synchronous: false) to start the download
///   2. Polling UpdateFile events until TDLib has written enough bytes
///      to the local cache file for VideoPlayer to initialize
///   3. Opening VideoPlayerController.file() on the partial file —
///      video_player reads ahead as more bytes arrive
class MediaPreviewSheet extends ConsumerStatefulWidget {
  const MediaPreviewSheet({super.key, required this.media});
  final MediaMessage media;

  @override
  ConsumerState<MediaPreviewSheet> createState() => _MediaPreviewSheetState();
}

class _MediaPreviewSheetState extends ConsumerState<MediaPreviewSheet> {
  // Auto-preview threshold for non-video types (photos, audio).
  static const _autoPreviewMaxBytes = 20 * 1024 * 1024; // 20 MB

  _PreviewState _state = _PreviewState.idle;
  String? _localPath;
  String? _error;

  // Streaming progress (0.0–1.0), shown while video buffers.
  double _streamProgress = 0.0;
  int _streamedBytes = 0;

  // Video
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  // Audio
  AudioPlayer? _audioPlayer;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _initPreview();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _initPreview() async {
    final m = widget.media;

    if (!_isPreviewable(m.mediaType)) {
      setState(() => _state = _PreviewState.metadata);
      return;
    }

    // Videos always stream regardless of size.
    final isVideo = m.mediaType == MediaType.video ||
        m.mediaType == MediaType.animation ||
        m.mediaType == MediaType.videoNote;

    if (!isVideo && m.fileSize > _autoPreviewMaxBytes && m.fileSize > 0) {
      setState(() => _state = _PreviewState.tooBig);
      return;
    }

    setState(() => _state = _PreviewState.loading);

    if (isVideo) {
      await _startStreamingVideo();
    } else {
      await _fetchAndLoad();
    }
  }

  // ── Video download with progress ─────────────────────────────

  Future<void> _startStreamingVideo() async {
    try {
      final send = ref.read(tdlibSendProvider);
      final client = ref.read(tdlibClientProvider);

      // Subscribe to UpdateFile events for live progress.
      final sub = client.updates.listen((event) {
        if (event is td.UpdateFile &&
            event.file.id == widget.media.fileId &&
            mounted) {
          final downloaded = event.file.local.downloadedSize;
          setState(() {
            _streamedBytes = downloaded;
            _streamProgress = widget.media.fileSize > 0
                ? (downloaded / widget.media.fileSize).clamp(0.0, 1.0)
                : 0.0;
          });
        }
      });

      // Download fully before playing — synchronous: true waits for completion.
      // This is the only reliable cross-platform approach; partial-file playback
      // requires platform-specific media server support not available on Windows.
      final result = await send(td.DownloadFile(
        fileId: widget.media.fileId,
        priority: 32,
        offset: 0,
        limit: 0,
        synchronous: true,
      ));

      await sub.cancel();
      if (!mounted) return;

      String? path;
      if (result is td.File && result.local.isDownloadingCompleted) {
        path = result.local.path.isNotEmpty ? result.local.path : null;
      }

      // If synchronous didn't give us the path, poll once more.
      if (path == null || path.isEmpty) {
        final fileResult = await send(td.GetFile(fileId: widget.media.fileId));
        if (fileResult is td.File) {
          path = fileResult.local.path.isNotEmpty ? fileResult.local.path : null;
        }
      }

      if (path == null || path.isEmpty) {
        setState(() {
          _state = _PreviewState.error;
          _error = 'Download completed but file path is empty';
        });
        return;
      }

      _localPath = path;
      await _setupVideoPlayer(path);
    } catch (e) {
      Log.error('Video preview failed: $e', tag: 'PREVIEW');
      if (mounted) {
        setState(() {
          _state = _PreviewState.error;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _setupVideoPlayer(String path) async {
    // With fvp registered, VideoPlayerController.file() works on all platforms
    // including Windows (D3D11 hardware decoding) and Linux (OpenGL).
    _videoController = VideoPlayerController.file(io.File(path));

    try {
      await _videoController!.initialize();
    } catch (e) {
      Log.error('VideoPlayer init failed: $e', tag: 'PREVIEW');
      if (mounted) {
        setState(() {
          _state = _PreviewState.error;
          _error = 'Could not play video: $e';
        });
      }
      return;
    }
    if (!mounted) return;

    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: widget.media.mediaType == MediaType.animation,
      allowFullScreen: true,
      showControls: widget.media.mediaType != MediaType.animation,
      aspectRatio: _videoController!.value.aspectRatio,
    );
    setState(() => _state = _PreviewState.ready);
  }

  // ── Non-streaming fetch (photos, audio) ───────────────────────

  Future<void> _fetchAndLoad() async {
    try {
      final send = ref.read(tdlibSendProvider);
      final result = await send(td.DownloadFile(
        fileId: widget.media.fileId,
        priority: 16,
        offset: 0,
        limit: 0,
        synchronous: true,
      ));

      String? path;
      if (result is td.File) {
        path = result.local.path.isNotEmpty ? result.local.path : null;
      }

      if (path == null || path.isEmpty) {
        if (mounted) setState(() { _state = _PreviewState.error; _error = 'File not available'; });
        return;
      }

      _localPath = path;
      await _setupNonVideoPlayer(path);
    } catch (e) {
      Log.error('Preview fetch failed: $e', tag: 'PREVIEW');
      if (mounted) setState(() { _state = _PreviewState.error; _error = e.toString(); });
    }
  }

  Future<void> _setupNonVideoPlayer(String path) async {
    final type = widget.media.mediaType;

    if (type == MediaType.photo) {
      if (mounted) setState(() => _state = _PreviewState.ready);
      return;
    }

    if (type == MediaType.audio || type == MediaType.voiceNote) {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setFilePath(path);
      _audioDuration = _audioPlayer!.duration ?? Duration.zero;
      _audioPlayer!.positionStream.listen((pos) {
        if (mounted) setState(() => _audioPosition = pos);
      });
      _audioPlayer!.playingStream.listen((playing) {
        if (mounted) setState(() => _audioPlaying = playing);
      });
      if (mounted) setState(() => _state = _PreviewState.ready);
      return;
    }

    if (mounted) setState(() => _state = _PreviewState.metadata);
  }

  bool _isPreviewable(MediaType type) =>
      type == MediaType.photo ||
      type == MediaType.video ||
      type == MediaType.audio ||
      type == MediaType.voiceNote ||
      type == MediaType.animation ||
      type == MediaType.videoNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.media;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
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
                width: 36,
                height: 4,
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
                        Text(
                          sanitizeText(m.fileName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${m.typeLabel} · ${formatBytes(m.fileSize)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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

            const Divider(height: 1),

            // Content
            Expanded(
              child: _buildContent(theme, scrollController),
            ),

            // Action bar
            _ActionBar(
              media: m,
              localPath: _localPath,
              onDownload: () => _enqueue(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ScrollController scrollController) {
    return switch (_state) {
      _PreviewState.idle || _PreviewState.loading => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: _streamProgress > 0 ? _streamProgress : null,
                        strokeWidth: 3,
                      ),
                    ),
                    if (_streamProgress > 0)
                      Text(
                        '${(_streamProgress * 100).round()}%',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _streamProgress > 0
                      ? 'Buffering ${formatBytes(_streamedBytes)}...'
                      : 'Loading preview...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      _PreviewState.error => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: Color(0xFFFF1744)),
                const SizedBox(height: 12),
                Text(_error ?? 'Preview failed',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() { _state = _PreviewState.loading; _error = null; _streamProgress = 0; });
                    _initPreview();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      _PreviewState.tooBig => _TooBigPrompt(
          media: widget.media,
          onStream: () {
            setState(() => _state = _PreviewState.loading);
            _startStreamingVideo();
          },
          onDownload: () => _enqueue(context),
        ),
      _PreviewState.ready => _buildReadyContent(theme, scrollController),
      _PreviewState.metadata => _MetadataView(
          media: widget.media,
          scrollController: scrollController,
        ),
    };
  }

  Widget _buildReadyContent(ThemeData theme, ScrollController scrollController) {
    final type = widget.media.mediaType;

    if (type == MediaType.photo) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.file(
            io.File(_localPath!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_rounded,
              size: 64,
              color: Color(0xFF78909C),
            ),
          ),
        ),
      );
    }

    if (type == MediaType.video ||
        type == MediaType.animation ||
        type == MediaType.videoNote) {
      if (_chewieController != null) {
        return Chewie(controller: _chewieController!);
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (type == MediaType.audio || type == MediaType.voiceNote) {
      return _AudioPlayer(
        player: _audioPlayer!,
        duration: _audioDuration,
        position: _audioPosition,
        isPlaying: _audioPlaying,
        fileName: widget.media.fileName,
      );
    }

    return _MetadataView(media: widget.media, scrollController: scrollController);
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

// ── Preview states ────────────────────────────────────────────────

enum _PreviewState { idle, loading, ready, error, tooBig, metadata }

// ── Audio player widget ───────────────────────────────────────────

class _AudioPlayer extends StatelessWidget {
  const _AudioPlayer({
    required this.player,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.fileName,
  });

  final AudioPlayer player;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.audiotrack_rounded,
                size: 48, color: Color(0xFF2AABEE)),
          ),
          const SizedBox(height: 24),
          Text(
            sanitizeText(fileName),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              activeColor: const Color(0xFF2AABEE),
              onChanged: (v) {
                final ms = (v * duration.inMilliseconds).round();
                player.seek(Duration(milliseconds: ms));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(_fmt(duration),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.replay_10_rounded),
                onPressed: () => player.seek(
                    Duration(seconds: position.inSeconds - 10)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFF2AABEE),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  iconSize: 28,
                  color: Colors.white,
                  icon: Icon(isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  onPressed: () =>
                      isPlaying ? player.pause() : player.play(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.forward_10_rounded),
                onPressed: () => player.seek(
                    Duration(seconds: position.inSeconds + 10)),
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

// ── Too-big prompt ────────────────────────────────────────────────

class _TooBigPrompt extends StatelessWidget {
  const _TooBigPrompt({
    required this.media,
    required this.onStream,
    required this.onDownload,
  });
  final MediaMessage media;
  final VoidCallback onStream;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = media.mediaType == MediaType.video ||
        media.mediaType == MediaType.animation ||
        media.mediaType == MediaType.videoNote;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_download_outlined,
                size: 56,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              isVideo ? 'Large video file' : 'File too large for in-app preview',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              formatBytes(media.fileSize),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (isVideo) ...[
              FilledButton.icon(
                onPressed: onStream,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Stream while downloading'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download to device'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Metadata view ─────────────────────────────────────────────────

class _MetadataView extends StatelessWidget {
  const _MetadataView(
      {required this.media, required this.scrollController});
  final MediaMessage media;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              FileTypeIcon.iconFor(media.fileName),
              size: 40,
              color: FileTypeIcon.colorFor(media.fileName),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildRow('Name', sanitizeText(media.fileName), theme),
        _buildRow('Type', media.typeLabel, theme),
        _buildRow('Size', formatBytes(media.fileSize), theme),
        if (media.mimeType.isNotEmpty) _buildRow('MIME', media.mimeType, theme),
        if (media.caption.isNotEmpty)
          _buildRow('Caption', sanitizeText(media.caption), theme),
        if (media.date > 0)
          _buildRow(
            'Date',
            DateTime.fromMillisecondsSinceEpoch(media.date * 1000)
                .toLocal()
                .toString()
                .substring(0, 16),
            theme,
          ),
      ],
    );
  }

  static Widget _buildRow(String label, String value, ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

// ── Action bar ────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.media,
    required this.localPath,
    required this.onDownload,
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
                label: const Text('Download'),
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
                    files: [XFile(localPath!)],
                    text: media.fileName,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
