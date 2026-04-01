import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/platform_interfaces/td_native_plugin_real.dart'
    as td_real;
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/platform_interfaces/td_plugin.dart'
    as td_plugin;
import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';

import '../constants/app_constants.dart';

// Re-export TdObject so other files can import it from this file if needed.
export 'package:tdlib/td_api.dart' show TdObject, TdFunction, TdError;

/// Riverpod provider exposing the single [TdLibClient] instance.
/// Overridden in main.dart after initialization.
final tdlibClientProvider = Provider<TdLibClient>(
  (ref) => throw UnimplementedError(
    'tdlibClientProvider must be overridden with an initialized TdLibClient',
  ),
);

class TdLibClient {
  int _clientId = 0;
  final _updateController = StreamController<TdObject>.broadcast();
  Timer? _pollTimer;

  Stream<TdObject> get updates => _updateController.stream;
  bool get isInitialized => _clientId != 0;

  Future<void> initialize() async {
  // Register FFI plugin before anything else
  td_real.TdNativePlugin.registerWith();
  await td_plugin.TdPlugin.initialize('libtdjson.so');

  // Initialize the shared EventSubject isolate
  await EventSubject.initialize();

  _clientId = tdCreate();

  // Forward updates for our client to the broadcast stream.
  EventSubject.instance.listen(_clientId).listen((event) {
    if (!_updateController.isClosed) {
      _updateController.add(event);
    }
  });

  final appDir = await getApplicationDocumentsDirectory();
  final tdlibDir = '${appDir.path}/tdlib';

  // ✅ Attach the listener BEFORE sending — prevents the race condition
  // where UpdateAuthorizationState arrives before .first is subscribed.
  final authStateReceived = updates
      .where((e) => e is UpdateAuthorizationState)
      .first
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'TDLib did not respond after SetTdlibParameters',
        ),
      );

  // Send AFTER the listener is ready
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

  // Now await — listener was already subscribed before tdSend fired
  await authStateReceived;
}

  Future<TdObject?> send(TdFunction function) async {
    if (_clientId == 0) return null;

    final extra = DateTime.now().microsecondsSinceEpoch.toString();
    tdSend(_clientId, function, extra);

    return updates
        .where((e) => e.extra?.toString() == extra)
        .first
        .timeout(const Duration(seconds: 20), onTimeout: () => const Ok());
  }

  void dispose() {
    _pollTimer?.cancel();
    _clientId = 0;
    _updateController.close();
  }
}
