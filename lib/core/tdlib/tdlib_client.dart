import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

export 'package:handy_tdlib/api.dart' show TdObject, TdFunction, TdError;

final tdlibClientProvider = Provider<TdLibClient>(
  (ref) => throw UnimplementedError(
    'tdlibClientProvider must be overridden with an initialized TdLibClient',
  ),
);

class TdLibClient {
  final _updateController = StreamController<td.TdObject>.broadcast();
  late final SendPort _invokesPort;

  Stream<td.TdObject> get updates => _updateController.stream;

  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final tdlibDir = '${appDir.path}/tdlib';

    // Receive port for updates coming back from the TDLib isolate
    final updatesPort = ReceivePort();

    // Receive port to get the invokes SendPort from the isolate
    final invokeSetupPort = ReceivePort();

    await Isolate.spawn(
      _tdlibIsolate,
      _IsolateArgs(
        updatesSendPort: updatesPort.sendPort,
        invokeSetupSendPort: invokeSetupPort.sendPort,
        tdlibDir: tdlibDir,
        apiId: AppConstants.telegramApiId,
        apiHash: AppConstants.telegramApiHash,
      ),
    );

    // Get the SendPort we use to send TDLib functions to the isolate
    _invokesPort = await invokeSetupPort.first as SendPort;
    invokeSetupPort.close();

    // Forward all updates from the isolate into our broadcast stream
    updatesPort.listen((message) {
      if (message is td.TdObject && !_updateController.isClosed) {
        _updateController.add(message);
      }
    });

    // Wait for TDLib to confirm parameters accepted
    await updates
        .where((e) => e is td.UpdateAuthorizationState)
        .first
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'TDLib did not respond after SetTdlibParameters',
          ),
        );
  }

  Future<td.TdObject?> send(td.TdFunction function) async {
    final extra = DateTime.now().microsecondsSinceEpoch.toString();
    _invokesPort.send(function.toJson(extra));

    return updates
        .where((e) => e.extra?.toString() == extra)
        .first
        .timeout(const Duration(seconds: 20), onTimeout: () => const td.Ok());
  }

  void dispose() {
    _updateController.close();
  }
}

// Args passed into the isolate
class _IsolateArgs {
  final SendPort updatesSendPort;
  final SendPort invokeSetupSendPort;
  final String tdlibDir;
  final int apiId;
  final String apiHash;

  _IsolateArgs({
    required this.updatesSendPort,
    required this.invokeSetupSendPort,
    required this.tdlibDir,
    required this.apiId,
    required this.apiHash,
  });
}

// Runs in a separate isolate — all TDLib calls happen here
@pragma('vm:entry-point')
Future<void> _tdlibIsolate(_IsolateArgs args) async {
  final clientId = TdPlugin.instance.tdCreateClientId();

  // Give main isolate a SendPort to send invokes here
  final invokesPort = ReceivePort();
  args.invokeSetupSendPort.send(invokesPort.sendPort);

  // Listen for TdFunction JSON from the main isolate and forward to TDLib
  invokesPort.listen((message) {
    if (message is String) {
      TdPlugin.instance.tdSend(clientId, message);
    }
  });

  // Send TdlibParameters immediately
  TdPlugin.instance.tdSend(
    clientId,
    td.SetTdlibParameters(
      useTestDc: false,
      databaseDirectory: args.tdlibDir,
      filesDirectory: '${args.tdlibDir}/files',
      databaseEncryptionKey: '',
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: args.apiId,
      apiHash: args.apiHash,
      systemLanguageCode: 'en',
      deviceModel: 'Android',
      systemVersion: '14',
      applicationVersion: '1.0.0',
      enableStorageOptimizer: true,
      ignoreFileNames: false,
    ).toJson(''),
  );

  // Receive loop — poll TDLib and forward updates to main isolate
  while (true) {
    final response = TdPlugin.instance.tdReceive(clientId);
    if (response != null) {
      try {
        final obj = convertJsonToObject(response);
        if (obj != null) args.updatesSendPort.send(obj);
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
