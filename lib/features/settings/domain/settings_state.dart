/// Persisted user settings.
class SettingsState {
  const SettingsState({
    this.concurrentDownloads = 3,
    this.isDarkMode = true,
    this.smartCategorization = false,
    this.downloadBasePath = '',
    this.wifiOnly = false,
    this.pauseOnLowBattery = false,
    this.autoExtractArchives = false,
    // ── Bandwidth throttling ──────────────────────────────
    this.globalSpeedLimitBps = 0,
    // ── Retry / connection recovery ───────────────────────
    this.maxAutoRetries = 5,
    this.retryBackoffBaseSeconds = 5,
    // ── Checksum verification ─────────────────────────────
    this.verifyChecksums = false,
    // ── Scheduling & network rules ────────────────────────
    this.downloadOnlyOnSchedule = false,
    this.scheduleStartHour = 2,
    this.scheduleEndHour = 6,
    this.allowCellularForSmallFilesMb = 0,
    // ── Thermal & battery ─────────────────────────────────
    this.pauseOnHighThermal = false,
    this.lowBatteryThresholdPct = 15,
    this.chargingOnlyMode = false,
    // ── Proxy ─────────────────────────────────────────────
    this.proxyEnabled = false,
    this.proxyType = ProxyType.none,
    this.proxyHost = '',
    this.proxyPort = 1080,
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.proxySecret = '',
    // ── Auto-cleanup ──────────────────────────────────────
    this.autoCleanupEnabled = false,
    this.autoCleanupAfterDays = 30,
    this.autoCleanupMinFreeMb = 500,
    this.autoCleanupKeepFavorites = true,
    // ── Channel mirroring ─────────────────────────────────
    this.mirrorRules = const [],
    // ── Haptic feedback ───────────────────────────────────
    this.hapticsEnabled = true,
    // ── Notifications ─────────────────────────────────────
    this.notificationsEnabled = true,
    this.notifyOnCompletion = true,
    this.notifyOnError = true,
    this.notifyOnMilestone = true,
    this.notificationSound = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
  });

  // ── Core ──────────────────────────────────────────────────────
  final int concurrentDownloads;
  final bool isDarkMode;
  final bool smartCategorization;
  final String downloadBasePath;
  final bool wifiOnly;
  final bool pauseOnLowBattery;
  final bool autoExtractArchives;

  // ── Bandwidth throttling ──────────────────────────────────────
  /// Global download speed cap in bytes/second. 0 = unlimited.
  final int globalSpeedLimitBps;

  // ── Retry / connection recovery ───────────────────────────────
  /// Maximum number of automatic retries before marking as failed.
  final int maxAutoRetries;

  /// Base delay in seconds for exponential backoff (delay = base * 2^attempt).
  final int retryBackoffBaseSeconds;

  // ── Checksum verification ─────────────────────────────────────
  /// Verify MD5 checksum after download completes (when available).
  final bool verifyChecksums;

  // ── Scheduling & network rules ────────────────────────────────
  /// Only download during the scheduled time window.
  final bool downloadOnlyOnSchedule;

  /// Start hour (0–23) of the allowed download window.
  final int scheduleStartHour;

  /// End hour (0–23) of the allowed download window.
  final int scheduleEndHour;

  /// Allow cellular downloads for files smaller than this (MB). 0 = never.
  final int allowCellularForSmallFilesMb;

  // ── Thermal & battery ─────────────────────────────────────────
  /// Pause downloads when device reports high thermal state.
  final bool pauseOnHighThermal;

  /// Battery percentage below which downloads pause (default 15%).
  final int lowBatteryThresholdPct;

  /// Only download when the device is charging.
  final bool chargingOnlyMode;

  // ── Proxy ─────────────────────────────────────────────────────
  final bool proxyEnabled;
  final ProxyType proxyType;
  final String proxyHost;
  final int proxyPort;
  final String proxyUsername;
  final String proxyPassword;

  /// MTProto proxy secret (hex string).
  final String proxySecret;

  // ── Auto-cleanup ──────────────────────────────────────────────
  final bool autoCleanupEnabled;

  /// Delete completed downloads older than this many days.
  final int autoCleanupAfterDays;

  /// Trigger cleanup when free storage drops below this (MB).
  final int autoCleanupMinFreeMb;

  /// Never auto-delete files marked as favorites.
  final bool autoCleanupKeepFavorites;

  // ── Channel mirroring ─────────────────────────────────────────
  final List<MirrorRule> mirrorRules;

  // ── Haptic feedback ───────────────────────────────────────────
  final bool hapticsEnabled;

  // ── Notifications ─────────────────────────────────────────────
  final bool notificationsEnabled;
  final bool notifyOnCompletion;
  final bool notifyOnError;
  final bool notifyOnMilestone;
  final bool notificationSound;
  final bool quietHoursEnabled;
  final int quietHoursStart;
  final int quietHoursEnd;

  // ── Helpers ───────────────────────────────────────────────────

  /// Whether the current time falls within the scheduled download window.
  bool get isWithinSchedule {
    if (!downloadOnlyOnSchedule) return true;
    // If start == end, treat as "all day" (no restriction).
    if (scheduleStartHour == scheduleEndHour) return true;
    final now = DateTime.now().hour;
    if (scheduleStartHour < scheduleEndHour) {
      // Normal window: e.g. 02:00 – 06:00
      return now >= scheduleStartHour && now < scheduleEndHour;
    }
    // Overnight window: e.g. 22:00 – 06:00
    return now >= scheduleStartHour || now < scheduleEndHour;
  }

  SettingsState copyWith({
    int? concurrentDownloads,
    bool? isDarkMode,
    bool? smartCategorization,
    String? downloadBasePath,
    bool? wifiOnly,
    bool? pauseOnLowBattery,
    bool? autoExtractArchives,
    int? globalSpeedLimitBps,
    int? maxAutoRetries,
    int? retryBackoffBaseSeconds,
    bool? verifyChecksums,
    bool? downloadOnlyOnSchedule,
    int? scheduleStartHour,
    int? scheduleEndHour,
    int? allowCellularForSmallFilesMb,
    bool? pauseOnHighThermal,
    int? lowBatteryThresholdPct,
    bool? chargingOnlyMode,
    bool? proxyEnabled,
    ProxyType? proxyType,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    String? proxySecret,
    bool? autoCleanupEnabled,
    int? autoCleanupAfterDays,
    int? autoCleanupMinFreeMb,
    bool? autoCleanupKeepFavorites,
    List<MirrorRule>? mirrorRules,
    bool? hapticsEnabled,
    bool? notificationsEnabled,
    bool? notifyOnCompletion,
    bool? notifyOnError,
    bool? notifyOnMilestone,
    bool? notificationSound,
    bool? quietHoursEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
  }) =>
      SettingsState(
        concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
        isDarkMode: isDarkMode ?? this.isDarkMode,
        smartCategorization: smartCategorization ?? this.smartCategorization,
        downloadBasePath: downloadBasePath ?? this.downloadBasePath,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        pauseOnLowBattery: pauseOnLowBattery ?? this.pauseOnLowBattery,
        autoExtractArchives: autoExtractArchives ?? this.autoExtractArchives,
        globalSpeedLimitBps: globalSpeedLimitBps ?? this.globalSpeedLimitBps,
        maxAutoRetries: maxAutoRetries ?? this.maxAutoRetries,
        retryBackoffBaseSeconds:
            retryBackoffBaseSeconds ?? this.retryBackoffBaseSeconds,
        verifyChecksums: verifyChecksums ?? this.verifyChecksums,
        downloadOnlyOnSchedule:
            downloadOnlyOnSchedule ?? this.downloadOnlyOnSchedule,
        scheduleStartHour: scheduleStartHour ?? this.scheduleStartHour,
        scheduleEndHour: scheduleEndHour ?? this.scheduleEndHour,
        allowCellularForSmallFilesMb:
            allowCellularForSmallFilesMb ?? this.allowCellularForSmallFilesMb,
        pauseOnHighThermal: pauseOnHighThermal ?? this.pauseOnHighThermal,
        lowBatteryThresholdPct:
            lowBatteryThresholdPct ?? this.lowBatteryThresholdPct,
        chargingOnlyMode: chargingOnlyMode ?? this.chargingOnlyMode,
        proxyEnabled: proxyEnabled ?? this.proxyEnabled,
        proxyType: proxyType ?? this.proxyType,
        proxyHost: proxyHost ?? this.proxyHost,
        proxyPort: proxyPort ?? this.proxyPort,
        proxyUsername: proxyUsername ?? this.proxyUsername,
        proxyPassword: proxyPassword ?? this.proxyPassword,
        proxySecret: proxySecret ?? this.proxySecret,
        autoCleanupEnabled: autoCleanupEnabled ?? this.autoCleanupEnabled,
        autoCleanupAfterDays: autoCleanupAfterDays ?? this.autoCleanupAfterDays,
        autoCleanupMinFreeMb: autoCleanupMinFreeMb ?? this.autoCleanupMinFreeMb,
        autoCleanupKeepFavorites:
            autoCleanupKeepFavorites ?? this.autoCleanupKeepFavorites,
        mirrorRules: mirrorRules ?? this.mirrorRules,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        notifyOnCompletion: notifyOnCompletion ?? this.notifyOnCompletion,
        notifyOnError: notifyOnError ?? this.notifyOnError,
        notifyOnMilestone: notifyOnMilestone ?? this.notifyOnMilestone,
        notificationSound: notificationSound ?? this.notificationSound,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      );

  /// Map file extension to a categorized sub-folder name.
  static String categoryForExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return 'Other';
    final ext = fileName.substring(dot + 1).toLowerCase();

    return switch (ext) {
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' => 'Videos',
      'mp3' || 'flac' || 'ogg' || 'wav' || 'aac' || 'm4a' => 'Audio',
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' =>
        'Photos',
      'pdf' || 'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' ||
      'txt' || 'csv' =>
        'Documents',
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => 'Archives',
      'apk' => 'Apps',
      _ => 'Other',
    };
  }

  /// Check if a file is an extractable archive.
  static bool isArchive(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return false;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return ext == 'zip' || ext == 'tar' || ext == 'gz';
  }

  /// Check if a file is streamable media.
  static bool isStreamable(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return false;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return ext == 'mp4' ||
        ext == 'mkv' ||
        ext == 'webm' ||
        ext == 'mp3' ||
        ext == 'aac' ||
        ext == 'm4a' ||
        ext == 'ogg';
  }
}

// ── Proxy type ────────────────────────────────────────────────────

enum ProxyType { none, socks5, mtproto }

// ── Mirror rule ───────────────────────────────────────────────────

/// How often a mirror rule automatically backfills historical messages.
enum MirrorSyncInterval {
  never,
  hourly,
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
        MirrorSyncInterval.never => 'Manual only',
        MirrorSyncInterval.hourly => 'Every hour',
        MirrorSyncInterval.daily => 'Once daily',
        MirrorSyncInterval.weekly => 'Once weekly',
        MirrorSyncInterval.monthly => 'Once monthly',
      };

  /// Duration between syncs. Null means never auto-sync.
  Duration? get duration => switch (this) {
        MirrorSyncInterval.never => null,
        MirrorSyncInterval.hourly => const Duration(hours: 1),
        MirrorSyncInterval.daily => const Duration(days: 1),
        MirrorSyncInterval.weekly => const Duration(days: 7),
        MirrorSyncInterval.monthly => const Duration(days: 30),
      };
}

/// A rule that mirrors all new media from a Telegram channel to a local folder.
class MirrorRule {
  const MirrorRule({
    required this.channelId,
    required this.channelTitle,
    required this.localFolder,
    this.enabled = true,
    this.filterExtensions = const [],
    this.minFileSizeBytes = 0,
    this.maxFileSizeBytes = 0,
    this.autoSyncInterval = MirrorSyncInterval.never,
    this.lastSyncedAt,
  });

  final int channelId;
  final String channelTitle;
  final String localFolder;
  final bool enabled;

  /// If non-empty, only mirror files with these extensions.
  final List<String> filterExtensions;

  /// Minimum file size to mirror (0 = no minimum).
  final int minFileSizeBytes;

  /// Maximum file size to mirror (0 = no maximum).
  final int maxFileSizeBytes;

  /// How often to automatically backfill historical messages.
  final MirrorSyncInterval autoSyncInterval;

  /// When this rule was last auto-synced (null = never).
  final DateTime? lastSyncedAt;

  /// Whether this rule is due for an auto-sync right now.
  bool get isDueForSync {
    final interval = autoSyncInterval.duration;
    if (interval == null) return false;
    if (lastSyncedAt == null) return true;
    return DateTime.now().difference(lastSyncedAt!) >= interval;
  }

  MirrorRule copyWith({
    int? channelId,
    String? channelTitle,
    String? localFolder,
    bool? enabled,
    List<String>? filterExtensions,
    int? minFileSizeBytes,
    int? maxFileSizeBytes,
    MirrorSyncInterval? autoSyncInterval,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) =>
      MirrorRule(
        channelId: channelId ?? this.channelId,
        channelTitle: channelTitle ?? this.channelTitle,
        localFolder: localFolder ?? this.localFolder,
        enabled: enabled ?? this.enabled,
        filterExtensions: filterExtensions ?? this.filterExtensions,
        minFileSizeBytes: minFileSizeBytes ?? this.minFileSizeBytes,
        maxFileSizeBytes: maxFileSizeBytes ?? this.maxFileSizeBytes,
        autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
        lastSyncedAt:
            clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      );

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'channelTitle': channelTitle,
        'localFolder': localFolder,
        'enabled': enabled,
        'filterExtensions': filterExtensions,
        'minFileSizeBytes': minFileSizeBytes,
        'maxFileSizeBytes': maxFileSizeBytes,
        'autoSyncInterval': autoSyncInterval.name,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      };

  factory MirrorRule.fromJson(Map<String, dynamic> json) => MirrorRule(
        channelId: json['channelId'] as int,
        channelTitle: json['channelTitle'] as String? ?? '',
        localFolder: json['localFolder'] as String,
        enabled: json['enabled'] as bool? ?? true,
        filterExtensions: (json['filterExtensions'] as List<dynamic>?)
                ?.cast<String>() ??
            const [],
        minFileSizeBytes: json['minFileSizeBytes'] as int? ?? 0,
        maxFileSizeBytes: json['maxFileSizeBytes'] as int? ?? 0,
        autoSyncInterval: MirrorSyncInterval.values.firstWhere(
          (e) => e.name == (json['autoSyncInterval'] as String? ?? 'never'),
          orElse: () => MirrorSyncInterval.never,
        ),
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
      );
}
