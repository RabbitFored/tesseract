import 'package:flutter/material.dart';

import '../../../downloader/domain/download_item.dart';
import '../../../downloader/domain/download_status.dart';

/// Maps file extensions to Material icons and accent colors.
class FileTypeIcon {
  const FileTypeIcon._();

  static IconData iconFor(String fileName) {
    final ext = _ext(fileName);
    return switch (ext) {
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' => Icons.movie_rounded,
      'mp3' || 'flac' || 'ogg' || 'wav' || 'aac' || 'm4a' => Icons.audiotrack_rounded,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' => Icons.image_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'doc' || 'docx' => Icons.description_rounded,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
      'ppt' || 'pptx' => Icons.slideshow_rounded,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_rounded,
      'apk' => Icons.android_rounded,
      'exe' || 'msi' => Icons.terminal_rounded,
      'txt' || 'log' || 'md' => Icons.article_rounded,
      'json' || 'xml' || 'yaml' || 'yml' => Icons.code_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  static Color colorFor(String fileName) {
    final ext = _ext(fileName);
    return switch (ext) {
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' => const Color(0xFFE040FB),
      'mp3' || 'flac' || 'ogg' || 'wav' || 'aac' || 'm4a' => const Color(0xFFFF6D00),
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' => const Color(0xFF00E676),
      'pdf' => const Color(0xFFFF1744),
      'doc' || 'docx' => const Color(0xFF448AFF),
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => const Color(0xFFFFD740),
      'apk' => const Color(0xFF69F0AE),
      _ => const Color(0xFF90A4AE),
    };
  }

  static String _ext(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

/// Status-specific color and label.
class StatusStyle {
  const StatusStyle._();

  static Color colorFor(DownloadStatus status) => switch (status) {
        DownloadStatus.downloading => const Color(0xFF2AABEE),
        DownloadStatus.queued => const Color(0xFF78909C),
        DownloadStatus.paused => const Color(0xFFFFAB00),
        DownloadStatus.completed => const Color(0xFF00E676),
        DownloadStatus.extracting => const Color(0xFFAB47BC),
        DownloadStatus.error => const Color(0xFFFF1744),
      };

  static String labelFor(DownloadStatus status) => switch (status) {
        DownloadStatus.downloading => 'Downloading',
        DownloadStatus.queued => 'Queued',
        DownloadStatus.paused => 'Paused',
        DownloadStatus.completed => 'Completed',
        DownloadStatus.extracting => 'Extracting...',
        DownloadStatus.error => 'Error',
      };
}

/// Phase 10: Error-reason-specific badge styling.
/// When `errorReason` is non-empty, overrides the generic "Error" badge.
class ErrorBadgeStyle {
  const ErrorBadgeStyle._();

  /// Return a contextual label for the error badge.
  static String labelFor(String errorReason) => switch (errorReason) {
        'corrupted_archive' => 'Corrupted Archive',
        'password_required' => 'Password Required',
        'unsupported_format' => 'Unsupported Format',
        'file_not_found' => 'File Not Found',
        'extraction_failed' => 'Extraction Failed',
        _ => 'Error',
      };

  /// Return a contextual color for the error badge.
  /// Corrupted = red, Password = orange, others = default red.
  static Color colorFor(String errorReason) => switch (errorReason) {
        'corrupted_archive' => const Color(0xFFFF1744),
        'password_required' => const Color(0xFFFF9100),
        'unsupported_format' => const Color(0xFF78909C),
        'file_not_found' => const Color(0xFF78909C),
        'extraction_failed' => const Color(0xFFFF1744),
        _ => const Color(0xFFFF1744),
      };

  /// Return a contextual icon for the error badge.
  static IconData iconFor(String errorReason) => switch (errorReason) {
        'corrupted_archive' => Icons.broken_image_rounded,
        'password_required' => Icons.lock_rounded,
        'unsupported_format' => Icons.block_rounded,
        'file_not_found' => Icons.find_in_page_rounded,
        'extraction_failed' => Icons.error_outline_rounded,
        _ => Icons.error_outline_rounded,
      };
}

/// Format bytes into human-readable strings.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size < 10 && i > 0 ? 2 : (size < 100 && i > 0 ? 1 : 0))} ${units[i]}';
}

/// Format a progress fraction as percentage string.
String formatProgress(DownloadItem item) {
  return '${(item.progress * 100).toStringAsFixed(1)}%';
}

/// Format as "downloaded / total" size string.
String formatSizeProgress(DownloadItem item) {
  return '${formatBytes(item.downloadedSize)} / ${formatBytes(item.totalSize)}';
}

/// Format bytes/second as a human-readable speed string.
String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  int i = 0;
  double speed = bytesPerSecond.toDouble();
  while (speed >= 1024 && i < units.length - 1) {
    speed /= 1024;
    i++;
  }
  return '${speed.toStringAsFixed(speed < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}

/// Format seconds remaining as a human-readable ETA string.
String formatEta(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '${seconds}s left';
  if (seconds < 3600) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s left' : '${m}m left';
  }
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return m > 0 ? '${h}h ${m}m left' : '${h}h left';
}
