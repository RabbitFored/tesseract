import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/logger.dart';
import '../domain/settings_state.dart';

/// Keys for SharedPreferences.
abstract final class _Keys {
  static const concurrentDownloads = 'concurrent_downloads';
  static const isDarkMode = 'is_dark_mode';
  static const smartCategorization = 'smart_categorization';
  static const wifiOnly = 'wifi_only';
  static const pauseOnLowBattery = 'pause_on_low_battery';
  static const autoExtractArchives = 'auto_extract_archives';
}

/// Global settings provider.
final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>(
  (ref) => SettingsController(),
);

/// Manages user preferences via [SharedPreferences].
class SettingsController extends StateNotifier<SettingsState> {
  SettingsController() : super(const SettingsState());

  SharedPreferences? _prefs;

  /// Load persisted settings. Call once at app start.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    // Default to the public Android Downloads folder so files can be shared
    final basePath = _prefs?.getString('custom_download_path') ?? 
        '/storage/emulated/0/Download/Tesseract';

    state = SettingsState(
      concurrentDownloads:
          _prefs?.getInt(_Keys.concurrentDownloads) ?? 3,
      isDarkMode: _prefs?.getBool(_Keys.isDarkMode) ?? true,
      smartCategorization:
          _prefs?.getBool(_Keys.smartCategorization) ?? false,
      downloadBasePath: basePath,
      wifiOnly: _prefs?.getBool(_Keys.wifiOnly) ?? false,
      pauseOnLowBattery:
          _prefs?.getBool(_Keys.pauseOnLowBattery) ?? false,
      autoExtractArchives:
          _prefs?.getBool(_Keys.autoExtractArchives) ?? false,
    );

    Log.info(
      'Settings loaded: concurrent=${state.concurrentDownloads}, '
      'dark=${state.isDarkMode}, wifi=${state.wifiOnly}, '
      'lowBat=${state.pauseOnLowBattery}, extract=${state.autoExtractArchives}',
      tag: 'SETTINGS',
    );
  }

  Future<void> setConcurrentDownloads(int value) async {
    final clamped = value.clamp(1, 5);
    await _prefs?.setInt(_Keys.concurrentDownloads, clamped);
    state = state.copyWith(concurrentDownloads: clamped);
  }

  Future<void> setDarkMode(bool enabled) async {
    await _prefs?.setBool(_Keys.isDarkMode, enabled);
    state = state.copyWith(isDarkMode: enabled);
  }

  Future<void> setSmartCategorization(bool enabled) async {
    await _prefs?.setBool(_Keys.smartCategorization, enabled);
    state = state.copyWith(smartCategorization: enabled);
  }

  Future<void> setWifiOnly(bool enabled) async {
    await _prefs?.setBool(_Keys.wifiOnly, enabled);
    state = state.copyWith(wifiOnly: enabled);
  }

  Future<void> setPauseOnLowBattery(bool enabled) async {
    await _prefs?.setBool(_Keys.pauseOnLowBattery, enabled);
    state = state.copyWith(pauseOnLowBattery: enabled);
  }

  Future<void> setAutoExtractArchives(bool enabled) async {
    await _prefs?.setBool(_Keys.autoExtractArchives, enabled);
    state = state.copyWith(autoExtractArchives: enabled);
  }

  String resolveDownloadPath(String fileName) {
    if (state.smartCategorization) {
      final category = SettingsState.categoryForExtension(fileName);
      return '${state.downloadBasePath}/$category/$fileName';
    }
    return '${state.downloadBasePath}/$fileName';
  }

  Future<void> setDownloadPath(String path) async {
    await _prefs?.setString('custom_download_path', path);
    state = state.copyWith(downloadBasePath: path);
  }
}
