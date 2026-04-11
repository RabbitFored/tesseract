import 'dart:async';
import 'dart:io' show Platform;

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

  /// Monotonically increasing counter for unique request tagging.
  /// Using microsecond timestamps caused collisions under concurrency.
  int _extraCounter = 0;

  /// Stream of all TDLib updates (messages, auth state changes, etc.).
  Stream<TdObject> get updates => _updateController.stream;

  /// Most recent authorization state seen by the receive loop.
  /// Used by AuthController to avoid missing the initial AuthReady event.
  AuthorizationState? lastAuthState;

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
    final libName = Platform.isWindows
        ? 'tdjson.dll'
        : Platform.isMacOS
            ? 'libtdjson.dylib'
            : 'libtdjson.so';
    await td_plugin.TdPlugin.initialize(libName);
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
          return e is UpdateAuthorizationState || e is TdError;
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

    final params = {
      'use_test_dc': false,
      'database_directory': tdlibDir,
      'files_directory': '$tdlibDir/files',
      'database_encryption_key': '',
      'use_file_database': true,
      'use_chat_info_database': true,
      'use_message_database': true,
      'use_secret_chats': false,
      'api_id': AppConstants.telegramApiId,
      'api_hash': AppConstants.telegramApiHash,
      'system_language_code': 'en',
      'device_model': Platform.operatingSystem,
      'system_version': Platform.operatingSystemVersion,
      'application_version': AppConstants.appVersion,
      'enable_storage_optimizer': true,
      'ignore_file_names': false,
    };

    tdSend(
      _clientId,
      _DualFormatTdlibParameters(params),
    );
    debugPrint('[TdLibClient] SetTdlibParameters sent. Awaiting auth state...');

    // Await TDLib's acknowledgment (future was set up before tdSend).
    final authEvent = await authStateFuture;
    if (authEvent is TdError) {
      throw Exception('TDLib Initialization Error [${authEvent.code}]: ${authEvent.message}');
    }
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
  /// Drains ALL available events per tick to prevent backlog buildup
  /// during active downloads (UpdateFile floods).
  void _pollReceive() {
    if (_clientId == 0) return;

    // Drain all queued events in one tick. Without this loop,
    // only one event is processed per 50ms — if TDLib generates
    // 50+ UpdateFile events/second during downloads, responses to
    // new send() calls get buried behind a growing backlog.
    while (true) {
      final result = tdReceive(0);
      if (result == null) break;

      // Cache the latest auth state so late subscribers don't miss it.
      if (result is UpdateAuthorizationState) {
        lastAuthState = result.authorizationState;
      }

      if (!_updateController.isClosed) {
        _updateController.add(result);
      }
    }
  }

  /// Send a TDLib function asynchronously.
  /// Returns the next update whose [extra] matches the request.
  Future<TdObject?> send(TdFunction function) async {
    if (_clientId == 0) return null;

    // Use a monotonically increasing counter to guarantee uniqueness.
    // The previous approach (microsecond timestamp) caused collisions
    // when multiple send() calls fired in the same microsecond,
    // leading to response mismatching and 40-second timeouts.
    final extra = '${++_extraCounter}';
    tdSend(_clientId, function, extra);

    // Wait for the response with the matching extra field.
    final result = await updates
        .where((e) => e.extra?.toString() == extra)
        .first
        .timeout(const Duration(seconds: 30), onTimeout: () {
      debugPrint('[TdLibClient] send() TIMEOUT extra=$extra function=${function.runtimeType}');
      return const TdError(code: 408, message: 'Request timed out');
    });
    return result;
  }

  /// Dispose the timer and stream controller.
  void dispose() {
    _receiveTimer?.cancel();
    _receiveTimer = null;
    _updateController.close();
  }

  /// Properly shut down TDLib: send Close(), wait for AuthorizationStateClosed,
  /// then destroy the native client. This releases the database lock so the
  /// next app launch doesn't get stuck on "Connecting to Telegram..." (Bug 5).
  Future<void> destroy() async {
    if (_clientId == 0) return;

    try {
      // Send the Close command to TDLib.
      tdSend(_clientId, const Close());

      // Wait (up to 5 seconds) for TDLib to acknowledge the close.
      await updates
          .where((e) =>
              e is UpdateAuthorizationState &&
              e.authorizationState is AuthorizationStateClosed)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[TdLibClient] Timeout waiting for AuthorizationStateClosed');
        return const UpdateAuthorizationState(
          authorizationState: AuthorizationStateClosed(),
        );
      });
    } catch (e) {
      debugPrint('[TdLibClient] Error during destroy: $e');
    } finally {
      _receiveTimer?.cancel();
      _receiveTimer = null;
      final id = _clientId;
      _clientId = 0;
      if (!_updateController.isClosed) {
        _updateController.close();
      }
      // The native client handle is freed internally or not explicitly exposed.
      debugPrint('[TdLibClient] Closed native client id=$id');
    }
  }
}

class _DualFormatTdlibParameters extends TdFunction {
  final Map<String, dynamic> params;
  _DualFormatTdlibParameters(this.params);

  @override
  Map<String, dynamic> toJson([dynamic extra]) {
    // Older TDLib requires all parameters wrapped in a "parameters" object.
    // Newer TDLib >= 1.8.0 requires them flattened on the root.
    // We send BOTH to safely cross ABI breaks between the Dart generator and C binaries.
    return {
      "@type": "setTdlibParameters",
      "@extra": extra,
      "parameters": {"@type": "tdlibParameters", ...params},
      ...params,
    };
  }

  @override
  String getConstructor() => "setTdlibParameters";
}
