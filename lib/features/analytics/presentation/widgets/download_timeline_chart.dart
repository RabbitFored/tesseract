import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/daily_stats.dart';
import '../utils/format_helpers.dart';

/// Line chart showing download activity over time
class DownloadTimelineChart extends StatelessWidget {
  const DownloadTimelineChart({
    super.key,
    required this.stats,
  });

  final List<DailyStats> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (stats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No data available',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final spots = stats.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.totalDownloads.toDouble(),
      );
    }).toList();

    final maxY = stats.map((s) => s.totalDownloads).reduce((a, b) => a > b ? a : b).toDouble();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 5 : 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: stats.length > 10 ? (stats.length / 5).ceilToDouble() : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= stats.length) return const SizedBox();

                  final date = DateTime.parse(stats[index].date);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formatDateShort(date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxY > 0 ? maxY / 5 : 1,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (stats.length - 1).toDouble(),
          minY: 0,
          maxY: maxY * 1.2,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF2AABEE),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: stats.length <= 10,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: const Color(0xFF2AABEE),
                    strokeWidth: 2,
                    strokeColor: theme.colorScheme.surface,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF2AABEE).withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.x.toInt();
                  if (index < 0 || index >= stats.length) return null;

                  final stat = stats[index];
                  final date = DateTime.parse(stat.date);

                  return LineTooltipItem(
                    '${formatDateShort(date)}\n${stat.totalDownloads} downloads',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
