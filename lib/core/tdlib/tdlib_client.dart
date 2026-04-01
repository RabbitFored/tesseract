import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';

import '../constants/app_constants.dart';
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/platform_interfaces/td_native_plugin_real.dart'
    as td_real;
// ignore: implementation_imports
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
    debugPrint('[TdLibClient] Registering FFI plugin...');
    // Register FFI plugin before anything else
    td_real.TdNativePlugin.registerWith();
    await td_plugin.TdPlugin.initialize('libtdjson.so');
    debugPrint('[TdLibClient] FFI plugin ready.');

    _clientId = tdCreate();
    debugPrint('[TdLibClient] Created native client id=$_clientId');

    // Start the receive loop BEFORE sending any request, so we never
    // miss an event that arrives between tdSend() and the await below.
    _startReceiveLoop();
    debugPrint('[TdLibClient] Receive loop started.');

    // Set up the auth-state future BEFORE sending SetTdlibParameters to
    // avoid a race condition on the broadcast stream.
    final authStateFuture = updates
        .where((e) {
          debugPrint('[TdLibClient] Received update: ${e.runtimeType}');
          return e is UpdateAuthorizationState;
        })
        .first
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint(
              '[TdLibClient] TIMEOUT waiting for UpdateAuthorizationState!',
            );
            throw TimeoutException(
              'TDLib did not respond after SetTdlibParameters',
            );
          },
        );

    // Point TDLib at a persistent directory for its database files.
    final appDir = await getApplicationDocumentsDirectory();
    final tdlibDir = '${appDir.path}/tdlib';
    debugPrint('[TdLibClient] DB dir: $tdlibDir');

    debugPrint('[TdLibClient] Sending SetTdlibParameters...');
    debugPrint(
      '[TdLibClient] API_ID=${AppConstants.telegramApiId} '
      'API_HASH=${AppConstants.telegramApiHash.isEmpty ? "(EMPTY)" : "(set)"}',
    );

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
    debugPrint('[TdLibClient] SetTdlibParameters sent. Awaiting auth state...');

    // Await TDLib's acknowledgment (future was set up before tdSend).
    await authStateFuture;
    debugPrint('[TdLibClient] Initialization complete!');
  }

  /// Start a periodic timer that polls TDLib for pending events.
  void _startReceiveLoop() {
    _receiveTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _pollReceive(),
    );
  }

  /// Poll TDLib for pending events (called by the periodic timer).
  void _pollReceive() {
    if (_clientId == 0) return;

    // tdReceive with timeout=0 returns immediately if nothing is available.
    // The 50ms timer interval provides the actual polling cadence.
    final result = tdReceive(0);
    if (result != null) {
      debugPrint('[TdLibClient] tdReceive got: ${result.runtimeType}');
      if (!_updateController.isClosed) {
        _updateController.add(result);
      }
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
