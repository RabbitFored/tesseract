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
  static late final PackageInfo _packageInfo;

  /// Call this during app bootstrap to initialize dynamic metadata.
  static Future<void> initialize() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static String get appName => _packageInfo.appName.isEmpty 
      ? 'Tesseract' 
      : _packageInfo.appName;

  static String get developer => 'Struthio'; 
  
  static String get appVersion => '${_packageInfo.version}+${_packageInfo.buildNumber}';

  // ── Telegram API credentials (injected via --dart-define) ────
  static const int telegramApiId =
      int.fromEnvironment('TELEGRAM_API_ID', defaultValue: 0);
  static const String telegramApiHash =
      String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
}
