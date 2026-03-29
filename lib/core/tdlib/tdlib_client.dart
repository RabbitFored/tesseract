import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/tdlib.dart';

import '../constants/app_constants.dart';

/// Riverpod provider exposing the single [TdLibClient] instance.
/// Overridden in main.dart after initialization.
final tdlibClientProvider = Provider<TdLibClient>(
  (ref) => throw UnimplementedError(
    'tdlibClientProvider must be overridden with an initialized TdLibClient',
  ),
);

/// Thin wrapper around the tdlib [TdClient] that manages lifecycle,
/// sets TDLib parameters, and exposes a stream of updates.
class TdLibClient {
  TdClient? _client;
  final _updateController = StreamController<TdObject>.broadcast();

  /// Stream of all TDLib updates (messages, auth state changes, etc.).
  Stream<TdObject> get updates => _updateController.stream;

  /// Whether the native client has been created.
  bool get isInitialized => _client != null;

  /// Create the native TDLib client and configure database parameters.
  Future<void> initialize() async {
    _client = TdClient.create();

    // Start receiving updates in the background.
    _poll();

    // Point TDLib at a persistent directory for its database files.
    final appDir = await getApplicationDocumentsDirectory();
    final tdlibDir = '${appDir.path}/tdlib';

    await _send(SetTdlibParameters(
      useTestDc: false,
      databaseDirectory: tdlibDir,
      filesDirectory: '$tdlibDir/files',
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: AppConstants.telegramApiId,
      apiHash: AppConstants.telegramApiHash,
      systemLanguageCode: 'en',
      deviceModel: 'Android',
      systemVersion: '14',
      applicationVersion: AppConstants.appVersion,
    ));
  }

  /// Send a TDLib function and return the result.
  Future<TdObject?> send(TdFunction function) => _send(function);

  /// Dispose the native client and close the update stream.
  void dispose() {
    _client?.destroy();
    _client = null;
    _updateController.close();
  }

  // ── Private helpers ──────────────────────────────────────────

  Future<TdObject?> _send(TdFunction function) async {
    if (_client == null) return null;
    return _client!.send(function);
  }

  void _poll() {
    Future.doWhile(() async {
      if (_client == null) return false;
      final event = _client!.receive(timeout: 1.0);
      if (event != null) {
        _updateController.add(event);
      }
      return _client != null;
    });
  }
}
