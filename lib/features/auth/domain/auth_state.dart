/// Represents the current step in the Telegram authentication flow.
///
/// Maps directly to TDLib's `AuthorizationState` variants that are relevant
/// to the login flow.
sealed class AuthFlowState {
  const AuthFlowState();
}

/// Initial state — waiting for TDLib to report its first auth update.
class AuthLoading extends AuthFlowState {
  const AuthLoading();
}

/// TDLib is ready for the user's phone number.
class AuthWaitPhoneNumber extends AuthFlowState {
  const AuthWaitPhoneNumber();
}

/// TDLib has sent an OTP and is waiting for the code.
class AuthWaitCode extends AuthFlowState {
  const AuthWaitCode({
    required this.phoneNumber,
    this.codeLength = 5,
    this.codeType = 'SMS',
  });

  final String phoneNumber;
  final int codeLength;
  final String codeType;
}

/// The account has 2FA enabled; TDLib needs the cloud password.
class AuthWaitPassword extends AuthFlowState {
  const AuthWaitPassword({this.passwordHint = ''});

  final String passwordHint;
}

/// Authentication succeeded — user can proceed to the app.
class AuthReady extends AuthFlowState {
  const AuthReady();
}

/// A recoverable error occurred (wrong code, wrong password, etc.).
class AuthError extends AuthFlowState {
  const AuthError({
    required this.message,
    required this.previousState,
  });

  final String message;

  /// The state to return to after the user acknowledges the error.
  final AuthFlowState previousState;
}
