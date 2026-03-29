import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';

import 'tdlib_client.dart';

/// Provider that exposes the live stream of TDLib updates.
final tdlibUpdatesProvider = StreamProvider<TdObject>((ref) {
  final client = ref.watch(tdlibClientProvider);
  return client.updates;
});

/// Provider to send a TDLib function. Usage:
///   final result = await ref.read(tdlibSendProvider)(GetMe());
final tdlibSendProvider = Provider<Future<TdObject?> Function(TdFunction)>(
  (ref) {
    final client = ref.watch(tdlibClientProvider);
    return client.send;
  },
);
