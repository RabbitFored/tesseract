import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
// ignore: implementation_imports
import 'package:tdlib/src/tdclient/event_subject.dart';
import 'package:tdlib/td_api.dart';
import 'package:tdlib/td_client.dart';

import '../constants/app_constants.dart';

export 'package:tdlib/td_api.dart' show TdObject, TdFunction, TdError;

final tdlibClientProvider = Provider<TdLibClient>(
  (ref) => throw UnimplementedError(
    'tdlibClientProvider must be overridden with an initialized TdLibClient',
  ),
);

class TdLibClient {
  int _clientId = 0;
  final _updateController = StreamController<TdObject>.broadcast();

  Stream<TdObject> get updates => _updateController.stream;

  bool get isInitialized => _clientId != 0;

  Future<void> initialize() async {
    // No manual FFI registration needed — TdPlugin handles it on Android
    await TdPlugin.initialize('libtdjson.so');

    await EventSubject.initialize();

    _clientId = tdCreate();

    EventSubject.instance.listen(_clientId).listen((event) {
      if (!_updateController.isClosed) {
        _updateController.add(event);
      }
    });

    final appDir = await getApplicationDocumentsDirectory();
    final tdlibDir = '${appDir.path}/tdlib';

    // Attach listener BEFORE sending to avoid race condition
    final authStateReceived = updates
        .where((e) => e is UpdateAuthorizationState)
        .first
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'TDLib did not respond after SetTdlibParameters',
          ),
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
    _clientId = 0;
    _updateController.close();
  }
}
