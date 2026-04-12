import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_provider.dart';

/// Fetches the currently authenticated Telegram user.
final userProfileProvider = FutureProvider<User?>((ref) async {
  final send = ref.watch(tdlibSendProvider);
  final result = await send(const GetMe());
  
  if (result is User) {
    return result;
  }
  return null;
});
