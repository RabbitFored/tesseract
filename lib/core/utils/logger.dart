import 'dart:developer' as dev;

/// Lightweight logger wrapping dart:developer for structured output.
abstract final class Log {
  static void info(String message, {String tag = 'APP'}) {
    dev.log('[$tag] $message');
  }

  static void error(String message, {Object? error, StackTrace? stack, String tag = 'APP'}) {
    dev.log('[$tag] ERROR: $message', error: error, stackTrace: stack);
  }

  static void tdlib(String message) {
    dev.log('[TDLib] $message');
  }
}
