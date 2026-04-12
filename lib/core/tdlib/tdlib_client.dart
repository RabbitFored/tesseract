import 'dart:async';
import 'dart:convert';
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

    // Silence the massively verbose C++ internal logging polluting PowerShell/stdout.
    // Level 2 = Warnings/Errors/Info. 
    tdExecute(const SetLogVerbosityLevel(newVerbosityLevel: 2));

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

    while (true) {
      final rawResponse = TdPlugin.instance.tdReceive(0);
      if (rawResponse == null) break;

      final Map<String, dynamic> jsonMap = jsonDecode(rawResponse);
      final rawType = jsonMap['@type'];

      if (rawType == 'updateAuthorizationState') {
        final authState = jsonMap['authorization_state'];
        if (authState != null) {
          final authStateType = authState['@type'];
          // Intercept the WaitEncryptionKey state which is missing from the 1.6 SDK schema.
          if (authStateType == 'authorizationStateWaitEncryptionKey') {
            debugPrint('[TdLibClient] Intercepted WaitEncryptionKey (schema bypass). Auto-resolving...');
            // In TDLib > 1.8.0, checkDatabaseEncryptionKey fulfills this stage natively.
            tdSend(_clientId, const _CheckDatabaseEncryptionKey());
            continue;
          }
        }
      }

      // Patch JSON for TDLib 1.6.0 dart ↔ 1.8.x binary schema mismatches.
      _polyfillTdlibSchema(jsonMap);
      final patchedResponse = jsonEncode(jsonMap);

      TdObject? result;
      try {
        result = convertToObject(patchedResponse);
      } catch (e, st) {
        debugPrint('[TdLibClient] Failed to parse response: $e');
        debugPrint('[TdLibClient] Stack: ${st.toString().split('\n').take(3).join('\n')}');
        // If this was a response to a send() call, emit TdError so the
        // completer resolves instead of hanging for 30s.
        final extra = jsonMap['@extra'];
        if (extra != null && !_updateController.isClosed) {
          _updateController.add(TdError(
            code: 500,
            message: 'Schema parse error: $e',
            extra: extra,
          ));
        }
        continue;
      }
      if (result == null) continue;

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

  /// Comprehensive polyfill for TDLib 1.6.0 Dart schema ↔ 1.8.x binary mismatches.
  ///
  /// Three-step process applied recursively:
  /// 1. Apply field aliases for keys renamed between versions
  /// 2. Inject missing keys that fromJson expects but the binary omits
  /// 3. Patch remaining nulls by naming convention
  void _polyfillTdlibSchema(dynamic json) {
    if (json is Map<String, dynamic>) {
      if (json.containsKey('@type')) {
        _applyFieldAliases(json);
        _injectMissingKeys(json);
        _normalizeStructure(json);
        // Patch any remaining null values by naming convention.
        for (final key in json.keys.toList()) {
          if (json[key] != null || key.startsWith('@')) continue;
          if (_isBoolKey(key))        json[key] = false;
          else if (_isIntKey(key))    json[key] = 0;
          else if (_isStringKey(key)) json[key] = '';
        }
      }
      for (final value in json.values) {
        _polyfillTdlibSchema(value);
      }
    } else if (json is List) {
      for (final item in json) {
        _polyfillTdlibSchema(item);
      }
    }
  }

  // ── Field aliases: binary key → dart schema key ──

  static const _fieldAliases = <String, String>{
    'can_add_link_previews': 'can_add_web_page_previews',
    'show_story_poster': 'show_story_sender',
    'use_default_show_story_poster': 'use_default_show_story_sender',
    'can_create_topics': 'can_manage_topics',
  };

  static void _applyFieldAliases(Map<String, dynamic> json) {
    for (final e in _fieldAliases.entries) {
      if (json.containsKey(e.key) && !json.containsKey(e.value)) {
        json[e.value] = json[e.key];
      }
    }
  }

  // ── Structural normalization: handle type changes between versions ──

  /// Some TDLib 1.8.x fields change from plain values to typed wrapper objects.
  /// This normalizes them back to what the Dart 1.6.0 fromJson expects.
  static void _normalizeStructure(Map<String, dynamic> json) {
    final type = json['@type'];

    // messageInteractionInfo.reactions: 1.8.x wraps in {"@type":"messageReactions","reactions":[...]}
    // but 1.6.0 expects a plain List<MessageReaction>.
    if (type == 'messageInteractionInfo') {
      final reactions = json['reactions'];
      if (reactions is Map<String, dynamic> && reactions['@type'] != null) {
        // Unwrap: extract the inner list from the typed wrapper.
        json['reactions'] = reactions['reactions'] ?? [];
      } else if (reactions is! List) {
        json['reactions'] = [];
      }
    }
  }

  // ── Missing key injection: add keys that fromJson reads but binary omits ──

  /// Maps @type → list of keys that the Dart 1.6.0 fromJson expects.
  /// Only lists keys that TDLib 1.8.x is known to omit.
  static const _requiredKeys = <String, Map<String, dynamic>>{
    'user': {
      'is_contact': false, 'is_mutual_contact': false, 'is_close_friend': false,
      'is_verified': false, 'is_premium': false, 'is_support': false,
      'is_scam': false, 'is_fake': false, 'has_active_stories': false,
      'has_unread_active_stories': false, 'have_access': false,
      'added_to_attachment_menu': false, 'restriction_reason': '',
    },
    'userFullInfo': {
      'is_blocked': false, 'can_be_called': false, 'supports_video_calls': false,
      'has_private_calls': false, 'has_private_forwards': false,
      'has_restricted_voice_and_video_note_messages': false,
      'has_pinned_stories': false, 'need_phone_number_privacy_exception': false,
    },
    'supergroup': {
      'has_linked_chat': false, 'has_location': false, 'sign_messages': false,
      'join_to_send_messages': false, 'join_by_request': false,
      'is_slow_mode_enabled': false, 'is_channel': false, 'is_broadcast_group': false,
      'is_forum': false, 'is_verified': false, 'is_scam': false, 'is_fake': false,
      'restriction_reason': '',
    },
    'supergroupFullInfo': {
      'is_all_history_available': false, 'has_hidden_members': false,
      'can_hide_members': false, 'has_aggressive_anti_spam_enabled': false,
      'can_toggle_aggressive_anti_spam': false,
    },
    'basicGroup': {
      'is_active': false,
    },
    'basicGroupFullInfo': {
      'can_hide_members': false, 'can_toggle_aggressive_anti_spam': false,
    },
    'chat': {
      'has_protected_content': false, 'is_translatable': false,
      'is_marked_as_unread': false, 'is_blocked': false,
      'has_scheduled_messages': false, 'can_be_deleted_only_for_self': false,
      'can_be_deleted_for_all_users': false, 'can_be_reported': false,
      'default_disable_notification': false,
    },
    'chatPermissions': {
      'can_send_basic_messages': false, 'can_send_audios': false,
      'can_send_documents': false, 'can_send_photos': false,
      'can_send_videos': false, 'can_send_video_notes': false,
      'can_send_voice_notes': false, 'can_send_polls': false,
      'can_send_other_messages': false, 'can_add_web_page_previews': false,
      'can_change_info': false, 'can_invite_users': false,
      'can_pin_messages': false, 'can_manage_topics': false,
    },
    'chatNotificationSettings': {
      'use_default_mute_for': false, 'use_default_sound': false,
      'use_default_show_preview': false, 'show_preview': false,
      'use_default_mute_stories': false, 'mute_stories': false,
      'use_default_story_sound': false, 'use_default_show_story_sender': false,
      'show_story_sender': false,
      'use_default_disable_pinned_message_notifications': false,
      'disable_pinned_message_notifications': false,
      'use_default_disable_mention_notifications': false,
      'disable_mention_notifications': false,
    },
    'message': {
      'is_outgoing': false, 'is_pinned': false, 'can_be_edited': false,
      'can_be_forwarded': false, 'can_be_saved': false,
      'can_be_deleted_only_for_self': false, 'can_be_deleted_for_all_users': false,
      'can_get_added_reactions': false, 'can_get_statistics': false,
      'can_get_message_thread': false, 'can_get_viewers': false,
      'can_get_media_timestamp_links': false, 'can_report_reactions': false,
      'has_timestamped_media': false, 'is_channel_post': false,
      'is_topic_message': false, 'contains_unread_mention': false,
      'restriction_reason': '', 'author_signature': '',
    },
    'chatFolderInfo': {
      'title': '', 'is_shareable': false, 'has_my_invite_links': false,
    },
    'chatAdministratorRights': {
      'is_anonymous': false, 'can_manage_chat': false,
      'can_change_info': false, 'can_post_messages': false,
      'can_edit_messages': false, 'can_delete_messages': false,
      'can_invite_users': false, 'can_restrict_members': false,
      'can_pin_messages': false, 'can_manage_topics': false,
      'can_promote_members': false, 'can_manage_video_chats': false,
    },
    'chatInviteLink': {
      'is_primary': false, 'is_revoked': false,
      'creates_join_request': false,
    },
    'profilePhoto': {
      'has_animation': false, 'is_personal': false,
    },
    'chatPhoto': {
      'has_animation': false,
    },
    'messageForwardInfo': {
      'public_service_announcement_type': '',
    },
    'forwardSource': {
      'sender_name': '',
    },
    'videoChat': {
      'has_participants': false,
    },
    'linkPreviewOptions': {
      'is_disabled': false, 'force_small_media': false,
      'force_large_media': false, 'show_above_text': false,
    },
    'messagePhoto': {
      'show_caption_above_media': false, 'has_spoiler': false, 'is_secret': false,
    },
    'messageVideo': {
      'show_caption_above_media': false, 'has_spoiler': false, 'is_secret': false,
    },
    'messageAnimation': {
      'show_caption_above_media': false, 'has_spoiler': false, 'is_secret': false,
    },
    'photo': {
      'has_stickers': false,
    },
    'chatMemberStatusCreator': {
      'is_anonymous': false, 'is_member': false,
    },
    'chatMemberStatusAdministrator': {
      'can_be_edited': false,
    },
    'chatMemberStatusRestricted': {
      'is_member': false,
    },
  };

  static void _injectMissingKeys(Map<String, dynamic> json) {
    final type = json['@type'] as String?;
    if (type == null) return;
    final defaults = _requiredKeys[type];
    if (defaults == null) return;
    for (final e in defaults.entries) {
      if (!json.containsKey(e.key)) {
        json[e.key] = e.value;
      }
    }
  }

  // ── Naming convention fallback for types not in _requiredKeys ──

  static bool _isBoolKey(String key) {
    return key.startsWith('is_') || key.startsWith('can_') ||
        key.startsWith('has_') || key.startsWith('have_') ||
        key.startsWith('need_') || key.startsWith('show_') ||
        key.startsWith('use_default_') || key.startsWith('disable_') ||
        key.startsWith('mute_') || key.startsWith('force_') ||
        key.startsWith('added_to_') || key.startsWith('join_') ||
        key.startsWith('sign_') || key.startsWith('supports_') ||
        key.startsWith('contains_') || key.startsWith('default_disable_') ||
        key.startsWith('set_');
  }

  static bool _isIntKey(String key) {
    return key.endsWith('_count') || key.endsWith('_date') ||
        key.endsWith('_size') || key.endsWith('_time') ||
        key.endsWith('_offset') || key.endsWith('_level') ||
        key == 'date' || key == 'edit_date';
  }

  static bool _isStringKey(String key) {
    return key == 'restriction_reason' || key == 'author_signature' ||
        key == 'theme_name' || key == 'client_data' || key == 'title' ||
        key == 'sender_name' || key == 'public_service_announcement_type';
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
      '@type': 'setTdlibParameters',
      '@extra': extra,
      'parameters': {'@type': 'tdlibParameters', ...params},
      ...params,
    };
  }

  @override
  String getConstructor() => 'setTdlibParameters';
}

/// Automatically fulfills the separate CheckDatabaseEncryptionKey 
/// barrier introduced in modern TDLib native engines, while remaining
/// backward compatible with legacy parameter payloads.
class _CheckDatabaseEncryptionKey extends TdFunction {
  const _CheckDatabaseEncryptionKey();

  @override
  Map<String, dynamic> toJson([dynamic extra]) {
    return {
      // Newer TDLib expects checkDatabaseEncryptionKey, older sets it via SetDatabaseEncryptionKey.
      // The native client ignores unregistered keys.
      '@type': 'checkDatabaseEncryptionKey',
      '@extra': extra,
      'encryption_key': '',
      'key': '', 
    };
  }

  @override
  String getConstructor() => 'checkDatabaseEncryptionKey';
}
