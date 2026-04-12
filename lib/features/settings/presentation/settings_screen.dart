import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/data/auth_controller.dart';
import '../data/settings_controller.dart';
import '../data/user_profile_provider.dart';

/// Settings screen with concurrent download slider, theme toggle,
/// and smart categorization toggle.
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
          // ── Account section ───────────────────────────────
          _SectionHeader(title: 'Account', theme: theme),
          const _AccountCard(),
          const SizedBox(height: 8),

          // ── Download section ──────────────────────────────
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
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AABEE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${settings.concurrentDownloads}',
                        style: const TextStyle(
                          color: Color(0xFF2AABEE),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Maximum number of simultaneous downloads',
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

          // Smart categorization
          SwitchListTile(
            title: const Text('Smart Categorization'),
            subtitle: Text(
              'Auto-organize files into folders by type\n'
              '(Videos/, Audio/, Documents/, Photos/)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.smartCategorization,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setSmartCategorization,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const SizedBox(height: 16),

          // ── Automation & Resources section ─────────────────
          _SectionHeader(title: 'Automation & Resources', theme: theme),

          SwitchListTile(
            title: const Text('Wi-Fi Only Mode'),
            subtitle: Text(
              'Pause all downloads when not on Wi-Fi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              settings.wifiOnly
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              color: settings.wifiOnly
                  ? const Color(0xFF2AABEE)
                  : const Color(0xFF78909C),
            ),
            value: settings.wifiOnly,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setWifiOnly,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Pause on Low Battery'),
            subtitle: Text(
              'Auto-pause downloads when battery drops below 15%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              settings.pauseOnLowBattery
                  ? Icons.battery_saver_rounded
                  : Icons.battery_std_rounded,
              color: settings.pauseOnLowBattery
                  ? const Color(0xFFFFAB00)
                  : const Color(0xFF78909C),
            ),
            value: settings.pauseOnLowBattery,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setPauseOnLowBattery,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          const Divider(indent: 16, endIndent: 16, height: 1),

          SwitchListTile(
            title: const Text('Auto-Extract Archives'),
            subtitle: Text(
              'Automatically extract ZIP/TAR/GZ files after download',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            secondary: Icon(
              Icons.folder_zip_rounded,
              color: settings.autoExtractArchives
                  ? const Color(0xFFAB47BC)
                  : const Color(0xFF78909C),
            ),
            value: settings.autoExtractArchives,
            activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
            activeThumbColor: const Color(0xFF2AABEE),
            onChanged: controller.setAutoExtractArchives,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          // Extraction info card (visible when auto-extract is on)
          if (settings.autoExtractArchives) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: const Color(0xFFAB47BC).withValues(alpha: 0.08),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFFAB47BC),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Supported formats: .zip, .tar, .gz\n'
                          'Extraction runs in a background isolate — '
                          'downloads continue uninterrupted.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Appearance section ────────────────────────────
          _SectionHeader(title: 'Appearance', theme: theme),

          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: Text(
              settings.isDarkMode ? 'Dark theme active' : 'Light theme active',
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

          const SizedBox(height: 16),

          // ── Storage info ──────────────────────────────────
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
              final String? result = await FilePicker.platform.getDirectoryPath();
              if (result != null) {
                 controller.setDownloadPath(result);
              }
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),

          if (settings.smartCategorization) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Card(
                color: theme.colorScheme.surfaceContainerHigh,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folder Structure Preview',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final folder in [
                        'Videos/',
                        'Audio/',
                        'Photos/',
                        'Documents/',
                        'Archives/',
                        'Other/',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 3),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                size: 16,
                                color: const Color(0xFFFFAB00)
                                    .withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                folder,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
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
            ),
          ],

          const SizedBox(height: 24),

          // ── About ─────────────────────────────────────────
          _SectionHeader(title: 'About', theme: theme),

          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(AppConstants.appName),
            subtitle: Text(
              'v${AppConstants.appVersion} • Developed by ${AppConstants.developer}\n'
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
        ],
      ),
    );
  }
}

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
        final initials = name.isNotEmpty
            ? name.characters.first.toUpperCase()
            : '?';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Card(
                color: theme.colorScheme.surfaceContainerHigh,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
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
          'Active downloads will be cancelled. You will need to wait for a code to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1744),
            ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});
  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
}
