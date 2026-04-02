import 'package:telegram_downloader/core/tdlib/tdlib_client.dart';
import 'package:telegram_downloader/core/tdlib/tdlib_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final container = ProviderContainer();
  final client = container.read(tdlibClientProvider);
  await client.init();

  print('Sending LoadChats...');
  final loadResult = await client.send(LoadChats(chatList: null, limit: 30));
  print('LoadChats returned: $loadResult');
  
  print('Sending GetChats...');
  final getResult = await client.send(GetChats(chatList: null, limit: 30));
  print('GetChats returned: $getResult');
}
