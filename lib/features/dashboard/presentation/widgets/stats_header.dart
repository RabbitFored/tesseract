import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../downloader/domain/download_provider.dart';
import '../utils/display_helpers.dart';

/// Compact stats header card showing active downloads, overall progress,
/// global speed, and a sparkline chart of speed history.
class StatsHeader extends ConsumerWidget {
  const StatsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(downloadStatsProvider);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: title + speed + percentage ──────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloads',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stats.globalSpeed > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.speed_rounded,
                              size: 12,
                              color: Color(0xFF00E676),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatSpeed(stats.globalSpeed),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00E676),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (stats.active > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2AABEE)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${(stats.overallProgress * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFF2AABEE),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // ── Sparkline graph ─────────────────────────────
            if (stats.speedHistory.isNotEmpty &&
                stats.speedHistory.any((s) => s > 0)) ...[
              const SizedBox(height: 12),
              RepaintBoundary(
                child: _SpeedSparkline(speedHistory: stats.speedHistory),
              ),
            ],

            // ── Progress bar ────────────────────────────────
            if (stats.active > 0 || stats.queued > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stats.overallProgress,
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF2AABEE)),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // ── Stat chips row ──────────────────────────────
            Row(
              children: [
                _StatChip(
                  icon: Icons.downloading_rounded,
                  label: '${stats.active}',
                  caption: 'Active',
                  color: const Color(0xFF2AABEE),
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.hourglass_top_rounded,
                  label: '${stats.queued}',
                  caption: 'Queued',
                  color: const Color(0xFF78909C),
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.pause_circle_rounded,
                  label: '${stats.paused}',
                  caption: 'Paused',
                  color: const Color(0xFFFFAB00),
                ),
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.check_circle_rounded,
                  label: '${stats.completed}',
                  caption: 'Done',
                  color: const Color(0xFF00E676),
                ),
              ],
            ),

            // ── Bytes progress (when active) ────────────────
            if (stats.active > 0) ...[
              const SizedBox(height: 10),
              Text(
                '${formatBytes(stats.downloadedBytes)} of ${formatBytes(stats.totalBytes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sparkline widget (isolated in RepaintBoundary) ──────────────

class _SpeedSparkline extends StatelessWidget {
  const _SpeedSparkline({required this.speedHistory});
  final List<int> speedHistory;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < speedHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), speedHistory[i].toDouble()));
    }

    final maxY = speedHistory.fold<int>(0, math.max).toDouble();

    return SizedBox(
      height: 40,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY > 0 ? maxY * 1.15 : 1,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: const Color(0xFF2AABEE),
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF2AABEE).withValues(alpha: 0.2),
                    const Color(0xFF2AABEE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 150),
      ),
    );
  }
}

// ── Stat chip ───────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              caption,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
