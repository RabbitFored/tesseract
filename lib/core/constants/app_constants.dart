/// Application-wide constants.
///
/// Replace [telegramApiId] and [telegramApiHash] with your own values
/// obtained from https://my.telegram.org/apps before running the app.
abstract final class AppConstants {
  static const String appVersion = '1.0.0';

  // ── Telegram API credentials ─────────────────────────────────
  // IMPORTANT: Register at https://my.telegram.org/apps to obtain these.
  // For production, consider loading from --dart-define or a .env file.
  static const int telegramApiId = 38688572; // TODO: replace with your api_id
  static const String telegramApiHash = '05990baa445d31c8bc8b9538e2eabfa3'; // TODO: replace with your api_hash
}
