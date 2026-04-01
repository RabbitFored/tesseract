import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';

import '../constants/app_constants.dart';
import 'package:tdlib/src/tdclient/platform_interfaces/td_native_plugin_real.dart'
    as td_real;
import 'package:tdlib/src/tdclient/platform_interfaces/td_plugin.dart'
    as td_plugin;

// Re-export TdObject so other files can import it from this file if needed.
export 'package:tdlib/td_api.dart' show TdObject, TdFunction, TdError;

/// Riverpod provider exposing the single [TdLibClient] instance.
/// Overridden in main.dart after initialization.
final tdlibClientProvider = Provider<TdLibClient>(
  (ref) => throw UnimplementedError(
    'tdlibClientProvider must be overridden with an initialized TdLibClient',
  ),
);

/// Thin wrapper around the tdlib v1.6.0 API that manages lifecycle,
/// sets TDLib parameters, and exposes a stream of updates.
///
/// Uses a main-isolate [Timer.periodic] receive loop instead of the
/// broken [EventSubject] isolate approach (which crashes because
/// TdPlugin.instance is the stub in spawned isolates).
class TdLibClient {
  int _clientId = 0;
  Timer? _receiveTimer;
  final _updateController = StreamController<TdObject>.broadcast();

  /// Stream of all TDLib updates (messages, auth state changes, etc.).
  Stream<TdObject> get updates => _updateController.stream;

  /// Whether the native client has been initialized.
  bool get isInitialized => _clientId != 0;

  /// Create the native TDLib client and configure database parameters.
  ///
  /// Completes only after TDLib has acknowledged [SetTdlibParameters]
  /// by emitting an [UpdateAuthorizationState].
  Future<void> initialize() async {
    // Register FFI plugin before anything else
    td_real.TdNativePlugin.registerWith();
    await td_plugin.TdPlugin.initialize('libtdjson.so');

    _clientId = tdCreate();
    debugPrint('[TdLibClient] Created client id=$_clientId');

    // Start polling for TDLib events on the main isolate.
    // 50ms interval gives responsive event delivery without excessive CPU.
    _receiveTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _pollReceive(),
    );

    // Point TDLib at a persistent directory for its database files.
    final appDir = await getApplicationDocumentsDirectory();
    final tdlibDir = '${appDir.path}/tdlib';

    tdSend(
      _clientId,
      SetTdlibParameters(
        useTestDc: false,
        databaseDirectory: tdlibDir,
        filesDirectory: '$tdlibDir/files',
        databaseEncryptionKey: '',
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
        enableStorageOptimizer: true,
        ignoreFileNames: false,
      ),
    );

    // Wait for TDLib to process SetTdlibParameters and emit an auth state.
    debugPrint('[TdLibClient] Waiting for TDLib auth state acknowledgment...');
    await updates
        .where((e) => e is UpdateAuthorizationState)
        .first
        .timeout(const Duration(seconds: 15));
    debugPrint('[TdLibClient] TDLib acknowledged SetTdlibParameters.');
  }

  /// Poll TDLib for pending events (called by the periodic timer).
  void _pollReceive() {
    if (_clientId == 0) return;

    // Use a very short timeout (0) so this never blocks the UI thread.
    // The timer interval (50ms) provides the actual polling cadence.
    final result = tdReceive(0);
    if (result != null && !_updateController.isClosed) {
      _updateController.add(result);
    }
  }

  /// Send a TDLib function asynchronously.
  /// Returns the next update whose [extra] matches the request.
  Future<TdObject?> send(TdFunction function) async {
    if (_clientId == 0) return null;

    final extra = DateTime.now().microsecondsSinceEpoch.toString();
    tdSend(_clientId, function, extra);

    // Wait for the response with the matching extra field.
    return updates
        .where((e) => e.extra?.toString() == extra)
        .first
        .timeout(const Duration(seconds: 20), onTimeout: () => const Ok());
  }

  /// Dispose the timer and stream controller.
  void dispose() {
    _receiveTimer?.cancel();
    _receiveTimer = null;
    _clientId = 0;
    _updateController.close();
  }
}
