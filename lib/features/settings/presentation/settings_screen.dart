import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/data/auth_controller.dart';
import '../../downloader/data/download_manager.dart';
import '../data/settings_controller.dart';
import '../data/user_profile_provider.dart';
import '../domain/settings_state.dart';
import 'widgets/mirror_rules_screen.dart';
import 'widgets/proxy_settings_sheet.dart';
import 'widgets/schedule_settings_sheet.dart';

/// Settings screen — exposes all user-configurable options.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Account ───────────────────────────────────────
          _SectionHeader(title: 'Account', theme: theme),
          const _AccountCard(),
          const SizedBox(height: 8),

          // ── Downloads ─────────────────────────────────────
          _SectionHeader(title: 'Downloads', theme: theme),

          // Concurrent downloads slider
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Concurrent Downloads',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    _Badge('${settings.concurrentDownloads}'),
                  ],
                ),
                Text(
                  'Maximum simultaneous downloads',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Slider(
                  value: settings.concurrentDownloads.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${settings.concurrentDownloads}',
                  activeColor: const Color(0xFF2AABEE),
                  onChanged: (v) =>
                      controller.setConcurrentDownloads(v.round()),
                ),
              ],
            ),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Smart Categorization'),
            subtitle: Text(
              'Auto-organize files into type-based folders',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: const Icon(Icons.folder_special_rounded),
            value: settings.smartCategorization,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setSmartCategorization,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Auto-Extract Archives'),
            subtitle: Text(
              'Extract ZIP/TAR/GZ after download',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.folder_zip_rounded,
              color: settings.autoExtractArchives
                  ? const Color(0xFFAB47BC)
                  : null,
            ),
            value: settings.autoExtractArchives,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setAutoExtractArchives,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Verify Checksums'),
            subtitle: Text(
              'Verify MD5 integrity after download completes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.verified_rounded,
              color: settings.verifyChecksums
                  ? const Color(0xFF26A69A)
                  : null,
            ),
            value: settings.verifyChecksums,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setVerifyChecksums,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Bandwidth ─────────────────────────────────────
          _SectionHeader(title: 'Bandwidth', theme: theme),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Card(
              color: theme.colorScheme.surfaceContainerHigh,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: Color(0xFF78909C)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'TDLib has no safe speed-cap API — '
                        'hard bandwidth limits cause TCP session drops. '
                        'To limit bandwidth, reduce Concurrent Downloads to 1.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Connection Recovery ───────────────────────────
          _SectionHeader(title: 'Connection Recovery', theme: theme),

          _RetryTile(settings: settings, controller: controller),

          const SizedBox(height: 16),

          // ── Scheduling & Network Rules ────────────────────
          _SectionHeader(title: 'Scheduling & Network Rules', theme: theme),

          SwitchListTile(
            title: const Text('Wi-Fi Only Mode'),
            subtitle: Text(
              'Pause downloads when not on Wi-Fi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              settings.wifiOnly
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              color: settings.wifiOnly ? const Color(0xFF2AABEE) : null,
            ),
            value: settings.wifiOnly,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setWifiOnly,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Download Schedule'),
            subtitle: Text(
              settings.downloadOnlyOnSchedule
                  ? 'Active: ${_fmtHour(settings.scheduleStartHour)} – '
                      '${_fmtHour(settings.scheduleEndHour)}'
                  : 'Disabled',
              style: theme.textTheme.bodySmall?.copyWith(
                color: settings.downloadOnlyOnSchedule
                    ? const Color(0xFF2AABEE)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => ScheduleSettingsSheet(
                settings: settings,
                controller: controller,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Thermal & Battery ─────────────────────────────
          _SectionHeader(title: 'Thermal & Battery', theme: theme),

          SwitchListTile(
            title: const Text('Pause on Low Battery'),
            subtitle: Text(
              'Pause below ${settings.lowBatteryThresholdPct}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.battery_saver_rounded,
              color: settings.pauseOnLowBattery
                  ? const Color(0xFFFFAB00)
                  : null,
            ),
            value: settings.pauseOnLowBattery,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setPauseOnLowBattery,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          if (settings.pauseOnLowBattery) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Battery threshold',
                          style: theme.textTheme.bodySmall),
                      _Badge('${settings.lowBatteryThresholdPct}%'),
                    ],
                  ),
                  Slider(
                    value: settings.lowBatteryThresholdPct.toDouble(),
                    min: 5,
                    max: 50,
                    divisions: 9,
                    label: '${settings.lowBatteryThresholdPct}%',
                    activeColor: const Color(0xFFFFAB00),
                    onChanged: (v) =>
                        controller.setLowBatteryThreshold(v.round()),
                  ),
                ],
              ),
            ),
          ],

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Pause on High Temperature'),
            subtitle: Text(
              'Pause downloads when device overheats',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.thermostat_rounded,
              color: settings.pauseOnHighThermal
                  ? const Color(0xFFEF5350)
                  : null,
            ),
            value: settings.pauseOnHighThermal,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setPauseOnHighThermal,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Charging Only Mode'),
            subtitle: Text(
              'Only download while device is charging',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.battery_charging_full_rounded,
              color: settings.chargingOnlyMode
                  ? const Color(0xFF66BB6A)
                  : null,
            ),
            value: settings.chargingOnlyMode,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setChargingOnlyMode,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Proxy ─────────────────────────────────────────
          _SectionHeader(title: 'Proxy', theme: theme),

          ListTile(
            leading: Icon(
              Icons.vpn_lock_rounded,
              color: settings.proxyEnabled
                  ? const Color(0xFF2AABEE)
                  : null,
            ),
            title: const Text('Proxy Settings'),
            subtitle: Text(
              settings.proxyEnabled
                  ? '${settings.proxyType.name.toUpperCase()} — '
                      '${settings.proxyHost}:${settings.proxyPort}'
                  : 'Disabled',
              style: theme.textTheme.bodySmall?.copyWith(
                color: settings.proxyEnabled
                    ? const Color(0xFF2AABEE)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProxySettingsSheet(
                settings: settings,
                controller: controller,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Channel Mirroring ─────────────────────────────
          _SectionHeader(title: 'Channel Mirroring', theme: theme),

          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Mirror Rules'),
            subtitle: Text(
              settings.mirrorRules.isEmpty
                  ? 'No channels mirrored'
                  : '${settings.mirrorRules.length} channel(s) mirrored',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MirrorRulesScreen(),
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Storage ───────────────────────────────────────
          _SectionHeader(title: 'Storage', theme: theme),

          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Download Location'),
            subtitle: Text(
              settings.downloadBasePath.isNotEmpty
                  ? settings.downloadBasePath
                  : 'Not configured',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.edit_rounded, size: 20),
            onTap: () async {
              final result = await FilePicker.platform.getDirectoryPath();
              if (result != null) controller.setDownloadPath(result);
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          _AutoCleanupTile(settings: settings, controller: controller),

          if (settings.autoCleanupEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Delete after', style: theme.textTheme.bodySmall),
                      _Badge('${settings.autoCleanupAfterDays} days'),
                    ],
                  ),
                  Slider(
                    value: settings.autoCleanupAfterDays.toDouble(),
                    min: 1,
                    max: 90,
                    divisions: 17,
                    label: '${settings.autoCleanupAfterDays}d',
                    activeColor: const Color(0xFFEF5350),
                    onChanged: (v) =>
                        controller.setAutoCleanupAfterDays(v.round()),
                  ),
                  const SizedBox(height: 8),
                  Consumer(builder: (ctx, ref, _) {
                    return OutlinedButton.icon(
                      onPressed: () async {
                        final manager = ref.read(downloadManagerProvider);
                        final result = await manager.runCleanupNow();
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(
                              'Cleaned up ${result.deletedCount} files, '
                              'freed ${result.freedBytes ~/ 1024}KB',
                            ),
                          ));
                        }
                      },
                      icon: const Icon(Icons.cleaning_services_rounded),
                      label: const Text('Run Cleanup Now'),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Appearance ────────────────────────────────────
          _SectionHeader(title: 'Appearance', theme: theme),

          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: Text(
              settings.isDarkMode ? 'Dark theme' : 'Light theme',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              settings.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              color: settings.isDarkMode
                  ? const Color(0xFFFFAB00)
                  : const Color(0xFFFF6D00),
            ),
            value: settings.isDarkMode,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setDarkMode,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 24),

          // ── About ─────────────────────────────────────────
          _SectionHeader(title: 'About', theme: theme),

          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(AppConstants.appName),
            subtitle: Text(
              'v${AppConstants.appVersion} • ${AppConstants.developer}\n'
              'Powered by TDLib',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            isThreeLine: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _fmtHour(int h) =>
      '${h.toString().padLeft(2, '0')}:00';
}

// ── Shared widgets ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});
  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: const Color(0xFF2AABEE),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2AABEE).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2AABEE),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );
}

// ── Retry tile ────────────────────────────────────────────────────

class _RetryTile extends StatelessWidget {
  const _RetryTile({required this.settings, required this.controller});
  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.replay_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Auto-Retry Attempts',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              _Badge(settings.maxAutoRetries == 0
                  ? 'Off'
                  : '${settings.maxAutoRetries}×'),
            ],
          ),
          Text(
            'Automatic retries on connection drop (0 = disabled)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: settings.maxAutoRetries.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: '${settings.maxAutoRetries}',
            activeColor: const Color(0xFF2AABEE),
            onChanged: (v) => controller.setMaxAutoRetries(v.round()),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Backoff base delay',
                style: theme.textTheme.bodySmall,
              ),
              _Badge('${settings.retryBackoffBaseSeconds}s'),
            ],
          ),
          Slider(
            value: settings.retryBackoffBaseSeconds.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '${settings.retryBackoffBaseSeconds}s',
            activeColor: const Color(0xFF2AABEE),
            onChanged: (v) => controller.setRetryBackoffBase(v.round()),
          ),
          Text(
            'Delay = base × 2ⁿ (exponential backoff)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auto-cleanup tile ─────────────────────────────────────────────

class _AutoCleanupTile extends StatelessWidget {
  const _AutoCleanupTile(
      {required this.settings, required this.controller});
  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      title: const Text('Smart Storage Retention'),
      subtitle: Text(
        settings.autoCleanupEnabled
            ? 'Auto-delete completed files after '
                '${settings.autoCleanupAfterDays} days'
            : 'Completed files kept indefinitely',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      secondary: Icon(
        Icons.auto_delete_rounded,
        color: settings.autoCleanupEnabled
            ? const Color(0xFFEF5350)
            : null,
      ),
      value: settings.autoCleanupEnabled,
      activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
      activeThumbColor: const Color(0xFF2AABEE),
      onChanged: controller.setAutoCleanupEnabled,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// ── Account card ──────────────────────────────────────────────────

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load profile: $err'),
      ),
      data: (user) {
        if (user == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No user loaded.'),
          );
        }

        final name = [user.firstName, user.lastName]
            .where((s) => s.isNotEmpty)
            .join(' ');
        final initials =
            name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Card(
                color: theme.colorScheme.surfaceContainerHigh,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF2AABEE),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (user.phoneNumber.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '+${user.phoneNumber}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${user.id}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF1744),
                  side: const BorderSide(color: Color(0xFFFF1744)),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of Telegram?'),
        content: const Text(
          'Active downloads will be cancelled. '
          'You will need to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744)),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (context.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
      ref.read(authControllerProvider.notifier).logOut();
    }
  }
}
