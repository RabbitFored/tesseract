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
  });

  /// Max concurrent TDLib downloads (1–5).
  final int concurrentDownloads;

  /// Dark or Light theme.
  final bool isDarkMode;

  /// Auto-organize completed files into type-based sub-folders.
  final bool smartCategorization;

  /// Base download directory (resolved at runtime).
  final String downloadBasePath;

  /// Only download when connected to Wi-Fi.
  final bool wifiOnly;

  /// Auto-pause all downloads when battery drops below 15%.
  final bool pauseOnLowBattery;

  /// Auto-extract ZIP/RAR files after download completion.
  final bool autoExtractArchives;

  SettingsState copyWith({
    int? concurrentDownloads,
    bool? isDarkMode,
    bool? smartCategorization,
    String? downloadBasePath,
    bool? wifiOnly,
    bool? pauseOnLowBattery,
    bool? autoExtractArchives,
  }) =>
      SettingsState(
        concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
        isDarkMode: isDarkMode ?? this.isDarkMode,
        smartCategorization: smartCategorization ?? this.smartCategorization,
        downloadBasePath: downloadBasePath ?? this.downloadBasePath,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        pauseOnLowBattery: pauseOnLowBattery ?? this.pauseOnLowBattery,
        autoExtractArchives: autoExtractArchives ?? this.autoExtractArchives,
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
}
