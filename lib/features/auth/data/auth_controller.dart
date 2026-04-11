import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart';

import '../../../core/tdlib/tdlib_client.dart';
import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/auth_state.dart';

/// Global provider for the auth controller.
final authControllerProvider =
    NotifierProvider<AuthController, AuthFlowState>(
  AuthController.new,
);

/// Manages the Telegram authentication lifecycle by listening to TDLib
/// authorization-state updates and exposing a reactive [AuthFlowState].
class AuthController extends Notifier<AuthFlowState> {
  StreamSubscription<TdObject>? _sub;

  // Track the last "clean" auth step so we can return to it after errors.
  AuthFlowState _lastCleanState = const AuthLoading();

  @override
  AuthFlowState build() {
    final client = ref.read(tdlibClientProvider);
    _sub = client.updates.listen(_onUpdate);

    ref.onDispose(() {
      _sub?.cancel();
    });

    final cached = client.lastAuthState;
    if (cached != null) {
      return _mapAuthStateToFlow(cached);
    }
    
    return const AuthLoading();
  }

  // ── TDLib update handler ─────────────────────────────────────

  void _onUpdate(TdObject event) {
    if (event is UpdateAuthorizationState) {
      final next = _mapAuthStateToFlow(event.authorizationState);
      _setState(next);
    }
  }

  AuthFlowState _mapAuthStateToFlow(AuthorizationState authState) {
    Log.tdlib('Auth state → ${authState.runtimeType}');

    switch (authState) {
      case AuthorizationStateWaitPhoneNumber():
        return const AuthWaitPhoneNumber();

      case AuthorizationStateWaitCode(codeInfo: final info):
        return AuthWaitCode(
          phoneNumber: info.phoneNumber,
          codeLength: _codeLength(info.type),
          codeType: _describeCodeType(info.type),
        );

      case AuthorizationStateWaitPassword(passwordHint: final hint):
        return AuthWaitPassword(passwordHint: hint);

      case AuthorizationStateReady():
        return const AuthReady();

      default:
        Log.tdlib('Unhandled auth state: ${authState.runtimeType}');
        return state; // Retain current state if unhandled
    }
  }

  void _setState(AuthFlowState next) {
    _lastCleanState = next;
    state = next;
  }

  // ── Public actions (called from UI) ──────────────────────────

  /// Submit the user's phone number to TDLib.
  Future<void> submitPhoneNumber(String phoneNumber) async {
    final send = ref.read(tdlibSendProvider);
    final result = await send(SetAuthenticationPhoneNumber(
      phoneNumber: phoneNumber,
      settings: null,
    ));
    _handleResult(result);
  }

  /// Submit the OTP code received via SMS / Telegram.
  Future<void> submitCode(String code) async {
    final send = ref.read(tdlibSendProvider);
    final result = await send(CheckAuthenticationCode(code: code));
    _handleResult(result);
  }

  /// Submit the 2FA cloud password.
  Future<void> submitPassword(String password) async {
    final send = ref.read(tdlibSendProvider);
    final result = await send(CheckAuthenticationPassword(password: password));
    _handleResult(result);
  }

  /// Acknowledge an error and return to the previous input step.
  void clearError() {
    state = _lastCleanState;
  }

  // ── Private helpers ──────────────────────────────────────────

  void _handleResult(TdObject? result) {
    if (result is TdError) {
      Log.error('TDLib error ${result.code}: ${result.message}');
      state = AuthError(
        message: result.message,
        previousState: _lastCleanState,
      );
    }
  }

  String _describeCodeType(AuthenticationCodeType type) {
    return switch (type) {
      AuthenticationCodeTypeSms() => 'SMS',
      AuthenticationCodeTypeTelegramMessage() => 'Telegram message',
      AuthenticationCodeTypeCall() => 'Phone call',
      AuthenticationCodeTypeFlashCall() => 'Flash call',
      _ => 'Code',
    };
  }
  /// Safely extracts the digit count from the given code type.
  /// Only Sms / TelegramMessage / Call subtypes carry a length.
  static int _codeLength(AuthenticationCodeType type) {
    if (type is AuthenticationCodeTypeSms) return type.length;
    if (type is AuthenticationCodeTypeTelegramMessage) return type.length;
    return 5; // safe default for call / flash-call / etc.
  }
}
