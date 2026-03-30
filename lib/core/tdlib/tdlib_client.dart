import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/event_subject.dart';
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
/// Uses [EventSubject] for receiving updates in a background isolate and
/// [tdCreate] / [tdSend] free functions for sending requests.
class TdLibClient {
  int _clientId = 0;
  final _updateController = StreamController<TdObject>.broadcast();

  /// Stream of all TDLib updates (messages, auth state changes, etc.).
  Stream<TdObject> get updates => _updateController.stream;

  /// Whether the native client has been initialized.
  bool get isInitialized => _clientId != 0;

  /// Create the native TDLib client and configure database parameters.
  Future<void> initialize() async {
    // Register FFI plugin before anything else
    td_real.TdNativePlugin.registerWith();
    await td_plugin.TdPlugin.initialize('libtdjson.so');

    // Initialize the shared EventSubject isolate
    await EventSubject.initialize(libPath: 'libtdjson.so');

    _clientId = tdCreate();
    // Forward updates for our client to the broadcast stream.
    EventSubject.instance.listen(_clientId).listen((event) {
      if (!_updateController.isClosed) {
        _updateController.add(event);
      }
    });

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

  /// Dispose the stream controller.
  void dispose() {
    _clientId = 0;
    _updateController.close();
  }
}
