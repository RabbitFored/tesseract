import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloader/data/download_manager.dart';
import '../../data/settings_controller.dart';
import '../../domain/settings_state.dart';

/// Screen for managing channel mirror rules.
class MirrorRulesScreen extends ConsumerStatefulWidget {
  const MirrorRulesScreen({super.key});

  @override
  ConsumerState<MirrorRulesScreen> createState() => _MirrorRulesScreenState();
}

class _MirrorRulesScreenState extends ConsumerState<MirrorRulesScreen> {
  bool _syncing = false;
  String? _syncResult;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Channel Mirroring',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          // Global sync button — backfills all enabled rules.
          if (settings.mirrorRules.any((r) => r.enabled))
            _syncing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync_rounded),
                    tooltip: 'Sync now — backfill historical messages',
                    onPressed: () => _runSync(context),
                  ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add mirror rule',
            onPressed: () => _showAddRuleDialog(context, controller),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync result banner.
          if (_syncResult != null)
            Material(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: Color(0xFF2AABEE)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_syncResult!,
                          style: theme.textTheme.bodySmall),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _syncResult = null),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: settings.mirrorRules.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sync_disabled_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No mirror rules',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a rule to automatically download\n'
                          'new files from a Telegram channel.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () =>
                              _showAddRuleDialog(context, controller),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Rule'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: settings.mirrorRules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final rule = settings.mirrorRules[i];
                      return _MirrorRuleCard(
                        rule: rule,
                        syncing: _syncing,
                        onToggle: (enabled) => controller.updateMirrorRule(
                            i, rule.copyWith(enabled: enabled)),
                        onDelete: () => controller.removeMirrorRule(i),
                        onEdit: () =>
                            _showEditRuleDialog(context, controller, i, rule),
                        onSync: () => _runSyncForRule(context, rule),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Sync helpers ─────────────────────────────────────────────

  Future<void> _runSync(BuildContext context) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncResult = null;
    });
    try {
      final manager = ref.read(downloadManagerProvider);
      final count = await manager.mirrorController.syncAll();
      if (mounted) {
        setState(() => _syncResult =
            'Sync complete — $count new file${count == 1 ? '' : 's'} enqueued');
      }
    } catch (e) {
      if (mounted) setState(() => _syncResult = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _runSyncForRule(BuildContext context, MirrorRule rule) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncResult = null;
    });
    try {
      final manager = ref.read(downloadManagerProvider);
      final count = await manager.mirrorController.syncRule(rule);
      if (mounted) {
        final label =
            rule.channelTitle.isNotEmpty ? rule.channelTitle : 'Channel';
        setState(() => _syncResult =
            '$label: $count new file${count == 1 ? '' : 's'} enqueued');
      }
    } catch (e) {
      if (mounted) setState(() => _syncResult = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Dialog helpers ───────────────────────────────────────────

  Future<void> _showAddRuleDialog(
      BuildContext context, SettingsController controller) async {
    await showDialog(
      context: context,
      builder: (_) => _MirrorRuleDialog(
        onSave: (rule) => controller.addMirrorRule(rule),
      ),
    );
  }

  Future<void> _showEditRuleDialog(
    BuildContext context,
    SettingsController controller,
    int index,
    MirrorRule rule,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => _MirrorRuleDialog(
        existing: rule,
        onSave: (updated) => controller.updateMirrorRule(index, updated),
      ),
    );
  }
}

// ── Rule card ─────────────────────────────────────────────────────

class _MirrorRuleCard extends StatelessWidget {
  const _MirrorRuleCard({
    required this.rule,
    required this.syncing,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    required this.onSync,
  });

  final MirrorRule rule;
  final bool syncing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.sync_rounded,
              color: rule.enabled
                  ? const Color(0xFF2AABEE)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.channelTitle.isNotEmpty
                        ? rule.channelTitle
                        : 'Channel ${rule.channelId}',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    rule.localFolder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (rule.filterExtensions.isNotEmpty)
                    Text(
                      'Filter: ${rule.filterExtensions.join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (rule.autoSyncInterval != MirrorSyncInterval.never)
                    Text(
                      'Auto-sync: ${rule.autoSyncInterval.label}'
                      '${rule.lastSyncedAt != null ? ' · Last: ${_formatLastSync(rule.lastSyncedAt!)}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF2AABEE),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            // Per-rule sync button (only shown when rule is enabled).
            if (rule.enabled)
              IconButton(
                icon: syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                tooltip: 'Sync this channel now',
                onPressed: syncing ? null : onSync,
              ),
            Switch(
              value: rule.enabled,
              activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
              activeThumbColor: const Color(0xFF2AABEE),
              onChanged: onToggle,
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  size: 18, color: Color(0xFFEF5350)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastSync(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}

// ── Add / edit dialog ─────────────────────────────────────────────

class _MirrorRuleDialog extends StatefulWidget {
  const _MirrorRuleDialog({this.existing, required this.onSave});

  final MirrorRule? existing;
  final ValueChanged<MirrorRule> onSave;

  @override
  State<_MirrorRuleDialog> createState() => _MirrorRuleDialogState();
}

class _MirrorRuleDialogState extends State<_MirrorRuleDialog> {
  late final TextEditingController _channelId;
  late final TextEditingController _channelTitle;
  late final TextEditingController _folder;
  late final TextEditingController _extensions;
  late MirrorSyncInterval _autoSyncInterval;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _channelId =
        TextEditingController(text: r != null ? r.channelId.toString() : '');
    _channelTitle = TextEditingController(text: r?.channelTitle ?? '');
    _folder = TextEditingController(text: r?.localFolder ?? '');
    _extensions =
        TextEditingController(text: r?.filterExtensions.join(', ') ?? '');
    _autoSyncInterval = r?.autoSyncInterval ?? MirrorSyncInterval.never;
  }

  @override
  void dispose() {
    _channelId.dispose();
    _channelTitle.dispose();
    _folder.dispose();
    _extensions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Mirror Rule' : 'Edit Rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _channelId,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Channel ID',
                hintText: '-1001234567890',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _channelTitle,
              decoration: const InputDecoration(
                labelText: 'Channel Name (display only)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _folder,
                    decoration: const InputDecoration(
                      labelText: 'Local Folder',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath();
                    if (path != null) setState(() => _folder.text = path);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _extensions,
              decoration: const InputDecoration(
                labelText: 'File extensions (optional)',
                hintText: 'mp4, mkv, pdf',
                helperText: 'Leave empty to mirror all files',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MirrorSyncInterval>(
              initialValue: _autoSyncInterval,
              decoration: const InputDecoration(
                labelText: 'Auto-sync interval',
                helperText: 'Automatically backfill historical messages',
                border: OutlineInputBorder(),
              ),
              items: MirrorSyncInterval.values
                  .map((interval) => DropdownMenuItem(
                        value: interval,
                        child: Text(interval.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _autoSyncInterval = value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final id = int.tryParse(_channelId.text.trim());
    if (id == null || _folder.text.trim().isEmpty) return;

    final exts = _extensions.text
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    widget.onSave(MirrorRule(
      channelId: id,
      channelTitle: _channelTitle.text.trim(),
      localFolder: _folder.text.trim(),
      filterExtensions: exts,
      autoSyncInterval: _autoSyncInterval,
      lastSyncedAt: widget.existing?.lastSyncedAt,
    ));
    Navigator.pop(context);
  }
}
