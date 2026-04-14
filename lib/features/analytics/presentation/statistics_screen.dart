import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/analytics_service.dart';
import '../domain/daily_stats.dart';
import 'utils/format_helpers.dart';
import 'widgets/category_pie_chart.dart';
import 'widgets/download_timeline_chart.dart';
import 'widgets/stats_card.dart';

/// Statistics screen showing download analytics
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedDays = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analytics = ref.watch(analyticsServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Statistics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Time range',
            onSelected: (days) => setState(() => _selectedDays = days),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 7,
                child: Row(
                  children: [
                    if (_selectedDays == 7)
                      const Icon(Icons.check_rounded, size: 18),
                    if (_selectedDays == 7) const SizedBox(width: 8),
                    const Text('Last 7 days'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 30,
                child: Row(
                  children: [
                    if (_selectedDays == 30)
                      const Icon(Icons.check_rounded, size: 18),
                    if (_selectedDays == 30) const SizedBox(width: 8),
                    const Text('Last 30 days'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 90,
                child: Row(
                  children: [
                    if (_selectedDays == 90)
                      const Icon(Icons.check_rounded, size: 18),
                    if (_selectedDays == 90) const SizedBox(width: 8),
                    const Text('Last 90 days'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: 'Export data',
            onPressed: () => _showExportDialog(context, analytics),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF2AABEE),
          labelColor: const Color(0xFF2AABEE),
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Timeline'),
            Tab(text: 'Categories'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(analytics: analytics, days: _selectedDays),
          _TimelineTab(analytics: analytics, days: _selectedDays),
          _CategoriesTab(analytics: analytics),
        ],
      ),
    );
  }

  Future<void> _showExportDialog(
      BuildContext context, AnalyticsService analytics) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportData(analytics, 'csv');
            },
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportData(analytics, 'json');
            },
            child: const Text('JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData(AnalyticsService analytics, String format) async {
    try {
      final stats = await analytics.db.getDailyStats();

      if (stats.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tesseract_stats_$timestamp.$format';
      final file = File('${dir.path}/$fileName');

      if (format == 'csv') {
        final csv = const ListToCsvConverter().convert([
          ['Date', 'Downloads', 'Bytes', 'Failed', 'Success Rate'],
          ...stats.map((s) => [
                s.date,
                s.totalDownloads,
                s.totalBytes,
                s.failedDownloads,
                s.successRate.toStringAsFixed(1),
              ]),
        ]);
        await file.writeAsString(csv);
      } else {
        final json = jsonEncode(stats.map((s) => s.toMap()).toList());
        await file.writeAsString(json);
      }

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'Tesseract Download Statistics',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}

// ── Overview Tab ──────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.analytics, required this.days});

  final AnalyticsService analytics;
  final int days;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: analytics.db.getTotalStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final stats = snapshot.data!;
        final totalDownloads = stats['totalDownloads'] as int;
        final completedDownloads = stats['completedDownloads'] as int;
        final failedDownloads = stats['failedDownloads'] as int;
        final totalBytes = stats['totalBytes'] as int;
        final successRate = stats['successRate'] as String;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Total downloads
            StatsCard(
              title: 'Total Downloads',
              value: formatNumber(totalDownloads),
              subtitle: 'All time',
              icon: Icons.download_rounded,
              color: const Color(0xFF2AABEE),
            ),
            const SizedBox(height: 12),

            // Grid of stats
            Row(
              children: [
                Expanded(
                  child: StatsCard(
                    title: 'Completed',
                    value: formatNumber(completedDownloads),
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF66BB6A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatsCard(
                    title: 'Failed',
                    value: formatNumber(failedDownloads),
                    icon: Icons.error_rounded,
                    color: const Color(0xFFEF5350),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: StatsCard(
                    title: 'Total Data',
                    value: formatBytes(totalBytes),
                    icon: Icons.storage_rounded,
                    color: const Color(0xFFAB47BC),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatsCard(
                    title: 'Success Rate',
                    value: '$successRate%',
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF26A69A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Top channels
            FutureBuilder<List<Map<String, dynamic>>>(
              future: analytics.db.getTopChannels(limit: 5),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox();
                }

                return Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFFFAB00), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Top Channels',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ...snapshot.data!.map((channel) {
                          final channelId = channel['channel_id'] as int;
                          final count = channel['download_count'] as int;
                          final bytes = channel['total_bytes'] as int;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2AABEE)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.tag_rounded,
                                    size: 16,
                                    color: Color(0xFF2AABEE),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Channel $channelId',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        '$count downloads · ${formatBytes(bytes)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ── Timeline Tab ──────────────────────────────────────────────────

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.analytics, required this.days});

  final AnalyticsService analytics;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<DailyStats>>(
      future: analytics.db.getDownloadTimeline(days: days),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final stats = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Download Activity',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 250,
                    child: DownloadTimelineChart(stats: stats),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Categories Tab ────────────────────────────────────────────────

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.analytics});

  final AnalyticsService analytics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: analytics.db.getDownloadsByCategory(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categoryData = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Downloads by Category',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 300,
                    child: CategoryPieChart(categoryData: categoryData),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
