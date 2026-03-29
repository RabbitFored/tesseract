import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/tdlib.dart';

import '../../../core/tdlib/tdlib_client.dart';
import '../../../core/tdlib/tdlib_provider.dart';
import '../../../core/utils/logger.dart';
import '../domain/auth_state.dart';

/// Global provider for the auth controller.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthFlowState>(
  (ref) => AuthController(ref),
);

/// Manages the Telegram authentication lifecycle by listening to TDLib
/// authorization-state updates and exposing a reactive [AuthFlowState].
class AuthController extends StateNotifier<AuthFlowState> {
  AuthController(this._ref) : super(const AuthLoading()) {
    _subscribe();
  }

  final Ref _ref;
  StreamSubscription<TdObject>? _sub;

  // Track the last "clean" auth step so we can return to it after errors.
  AuthFlowState _lastCleanState = const AuthLoading();

  // ── Lifecycle ────────────────────────────────────────────────

  void _subscribe() {
    final client = _ref.read(tdlibClientProvider);
    _sub = client.updates.listen(_onUpdate);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── TDLib update handler ─────────────────────────────────────

  void _onUpdate(TdObject event) {
    if (event is UpdateAuthorizationState) {
      _handleAuthState(event.authorizationState);
    }
  }

  void _handleAuthState(AuthorizationState authState) {
    Log.tdlib('Auth state → ${authState.runtimeType}');

    switch (authState) {
      case AuthorizationStateWaitPhoneNumber():
        _setState(const AuthWaitPhoneNumber());

      case AuthorizationStateWaitCode(codeInfo: final info):
        _setState(AuthWaitCode(
          phoneNumber: info.phoneNumber,
          codeLength: info.type.length ?? 5,
          codeType: _describeCodeType(info.type),
        ));

      case AuthorizationStateWaitPassword(passwordHint: final hint):
        _setState(AuthWaitPassword(passwordHint: hint));

      case AuthorizationStateReady():
        _setState(const AuthReady());

      default:
        // Other states (Closing, Closed, WaitTdlibParameters, etc.)
        Log.tdlib('Unhandled auth state: ${authState.runtimeType}');
    }
  }

  void _setState(AuthFlowState next) {
    _lastCleanState = next;
    state = next;
  }

  // ── Public actions (called from UI) ──────────────────────────

  /// Submit the user's phone number to TDLib.
  Future<void> submitPhoneNumber(String phoneNumber) async {
    final send = _ref.read(tdlibSendProvider);
    final result = await send(SetAuthenticationPhoneNumber(
      phoneNumber: phoneNumber,
      settings: null,
    ));
    _handleResult(result);
  }

  /// Submit the OTP code received via SMS / Telegram.
  Future<void> submitCode(String code) async {
    final send = _ref.read(tdlibSendProvider);
    final result = await send(CheckAuthenticationCode(code: code));
    _handleResult(result);
  }

  /// Submit the 2FA cloud password.
  Future<void> submitPassword(String password) async {
    final send = _ref.read(tdlibSendProvider);
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
}
