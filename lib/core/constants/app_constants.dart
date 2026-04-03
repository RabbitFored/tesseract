import 'package:package_info_plus/package_info_plus.dart';

/// Application-wide constants.
///
/// Telegram API credentials are injected at build time via `--dart-define`:
///   flutter build apk \
///     --dart-define=TELEGRAM_API_ID=YOUR_ID \
///     --dart-define=TELEGRAM_API_HASH=YOUR_HASH
///
/// Register at https://my.telegram.org/apps to obtain your credentials.
/// In CI, these are supplied from GitHub secrets (see .github/workflows/build.yml).
abstract final class AppConstants {
  static PackageInfo? _packageInfo;

  /// Call this during app bootstrap to initialize dynamic metadata.
  /// Safe to skip in test environments — all getters have fallbacks.
  static Future<void> initialize() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      // Test environment or platform unavailable — use fallbacks.
      _packageInfo = null;
    }
  }

  static String get appName =>
      (_packageInfo?.appName.isNotEmpty == true)
          ? _packageInfo!.appName
          : 'Tesseract';

  static String get developer => 'Struthio';

  static String get appVersion {
    final p = _packageInfo;
    if (p == null) return '0.0.0';
    return p.buildNumber.isNotEmpty
        ? '${p.version}+${p.buildNumber}'
        : p.version;
  }

  // ── Telegram API credentials (injected via --dart-define) ────
  static const int telegramApiId =
      int.fromEnvironment('TELEGRAM_API_ID', defaultValue: 0);
  static const String telegramApiHash =
      String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
}
