/// Application-wide constants.
///
/// Telegram API credentials are injected at build time via `--dart-define`:
///   flutter build apk \
///     --dart-define=TELEGRAM_API_ID=<your_id> \
///     --dart-define=TELEGRAM_API_HASH=<your_hash>
///
/// Register at https://my.telegram.org/apps to obtain your credentials.
/// In CI, these are supplied from GitHub secrets (see .github/workflows/build.yml).
abstract final class AppConstants {
  static const String appVersion = '1.0.0';

  // ── Telegram API credentials (injected via --dart-define) ────
  static const int telegramApiId =
      int.fromEnvironment('TELEGRAM_API_ID', defaultValue: 0);
  static const String telegramApiHash =
      String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
}
