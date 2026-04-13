import 'package:flutter/material.dart';

import '../../data/settings_controller.dart';
import '../../domain/settings_state.dart';

/// Bottom sheet for configuring the download schedule window.
class ScheduleSettingsSheet extends StatefulWidget {
  const ScheduleSettingsSheet({
    super.key,
    required this.settings,
    required this.controller,
  });

  final SettingsState settings;
  final SettingsController controller;

  @override
  State<ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<ScheduleSettingsSheet> {
  late bool _enabled;
  late double _start;
  late double _end;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.downloadOnlyOnSchedule;
    _start = widget.settings.scheduleStartHour.toDouble();
    _end = widget.settings.scheduleEndHour.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Download Schedule',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Restrict downloads to a specific time window. '
              'Useful for off-peak hours or overnight downloads.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Enable Schedule'),
              value: _enabled,
              activeTrackColor: const Color(0xFF2AABEE).withValues(alpha: 0.5),
              activeThumbColor: const Color(0xFF2AABEE),
              onChanged: (v) => setState(() => _enabled = v),
              contentPadding: EdgeInsets.zero,
            ),

            if (_enabled) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start time', style: theme.textTheme.bodyMedium),
                  Text(
                    _fmtHour(_start.round()),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF2AABEE),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _start,
                min: 0,
                max: 23,
                divisions: 23,
                label: _fmtHour(_start.round()),
                activeColor: const Color(0xFF2AABEE),
                onChanged: (v) => setState(() => _start = v),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('End time', style: theme.textTheme.bodyMedium),
                  Text(
                    _fmtHour(_end.round()),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF2AABEE),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _end,
                min: 0,
                max: 23,
                divisions: 23,
                label: _fmtHour(_end.round()),
                activeColor: const Color(0xFF2AABEE),
                onChanged: (v) => setState(() => _end = v),
              ),
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.08),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: Color(0xFF2AABEE)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Downloads will only run between '
                          '${_fmtHour(_start.round())} and '
                          '${_fmtHour(_end.round())}. '
                          'Overnight windows (e.g. 22:00–06:00) are supported.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    await widget.controller.setDownloadOnlyOnSchedule(_enabled);
    await widget.controller.setScheduleWindow(
      _start.round(),
      _end.round(),
    );
    if (mounted) Navigator.pop(context);
  }

  static String _fmtHour(int h) =>
      '${h.toString().padLeft(2, '0')}:00';
}
