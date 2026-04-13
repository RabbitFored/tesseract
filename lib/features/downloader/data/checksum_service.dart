import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../../core/utils/logger.dart';

/// Computes and verifies file checksums in a background isolate.
///
/// Runs entirely in [Isolate.run] — no platform channels, no Flutter types.
class ChecksumService {
  const ChecksumService._();

  /// Compute the MD5 hex digest of a file in a background isolate.
  /// Returns null if the file does not exist or an error occurs.
  static Future<String?> computeMd5(String filePath) async {
    try {
      return await Isolate.run(() => _computeMd5Sync(filePath));
    } catch (e) {
      Log.error('Checksum computation failed for $filePath: $e',
          tag: 'CHECKSUM');
      return null;
    }
  }

  /// Verify a file against an expected MD5 hex string.
  /// Returns true if the file matches, false otherwise.
  static Future<bool> verifyMd5(String filePath, String expectedMd5) async {
    if (expectedMd5.isEmpty) return true; // nothing to verify
    final actual = await computeMd5(filePath);
    if (actual == null) return false;
    final match = actual.toLowerCase() == expectedMd5.toLowerCase();
    Log.info(
      'Checksum verify: expected=$expectedMd5 actual=$actual match=$match',
      tag: 'CHECKSUM',
    );
    return match;
  }

  /// Synchronous MD5 computation — runs inside an isolate.
  /// Reads the file in one shot via [File.readAsBytesSync]; safe because
  /// this always runs in a spawned isolate with its own memory heap.
  static String _computeMd5Sync(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    return md5.convert(file.readAsBytesSync()).toString();
  }
}
