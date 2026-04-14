import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/format_helpers.dart';

/// Pie chart showing downloads by category
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({
    super.key,
    required this.categoryData,
  });

  final List<Map<String, dynamic>> categoryData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (categoryData.isEmpty) {
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

    final total = categoryData.fold<int>(
      0,
      (sum, item) => sum + (item['count'] as int),
    );

    final colors = [
      const Color(0xFF2AABEE), // Videos
      const Color(0xFF66BB6A), // Audio
      const Color(0xFFFFAB00), // Photos
      const Color(0xFFEF5350), // Documents
      const Color(0xFFAB47BC), // Archives
      const Color(0xFF26A69A), // Apps
      const Color(0xFF78909C), // Other
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Pie chart
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 1,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: categoryData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final count = item['count'] as int;
                    final percentage = (count / total * 100);

                    return PieChartSectionData(
                      color: colors[index % colors.length],
                      value: count.toDouble(),
                      title: '${percentage.toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Legend
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: categoryData.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final category = item['category'] as String? ?? 'Unknown';
                final count = item['count'] as int;
                final bytes = item['total_bytes'] as int;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '$count files · ${formatBytes(bytes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
