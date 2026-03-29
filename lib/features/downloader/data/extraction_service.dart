import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

import '../../../core/utils/logger.dart';

/// Specific error types for extraction failures.
enum ExtractionErrorType {
  none,
  corrupted,
  encrypted,
  unsupported,
  notFound,
  unknown;

  /// Convert to a persisted error reason string for SQLite.
  String get reason => switch (this) {
        ExtractionErrorType.none => '',
        ExtractionErrorType.corrupted => 'corrupted_archive',
        ExtractionErrorType.encrypted => 'password_required',
        ExtractionErrorType.unsupported => 'unsupported_format',
        ExtractionErrorType.notFound => 'file_not_found',
        ExtractionErrorType.unknown => 'extraction_failed',
      };
}

/// Parameters passed into the extraction isolate.
/// Plain Dart object — no platform channels, no Flutter types.
class ExtractionParams {
  const ExtractionParams({
    required this.sourcePath,
    required this.targetDir,
    this.deleteOriginalOnSuccess = true,
  });

  final String sourcePath;
  final String targetDir;
  final bool deleteOriginalOnSuccess;
}

/// Result returned from the extraction isolate to the main thread.
/// Plain Dart object safe to pass across isolate boundaries.
class ExtractionResult {
  const ExtractionResult({
    required this.success,
    this.extractedCount = 0,
    this.errorType = ExtractionErrorType.none,
    this.errorMessage = '',
    this.extractedPaths = const [],
    this.originalDeleted = false,
  });

  final bool success;
  final int extractedCount;
  final ExtractionErrorType errorType;
  final String errorMessage;
  final List<String> extractedPaths;
  final bool originalDeleted;
}

/// Extracts ZIP/TAR/GZ archives in a background Dart isolate.
///
/// Design constraints (Phase 10):
/// - Runs entirely in [Isolate.run] — NO SQLite, NO Riverpod, NO platform channels.
/// - Uses [InputFileStream] for streaming from disk (low memory footprint).
/// - Returns a typed [ExtractionResult]; the MAIN thread updates the DB.
/// - Detects password-protected ZIPs before attempting extraction.
/// - Cleans up partially extracted files on failure.
/// - Optionally deletes the original archive on success.
class ExtractionService {
  const ExtractionService._();

  /// Extract an archive in a background isolate.
  ///
  /// Returns an [ExtractionResult] — the caller (main thread) is responsible
  /// for updating SQLite/Riverpod state based on the result.
  static Future<ExtractionResult> extract({
    required String sourcePath,
    required String targetDir,
    bool deleteOriginalOnSuccess = true,
  }) async {
    try {
      Log.info(
        'Starting extraction: $sourcePath → $targetDir',
        tag: 'EXTRACT',
      );

      final result = await Isolate.run(
        () => _extractInIsolate(ExtractionParams(
          sourcePath: sourcePath,
          targetDir: targetDir,
          deleteOriginalOnSuccess: deleteOriginalOnSuccess,
        )),
      );

      if (result.success) {
        Log.info(
          'Extraction complete: ${result.extractedCount} files'
          '${result.originalDeleted ? ' (original deleted)' : ''}',
          tag: 'EXTRACT',
        );
      } else {
        Log.error(
          'Extraction failed [${result.errorType.name}]: '
          '${result.errorMessage}',
          tag: 'EXTRACT',
        );
      }

      return result;
    } catch (e) {
      Log.error('Extraction isolate crashed', error: e, tag: 'EXTRACT');
      return ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.unknown,
        errorMessage: e.toString(),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════
  // Everything below runs INSIDE the background isolate.
  // No Flutter, no Riverpod, no platform channels. Only dart:io +
  // archive package.
  // ════════════════════════════════════════════════════════════════

  /// Pure function executed in the background isolate.
  static ExtractionResult _extractInIsolate(ExtractionParams params) {
    // ── 1. Validate source file exists ──────────────────────────
    final sourceFile = File(params.sourcePath);
    if (!sourceFile.existsSync()) {
      return const ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.notFound,
        errorMessage: 'Source file not found',
      );
    }

    // ── 2. Validate format ─────────────────────────────────────
    final ext = _fileExtension(params.sourcePath);
    if (!_isSupportedFormat(ext)) {
      return ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.unsupported,
        errorMessage: 'Unsupported archive format: .$ext',
      );
    }

    // ── 3. Pre-flight encryption check (ZIP only) ──────────────
    if (ext == 'zip' && _isZipEncrypted(sourceFile)) {
      return const ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.encrypted,
        errorMessage: 'Archive is password-protected',
      );
    }

    // ── 4. Extract ─────────────────────────────────────────────
    final extractedPaths = <String>[];
    InputFileStream? inputStream;

    try {
      // Create output directory.
      final outDir = Directory(params.targetDir);
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }

      if (ext == 'zip') {
        inputStream = InputFileStream(params.sourcePath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        _extractEntries(archive, params.targetDir, extractedPaths);
        inputStream.close();
        inputStream = null;
      } else if (ext == 'tar') {
        inputStream = InputFileStream(params.sourcePath);
        final archive = TarDecoder().decodeBuffer(inputStream);
        _extractEntries(archive, params.targetDir, extractedPaths);
        inputStream.close();
        inputStream = null;
      } else if (ext == 'gz') {
        _extractGz(sourceFile, params, extractedPaths);
      }

      // ── 5. Success: optionally delete original ───────────────
      bool originalDeleted = false;
      if (params.deleteOriginalOnSuccess && extractedPaths.isNotEmpty) {
        try {
          sourceFile.deleteSync();
          originalDeleted = true;
        } catch (_) {
          // Non-fatal: extraction succeeded even if deletion fails.
        }
      }

      return ExtractionResult(
        success: true,
        extractedCount: extractedPaths.length,
        extractedPaths: extractedPaths,
        originalDeleted: originalDeleted,
      );
    } catch (e) {
      // ── Ensure file handles are closed ─────────────────────
      try {
        inputStream?.close();
      } catch (_) {}

      // ── Clean up partially extracted files ─────────────────
      _cleanupPartialFiles(extractedPaths, params.targetDir);

      // ── Classify the error ─────────────────────────────────
      return _classifyError(e);
    }
  }

  // ── Entry extraction (streaming) ────────────────────────────

  /// Extract all entries from an [Archive] to disk.
  /// Tracks every written file path for cleanup on failure.
  static void _extractEntries(
    Archive archive,
    String targetDir,
    List<String> extractedPaths,
  ) {
    for (final entry in archive) {
      // Sanitize path to prevent zip-slip directory traversal attacks.
      final safeName = _sanitizePath(entry.name);
      if (safeName.isEmpty) continue;

      final entryPath = '$targetDir/$safeName';

      if (entry.isFile) {
        // Create parent directories for nested entries.
        File(entryPath).parent.createSync(recursive: true);

        // Stream entry content to disk via OutputFileStream.
        final outStream = OutputFileStream(entryPath);
        entry.writeContent(outStream);
        outStream.close();

        extractedPaths.add(entryPath);
      } else {
        Directory(entryPath).createSync(recursive: true);
      }
    }
  }

  /// Handle .gz files (potentially .tar.gz).
  /// GZ decompression requires the full compressed buffer, but we stream
  /// the inner tar entries to disk.
  static void _extractGz(
    File sourceFile,
    ExtractionParams params,
    List<String> extractedPaths,
  ) {
    final bytes = sourceFile.readAsBytesSync();
    final decompressed = GZipDecoder().decodeBytes(bytes);

    try {
      // Attempt to decode as .tar.gz (most common GZ use case).
      final archive = TarDecoder().decodeBytes(decompressed);
      _extractEntries(archive, params.targetDir, extractedPaths);
    } catch (_) {
      // Single-file .gz — write the decompressed content directly.
      final outName = params.sourcePath
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.gz', '');
      final outPath = '${params.targetDir}/$outName';

      final outDir = Directory(params.targetDir);
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      File(outPath).writeAsBytesSync(decompressed);
      extractedPaths.add(outPath);
    }
  }

  // ── Encryption detection ────────────────────────────────────

  /// Check if a ZIP file is encrypted by inspecting the Local File Header.
  ///
  /// ZIP format (PKWARE APPNOTE 6.3.10):
  ///   Offset 0-3:  Local file header signature (0x04034b50)
  ///   Offset 6-7:  General Purpose Bit Flag
  ///                 Bit 0 = file is encrypted
  ///
  /// Uses RandomAccessFile for precise, low-level reads with guaranteed
  /// cleanup via try/finally.
  static bool _isZipEncrypted(File file) {
    RandomAccessFile? raf;
    try {
      raf = file.openSync(mode: FileMode.read);
      if (raf.lengthSync() < 30) return false;

      final header = raf.readSync(30);

      // Verify PK\x03\x04 signature.
      if (header[0] != 0x50 ||
          header[1] != 0x4B ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        return false; // Not a valid ZIP.
      }

      // General Purpose Bit Flag at offset 6-7 (little-endian).
      final flags = header[6] | (header[7] << 8);
      return (flags & 0x01) != 0; // Bit 0 = encrypted.
    } catch (_) {
      return false; // Can't determine — let extraction attempt decide.
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  // ── Error classification ────────────────────────────────────

  /// Classify an extraction exception into a typed [ExtractionResult].
  static ExtractionResult _classifyError(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('encrypt') || msg.contains('password')) {
      return const ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.encrypted,
        errorMessage: 'Archive is password-protected',
      );
    }

    // Corruption indicators: unexpected EOF, bad CRC, invalid header, etc.
    if (msg.contains('corrupt') ||
        msg.contains('unexpected end') ||
        msg.contains('invalid') ||
        msg.contains('crc') ||
        msg.contains('bad header') ||
        msg.contains('not a valid') ||
        msg.contains('truncated')) {
      return ExtractionResult(
        success: false,
        errorType: ExtractionErrorType.corrupted,
        errorMessage: 'Archive is corrupted: $e',
      );
    }

    return ExtractionResult(
      success: false,
      errorType: ExtractionErrorType.corrupted,
      errorMessage: 'Extraction failed: $e',
    );
  }

  // ── Cleanup ─────────────────────────────────────────────────

  /// Delete all partially extracted files and remove empty target dir.
  /// Ensures no storage is wasted on failed extractions.
  static void _cleanupPartialFiles(
    List<String> extractedPaths,
    String targetDir,
  ) {
    // Delete individual extracted files.
    for (final path in extractedPaths) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }

    // Recursively remove target directory if empty.
    try {
      final dir = Directory(targetDir);
      if (dir.existsSync()) {
        final remaining = dir.listSync(recursive: true);
        if (remaining.isEmpty) {
          dir.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  // ── Helpers ─────────────────────────────────────────────────

  static String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static bool _isSupportedFormat(String ext) =>
      ext == 'zip' || ext == 'tar' || ext == 'gz';

  /// Sanitize archive entry paths to prevent directory traversal
  /// (zip-slip) attacks. Strips leading slashes and '..' segments.
  static String _sanitizePath(String name) {
    return name
        .replaceAll('\\', '/') // Normalize separators.
        .split('/')
        .where((seg) => seg != '..' && seg.isNotEmpty)
        .join('/');
  }
}
