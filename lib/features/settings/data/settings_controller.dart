import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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
  static const customDownloadPath = 'custom_download_path';
  // Bandwidth
  static const globalSpeedLimitBps = 'global_speed_limit_bps';
  // Retry
  static const maxAutoRetries = 'max_auto_retries';
  static const retryBackoffBaseSeconds = 'retry_backoff_base_seconds';
  // Checksum
  static const verifyChecksums = 'verify_checksums';
  // Scheduling
  static const downloadOnlyOnSchedule = 'download_only_on_schedule';
  static const scheduleStartHour = 'schedule_start_hour';
  static const scheduleEndHour = 'schedule_end_hour';
  static const allowCellularForSmallFilesMb = 'allow_cellular_small_mb';
  // Thermal & battery
  static const pauseOnHighThermal = 'pause_on_high_thermal';
  static const lowBatteryThresholdPct = 'low_battery_threshold_pct';
  static const chargingOnlyMode = 'charging_only_mode';
  // Proxy
  static const proxyEnabled = 'proxy_enabled';
  static const proxyType = 'proxy_type';
  static const proxyHost = 'proxy_host';
  static const proxyPort = 'proxy_port';
  static const proxyUsername = 'proxy_username';
  static const proxyPassword = 'proxy_password';
  static const proxySecret = 'proxy_secret';
  // Auto-cleanup
  static const autoCleanupEnabled = 'auto_cleanup_enabled';
  static const autoCleanupAfterDays = 'auto_cleanup_after_days';
  static const autoCleanupMinFreeMb = 'auto_cleanup_min_free_mb';
  static const autoCleanupKeepFavorites = 'auto_cleanup_keep_favorites';
  // Mirror rules
  static const mirrorRules = 'mirror_rules_json';
  // Haptics
  static const hapticsEnabled = 'haptics_enabled';
  // Notifications
  static const notificationsEnabled = 'notifications_enabled';
  static const notifyOnCompletion = 'notify_on_completion';
  static const notifyOnError = 'notify_on_error';
  static const notifyOnMilestone = 'notify_on_milestone';
  static const notificationSound = 'notification_sound';
  static const quietHoursEnabled = 'quiet_hours_enabled';
  static const quietHoursStart = 'quiet_hours_start';
  static const quietHoursEnd = 'quiet_hours_end';
}

/// Global settings provider.
final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

/// Manages user preferences via [SharedPreferences].
class SettingsController extends Notifier<SettingsState> {
  SharedPreferences? _prefs;

  @override
  SettingsState build() => const SettingsState();

  /// Load persisted settings. Call once at app start.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();

    final basePath = _prefs?.getString(_Keys.customDownloadPath) ??
        await _resolveDefaultDownloadPath();

    final mirrorJson = _prefs?.getString(_Keys.mirrorRules);
    final mirrors = _parseMirrorRules(mirrorJson);

    state = SettingsState(
      concurrentDownloads: _prefs?.getInt(_Keys.concurrentDownloads) ?? 3,
      isDarkMode: _prefs?.getBool(_Keys.isDarkMode) ?? true,
      smartCategorization: _prefs?.getBool(_Keys.smartCategorization) ?? false,
      downloadBasePath: basePath,
      wifiOnly: _prefs?.getBool(_Keys.wifiOnly) ?? false,
      pauseOnLowBattery: _prefs?.getBool(_Keys.pauseOnLowBattery) ?? false,
      autoExtractArchives: _prefs?.getBool(_Keys.autoExtractArchives) ?? false,
      globalSpeedLimitBps: _prefs?.getInt(_Keys.globalSpeedLimitBps) ?? 0,
      maxAutoRetries: _prefs?.getInt(_Keys.maxAutoRetries) ?? 5,
      retryBackoffBaseSeconds:
          _prefs?.getInt(_Keys.retryBackoffBaseSeconds) ?? 5,
      verifyChecksums: _prefs?.getBool(_Keys.verifyChecksums) ?? false,
      downloadOnlyOnSchedule:
          _prefs?.getBool(_Keys.downloadOnlyOnSchedule) ?? false,
      scheduleStartHour: _prefs?.getInt(_Keys.scheduleStartHour) ?? 2,
      scheduleEndHour: _prefs?.getInt(_Keys.scheduleEndHour) ?? 6,
      allowCellularForSmallFilesMb:
          _prefs?.getInt(_Keys.allowCellularForSmallFilesMb) ?? 0,
      pauseOnHighThermal: _prefs?.getBool(_Keys.pauseOnHighThermal) ?? false,
      lowBatteryThresholdPct:
          _prefs?.getInt(_Keys.lowBatteryThresholdPct) ?? 15,
      chargingOnlyMode: _prefs?.getBool(_Keys.chargingOnlyMode) ?? false,
      proxyEnabled: _prefs?.getBool(_Keys.proxyEnabled) ?? false,
      proxyType: ProxyType.values.firstWhere(
        (t) => t.name == (_prefs?.getString(_Keys.proxyType) ?? 'none'),
        orElse: () => ProxyType.none,
      ),
      proxyHost: _prefs?.getString(_Keys.proxyHost) ?? '',
      proxyPort: _prefs?.getInt(_Keys.proxyPort) ?? 1080,
      proxyUsername: _prefs?.getString(_Keys.proxyUsername) ?? '',
      proxyPassword: _prefs?.getString(_Keys.proxyPassword) ?? '',
      proxySecret: _prefs?.getString(_Keys.proxySecret) ?? '',
      autoCleanupEnabled: _prefs?.getBool(_Keys.autoCleanupEnabled) ?? false,
      autoCleanupAfterDays: _prefs?.getInt(_Keys.autoCleanupAfterDays) ?? 30,
      autoCleanupMinFreeMb: _prefs?.getInt(_Keys.autoCleanupMinFreeMb) ?? 500,
      autoCleanupKeepFavorites:
          _prefs?.getBool(_Keys.autoCleanupKeepFavorites) ?? true,
      mirrorRules: mirrors,
      hapticsEnabled: _prefs?.getBool(_Keys.hapticsEnabled) ?? true,
      notificationsEnabled: _prefs?.getBool(_Keys.notificationsEnabled) ?? true,
      notifyOnCompletion: _prefs?.getBool(_Keys.notifyOnCompletion) ?? true,
      notifyOnError: _prefs?.getBool(_Keys.notifyOnError) ?? true,
      notifyOnMilestone: _prefs?.getBool(_Keys.notifyOnMilestone) ?? true,
      notificationSound: _prefs?.getBool(_Keys.notificationSound) ?? true,
      quietHoursEnabled: _prefs?.getBool(_Keys.quietHoursEnabled) ?? false,
      quietHoursStart: _prefs?.getInt(_Keys.quietHoursStart) ?? 22,
      quietHoursEnd: _prefs?.getInt(_Keys.quietHoursEnd) ?? 7,
    );

    Log.info(
      'Settings loaded: concurrent=${state.concurrentDownloads}, '
      'dark=${state.isDarkMode}, wifi=${state.wifiOnly}, '
      'lowBat=${state.pauseOnLowBattery}, extract=${state.autoExtractArchives}, '
      'speedLimit=${state.globalSpeedLimitBps}B/s, '
      'proxy=${state.proxyEnabled}(${state.proxyType.name}), '
      'mirrors=${state.mirrorRules.length}',
      tag: 'SETTINGS',
    );
  }

  // ── Core setters ──────────────────────────────────────────────

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

  Future<void> setDownloadPath(String path) async {
    await _prefs?.setString(_Keys.customDownloadPath, path);
    state = state.copyWith(downloadBasePath: path);
  }

  // ── Bandwidth ─────────────────────────────────────────────────

  Future<void> setGlobalSpeedLimit(int bps) async {
    final clamped = bps < 0 ? 0 : bps;
    await _prefs?.setInt(_Keys.globalSpeedLimitBps, clamped);
    state = state.copyWith(globalSpeedLimitBps: clamped);
  }

  // ── Retry ─────────────────────────────────────────────────────

  Future<void> setMaxAutoRetries(int value) async {
    final clamped = value.clamp(0, 20);
    await _prefs?.setInt(_Keys.maxAutoRetries, clamped);
    state = state.copyWith(maxAutoRetries: clamped);
  }

  Future<void> setRetryBackoffBase(int seconds) async {
    final clamped = seconds.clamp(1, 60);
    await _prefs?.setInt(_Keys.retryBackoffBaseSeconds, clamped);
    state = state.copyWith(retryBackoffBaseSeconds: clamped);
  }

  // ── Checksum ──────────────────────────────────────────────────

  Future<void> setVerifyChecksums(bool enabled) async {
    await _prefs?.setBool(_Keys.verifyChecksums, enabled);
    state = state.copyWith(verifyChecksums: enabled);
  }

  // ── Scheduling ────────────────────────────────────────────────

  Future<void> setDownloadOnlyOnSchedule(bool enabled) async {
    await _prefs?.setBool(_Keys.downloadOnlyOnSchedule, enabled);
    state = state.copyWith(downloadOnlyOnSchedule: enabled);
  }

  Future<void> setScheduleWindow(int startHour, int endHour) async {
    await _prefs?.setInt(_Keys.scheduleStartHour, startHour.clamp(0, 23));
    await _prefs?.setInt(_Keys.scheduleEndHour, endHour.clamp(0, 23));
    state = state.copyWith(
      scheduleStartHour: startHour.clamp(0, 23),
      scheduleEndHour: endHour.clamp(0, 23),
    );
  }

  Future<void> setAllowCellularForSmallFiles(int mb) async {
    await _prefs?.setInt(_Keys.allowCellularForSmallFilesMb, mb.clamp(0, 1000));
    state = state.copyWith(allowCellularForSmallFilesMb: mb.clamp(0, 1000));
  }

  // ── Thermal & battery ─────────────────────────────────────────

  Future<void> setPauseOnHighThermal(bool enabled) async {
    await _prefs?.setBool(_Keys.pauseOnHighThermal, enabled);
    state = state.copyWith(pauseOnHighThermal: enabled);
  }

  Future<void> setLowBatteryThreshold(int pct) async {
    final clamped = pct.clamp(5, 50);
    await _prefs?.setInt(_Keys.lowBatteryThresholdPct, clamped);
    state = state.copyWith(lowBatteryThresholdPct: clamped);
  }

  Future<void> setChargingOnlyMode(bool enabled) async {
    await _prefs?.setBool(_Keys.chargingOnlyMode, enabled);
    state = state.copyWith(chargingOnlyMode: enabled);
  }

  // ── Proxy ─────────────────────────────────────────────────────

  Future<void> setProxyEnabled(bool enabled) async {
    await _prefs?.setBool(_Keys.proxyEnabled, enabled);
    state = state.copyWith(proxyEnabled: enabled);
  }

  Future<void> setProxyConfig({
    required ProxyType type,
    required String host,
    required int port,
    String username = '',
    String password = '',
    String secret = '',
  }) async {
    await _prefs?.setString(_Keys.proxyType, type.name);
    await _prefs?.setString(_Keys.proxyHost, host);
    await _prefs?.setInt(_Keys.proxyPort, port);
    await _prefs?.setString(_Keys.proxyUsername, username);
    await _prefs?.setString(_Keys.proxyPassword, password);
    await _prefs?.setString(_Keys.proxySecret, secret);
    state = state.copyWith(
      proxyType: type,
      proxyHost: host,
      proxyPort: port,
      proxyUsername: username,
      proxyPassword: password,
      proxySecret: secret,
    );
  }

  // ── Auto-cleanup ──────────────────────────────────────────────

  Future<void> setAutoCleanupEnabled(bool enabled) async {
    await _prefs?.setBool(_Keys.autoCleanupEnabled, enabled);
    state = state.copyWith(autoCleanupEnabled: enabled);
  }

  Future<void> setAutoCleanupAfterDays(int days) async {
    final clamped = days.clamp(1, 365);
    await _prefs?.setInt(_Keys.autoCleanupAfterDays, clamped);
    state = state.copyWith(autoCleanupAfterDays: clamped);
  }

  Future<void> setAutoCleanupMinFreeMb(int mb) async {
    final clamped = mb.clamp(0, 10000);
    await _prefs?.setInt(_Keys.autoCleanupMinFreeMb, clamped);
    state = state.copyWith(autoCleanupMinFreeMb: clamped);
  }

  Future<void> setAutoCleanupKeepFavorites(bool keep) async {
    await _prefs?.setBool(_Keys.autoCleanupKeepFavorites, keep);
    state = state.copyWith(autoCleanupKeepFavorites: keep);
  }

  // ── Mirror rules ──────────────────────────────────────────────

  Future<void> addMirrorRule(MirrorRule rule) async {
    final updated = [...state.mirrorRules, rule];
    await _saveMirrorRules(updated);
    state = state.copyWith(mirrorRules: updated);
  }

  Future<void> updateMirrorRule(int index, MirrorRule rule) async {
    final updated = [...state.mirrorRules];
    if (index < 0 || index >= updated.length) return;
    updated[index] = rule;
    await _saveMirrorRules(updated);
    state = state.copyWith(mirrorRules: updated);
  }

  Future<void> removeMirrorRule(int index) async {
    final updated = [...state.mirrorRules];
    if (index < 0 || index >= updated.length) return;
    updated.removeAt(index);
    await _saveMirrorRules(updated);
    state = state.copyWith(mirrorRules: updated);
  }

  Future<void> _saveMirrorRules(List<MirrorRule> rules) async {
    final json = jsonEncode(rules.map((r) => r.toJson()).toList());
    await _prefs?.setString(_Keys.mirrorRules, json);
  }

  List<MirrorRule> _parseMirrorRules(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => MirrorRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.error('Failed to parse mirror rules: $e', tag: 'SETTINGS');
      return const [];
    }
  }

  // ── Haptic feedback ───────────────────────────────────────────

  Future<void> setHapticsEnabled(bool enabled) async {
    await _prefs?.setBool(_Keys.hapticsEnabled, enabled);
    state = state.copyWith(hapticsEnabled: enabled);
  }

  // ── Notifications ─────────────────────────────────────────────

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs?.setBool(_Keys.notificationsEnabled, enabled);
    state = state.copyWith(notificationsEnabled: enabled);
  }

  Future<void> setNotifyOnCompletion(bool enabled) async {
    await _prefs?.setBool(_Keys.notifyOnCompletion, enabled);
    state = state.copyWith(notifyOnCompletion: enabled);
  }

  Future<void> setNotifyOnError(bool enabled) async {
    await _prefs?.setBool(_Keys.notifyOnError, enabled);
    state = state.copyWith(notifyOnError: enabled);
  }

  Future<void> setNotifyOnMilestone(bool enabled) async {
    await _prefs?.setBool(_Keys.notifyOnMilestone, enabled);
    state = state.copyWith(notifyOnMilestone: enabled);
  }

  Future<void> setNotificationSound(bool enabled) async {
    await _prefs?.setBool(_Keys.notificationSound, enabled);
    state = state.copyWith(notificationSound: enabled);
  }

  Future<void> setQuietHoursEnabled(bool enabled) async {
    await _prefs?.setBool(_Keys.quietHoursEnabled, enabled);
    state = state.copyWith(quietHoursEnabled: enabled);
  }

  Future<void> setQuietHours(int start, int end) async {
    await _prefs?.setInt(_Keys.quietHoursStart, start.clamp(0, 23));
    await _prefs?.setInt(_Keys.quietHoursEnd, end.clamp(0, 23));
    state = state.copyWith(
      quietHoursStart: start.clamp(0, 23),
      quietHoursEnd: end.clamp(0, 23),
    );
  }

  // ── Path helpers ──────────────────────────────────────────────

  String resolveDownloadPath(String fileName) {
    final sep = Platform.pathSeparator;
    if (state.smartCategorization) {
      final category = SettingsState.categoryForExtension(fileName);
      return '${state.downloadBasePath}$sep$category$sep$fileName';
    }
    return '${state.downloadBasePath}$sep$fileName';
  }

  /// Returns a platform-appropriate default download directory.
  static Future<String> _resolveDefaultDownloadPath() async {
    final sep = Platform.pathSeparator;
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/Tesseract';
    }
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return '${dir.path}${sep}Tesseract';
    } catch (_) {}
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}${sep}Tesseract';
  }
}
