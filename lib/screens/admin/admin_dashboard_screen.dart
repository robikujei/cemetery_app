import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'admin_burial_records_screen.dart';
import 'admin_map_manager_screen.dart';
import 'admin_reports_screen.dart';

const _background = Color(0xFFFBF9F6);
const _surface = Color(0xFFFFFFFF);
const _surfaceContainerLow = Color(0xFFF5F3F0);
const _surfaceContainerHighest = Color(0xFFE4E2DF);
const _primary = Color(0xFF335538);
const _primaryContainer = Color(0xFF4B6E4F);
const _primaryFixed = Color(0xFFC5EDC6);
const _secondary = Color(0xFF47626F);
const _tertiary = Color(0xFF5A4B3F);
const _onSurface = Color(0xFF1B1C1A);
const _onSurfaceVariant = Color(0xFF424841);
const _outlineVariant = Color(0xFFC2C8BF);

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.onMenuPressed,
    this.onOpenBurialRecords,
    this.onOpenMapManager,
    this.onOpenReports,
  });

  final VoidCallback? onMenuPressed;
  final VoidCallback? onOpenBurialRecords;
  final VoidCallback? onOpenMapManager;
  final VoidCallback? onOpenReports;

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  Map<String, dynamic> _metrics = {
    'total_burials': 0,
    'available_lots': 0,
    'visitor_count': 0,
    'transactions': 0,
    'recent_activities': [],
  };

  // Chart data
  List<BarChartGroupData> _burialBarData = [];
  List<String> _burialYears = [];
  List<BarChartGroupData> _visitorBarData = [];
  List<String> _visitorMonths = [];
  Map<String, int> _blockDistribution = {};

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadMetrics(),
        _loadBurialTrend(),
        _loadVisitorTrend(),
        _loadBlockDistribution(),
      ]);

      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    await _loadAllData();
  }

  void _openBurialRecords() {
    if (widget.onOpenBurialRecords != null) {
      widget.onOpenBurialRecords!.call();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AdminBurialRecordsScreen(onMenuPressed: widget.onMenuPressed),
      ),
    );
  }

  void _openMapManager() {
    if (widget.onOpenMapManager != null) {
      widget.onOpenMapManager!.call();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AdminMapManagerScreen(onMenuPressed: widget.onMenuPressed),
      ),
    );
  }

  void _openReports() {
    if (widget.onOpenReports != null) {
      widget.onOpenReports!.call();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AdminReportsScreen()));
  }

  Future<void> _loadMetrics() async {
    final supabase = Supabase.instance.client;

    final burialsResult = await supabase
        .from('burial_record')
        .select('burial_id');
    final totalBurials = burialsResult.length;

    final lotsResult = await supabase
        .from('cemetery_lot')
        .select('lot_id')
        .eq('status', 'Available');
    final availableLots = lotsResult.length;

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final visitorsResult = await supabase
        .from('visitor_log')
        .select('log_id')
        .gte('time_in', '$today 00:00:00');
    final visitorCount = visitorsResult.length;

    final transactionsResult = await supabase
        .from('transaction_history')
        .select('transaction_id');
    final transactions = transactionsResult.length;

    final recentActivities = await supabase
        .from('visitor_log')
        .select('''
          log_id,
          time_in,
          user:user_id (name),
          burial:burial_id (name_of_deceased)
        ''')
        .order('time_in', ascending: false)
        .limit(5);

    setState(() {
      _metrics = {
        'total_burials': totalBurials,
        'available_lots': availableLots,
        'visitor_count': visitorCount,
        'transactions': transactions,
        'recent_activities': recentActivities,
      };
    });
  }

  Future<void> _loadBurialTrend() async {
    final supabase = Supabase.instance.client;

    try {
      final burials = await supabase.from('burial_record').select('death_date');

      print('📊 Total burial records: ${burials.length}');

      if (burials.isEmpty) {
        setState(() {
          _burialBarData = [];
          _burialYears = [];
        });
        return;
      }

      Map<int, int> yearlyCount = {};
      for (var burial in burials) {
        if (burial['death_date'] != null &&
            burial['death_date'].toString().isNotEmpty) {
          try {
            final year = DateTime.parse(burial['death_date']).year;
            yearlyCount[year] = (yearlyCount[year] ?? 0) + 1;
          } catch (e) {
            print('Error parsing death_date: ${burial['death_date']}');
          }
        }
      }

      final sortedYears = yearlyCount.keys.toList()..sort();
      final barData = <BarChartGroupData>[];
      final years = <String>[];

      for (int i = 0; i < sortedYears.length; i++) {
        final year = sortedYears[i];
        final count = yearlyCount[year] ?? 0;

        barData.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: const Color(0xFF4B6E4F),
                width: 40,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
        years.add(year.toString());

        print('📊 Year $year: $count burials');
      }

      setState(() {
        _burialBarData = barData;
        _burialYears = years;
      });
    } catch (e) {
      print('Error loading burial trend: $e');
      setState(() {
        _burialBarData = [];
        _burialYears = [];
      });
    }
  }

  Future<void> _loadVisitorTrend() async {
    final supabase = Supabase.instance.client;

    try {
      final visitors = await supabase.from('visitor_log').select('time_in');

      print('📊 Total visitor logs: ${visitors.length}');

      if (visitors.isEmpty) {
        setState(() {
          _visitorBarData = [];
          _visitorMonths = [];
        });
        return;
      }

      Map<String, Map<String, dynamic>> monthData = {};

      for (var visitor in visitors) {
        final timeIn = visitor['time_in'];
        if (timeIn != null && timeIn.toString().isNotEmpty) {
          try {
            final date = DateTime.parse(timeIn.toString());
            final yearMonth = DateFormat('yyyy-MM').format(date);
            final monthLabel = DateFormat('MMM y').format(date);

            if (!monthData.containsKey(yearMonth)) {
              monthData[yearMonth] = {
                'label': monthLabel,
                'count': 0,
                'date': date,
              };
            }
            monthData[yearMonth]!['count'] = monthData[yearMonth]!['count'] + 1;
          } catch (e) {
            print('Error parsing date: $timeIn');
          }
        }
      }

      final sortedKeys = monthData.keys.toList()..sort();
      final barData = <BarChartGroupData>[];
      final months = <String>[];

      for (int i = 0; i < sortedKeys.length; i++) {
        final key = sortedKeys[i];
        final data = monthData[key]!;
        final count = data['count'] as int;

        barData.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: Colors.blue,
                width: 40,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
        months.add(data['label'] as String);

        print('📊 ${data['label']}: $count visits');
      }

      setState(() {
        _visitorBarData = barData;
        _visitorMonths = months;
      });
    } catch (e) {
      print('Error loading visitor trend: $e');
      setState(() {
        _visitorBarData = [];
        _visitorMonths = [];
      });
    }
  }

  Future<void> _loadBlockDistribution() async {
    final supabase = Supabase.instance.client;

    try {
      final lots = await supabase.from('cemetery_lot').select('''
            block_number,
            burial_record (burial_id)
          ''');

      Map<String, int> distribution = {};
      for (var lot in lots) {
        final blockNumber = lot['block_number']?.toString().trim();
        final blockName = blockNumber == null || blockNumber.isEmpty
            ? 'Unassigned Block'
            : 'Block $blockNumber';
        final burials = lot['burial_record'] as List? ?? [];
        final burialCount = burials.length;
        if (burialCount > 0) {
          distribution[blockName] =
              (distribution[blockName] ?? 0) + burialCount;
        }
      }

      setState(() {
        _blockDistribution = distribution;
      });
    } catch (e) {
      print('Error loading block distribution: $e');
      setState(() {
        _blockDistribution = {};
      });
    }
  }

  String _formatDate(String? dateTimeString) {
    if (dateTimeString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateTimeString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final metricColumns = width < 520 ? 2 : (width < 1100 ? 2 : 4);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    return Scaffold(
      backgroundColor: _background,
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Welcome back, Administrator. Here is the daily summary for your operations.',
                style: t.bodyMedium?.copyWith(color: const Color(0xFF424841)),
              ),
              const SizedBox(height: 28),
              GridView.count(
                crossAxisCount: metricColumns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: width < 520 ? 1.15 : 1.65,
                children: [
                  _MetricCard(
                    label: 'Total Burials',
                    value: _metrics['total_burials'].toString(),
                    icon: Icons.people_outline,
                    color: const Color(0xFF335538),
                    badge: 'All records',
                  ),
                  _MetricCard(
                    label: 'Available Lots',
                    value: _metrics['available_lots'].toString(),
                    icon: Icons.grid_view_rounded,
                    color: _secondary,
                    badge: 'Open plots',
                  ),
                  _MetricCard(
                    label: 'Visitors Today',
                    value: _metrics['visitor_count'].toString(),
                    icon: Icons.groups_outlined,
                    color: _tertiary,
                    badge: 'Live count',
                  ),
                  _MetricCard(
                    label: 'Total Transactions',
                    value: _metrics['transactions'].toString(),
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF2F6F50),
                    badge: 'History',
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: _buildQuickActions(t)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildMapPreview(t)),
                  ],
                )
              else ...[
                _buildQuickActions(t),
                const SizedBox(height: 24),
                _buildMapPreview(t),
              ],
              const SizedBox(height: 24),
              _buildChartsSection(t, cs),
              const SizedBox(height: 24),
              _buildRecentActivitySection(t, cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(TextTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Quick Actions',
          style: t.titleLarge?.copyWith(
            color: const Color(0xFF1B1C1A),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        _QuickActionButton(
          label: 'Add Burial Record',
          icon: Icons.person_add_alt_1,
          filled: true,
          onPressed: _openBurialRecords,
        ),
        const SizedBox(height: 12),
        _QuickActionButton(
          label: 'Map Cemetery',
          icon: Icons.map_outlined,
          onPressed: _openMapManager,
        ),
        const SizedBox(height: 12),
        _QuickActionButton(
          label: 'View Reports',
          icon: Icons.assessment_outlined,
          onPressed: _openReports,
        ),
      ],
    );
  }

  Widget _buildMapPreview(TextTheme t) {
    return _MapPreviewCard(
      titleStyle: t.titleLarge?.copyWith(
        color: _onSurface,
        fontWeight: FontWeight.w700,
      ),
      pillStyle: t.labelMedium?.copyWith(
        color: _onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildChartsSection(TextTheme t, ColorScheme cs) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Analytics',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (_isRefreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Burial Trend Bar Chart
            Text('Burial Trends (Yearly)', style: t.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: _burialBarData.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.show_chart,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No burial data available',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _refreshData,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reload Data'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4B6E4F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getMaxYFromBarData(_burialBarData),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toInt().toString(),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index >= 0 && index < _burialYears.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _burialYears[index],
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        barGroups: _burialBarData,
                        gridData: const FlGridData(show: true),
                      ),
                    ),
            ),
            const SizedBox(height: 24),

            // Visitor Trend Bar Chart
            Text('Visitor Trends (Monthly)', style: t.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 250,
              child: _visitorBarData.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No visitor data available',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Visitor logs will appear here when available',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _refreshData,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reload Data'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _getMaxYFromBarData(_visitorBarData),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.toInt().toString(),
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 80,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index >= 0 &&
                                    index < _visitorMonths.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Transform.rotate(
                                      angle: -0.3,
                                      child: Text(
                                        _visitorMonths[index],
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        barGroups: _visitorBarData,
                        gridData: const FlGridData(show: true),
                      ),
                    ),
            ),
            const SizedBox(height: 24),

            // Block Distribution Pie Chart
            if (_blockDistribution.isNotEmpty)
              Column(
                children: [
                  Text('Burial Distribution by Block', style: t.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 300,
                    child: PieChart(
                      PieChartData(
                        sections: _buildPieSections(),
                        centerSpaceRadius: 60,
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: _buildLegendItems(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  double _getMaxYFromBarData(List<BarChartGroupData> barData) {
    if (barData.isEmpty) return 10;
    double maxY = 0;
    for (var group in barData) {
      for (var rod in group.barRods) {
        if (rod.toY > maxY) maxY = rod.toY;
      }
    }
    return maxY == 0 ? 10 : maxY + (maxY * 0.15);
  }

  List<Widget> _buildLegendItems() {
    final colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.brown,
    ];
    final total = _blockDistribution.values.fold(
      0,
      (sum, count) => sum + count,
    );

    if (total == 0) return [const Text('No data available')];

    return _blockDistribution.entries.map((entry) {
      final index = _blockDistribution.keys.toList().indexOf(entry.key);
      final percentage = (entry.value / total * 100).toStringAsFixed(1);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: colors[index % colors.length],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${entry.key} ($percentage%)',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }).toList();
  }

  List<PieChartSectionData> _buildPieSections() {
    final colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.brown,
    ];
    final total = _blockDistribution.values.fold(
      0,
      (sum, count) => sum + count,
    );

    if (total == 0) return [];

    return _blockDistribution.entries.map((entry) {
      final index = _blockDistribution.keys.toList().indexOf(entry.key);
      final percentage = (entry.value / total * 100);

      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: percentage >= 10 ? '${percentage.toStringAsFixed(1)}%' : '',
        color: colors[index % colors.length],
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        showTitle: percentage >= 10,
      );
    }).toList();
  }

  Widget _buildRecentActivitySection(TextTheme t, ColorScheme cs) {
    final activities = _metrics['recent_activities'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Records',
              style: t.titleLarge?.copyWith(
                color: _onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton.icon(
              onPressed: _refreshData,
              iconAlignment: IconAlignment.end,
              label: const Text('View all'),
              icon: const Icon(Icons.chevron_right, size: 18),
              style: TextButton.styleFrom(foregroundColor: _primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (activities.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No recent activity',
                  style: t.bodyMedium?.copyWith(color: _onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Visitor logs will appear here when visitors scan QR codes',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...activities.map((activity) {
            final user = activity['user'] as Map? ?? {};
            final burial = activity['burial'] as Map? ?? {};
            final timeIn = _formatDate(activity['time_in']);
            final visitorName = user['name'] ?? 'Unknown Visitor';
            final graveName = burial['name_of_deceased'];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: _primaryFixed,
                      child: Icon(
                        Icons.account_circle_outlined,
                        color: _primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visitorName.toString(),
                            style: t.bodyLarge?.copyWith(
                              color: _onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            graveName != null
                                ? 'Visited: $graveName - $timeIn'
                                : 'Visit recorded - $timeIn',
                            style: t.labelSmall?.copyWith(
                              color: _onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.chevron_right,
                      color: _onSurfaceVariant.withValues(alpha: 0.65),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Scaffold(
      backgroundColor: _background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B6E4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.badge,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: _primaryContainer.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              Flexible(
                child: Text(
                  badge,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: t.labelLarge?.copyWith(
                  color: _onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: t.headlineSmall?.copyWith(
                  color: _onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : _onSurfaceVariant;
    return Material(
      color: filled ? _primary : _surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      elevation: filled ? 3 : 0,
      shadowColor: _primary.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 25),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: _primaryContainer.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MapPreviewCard extends StatefulWidget {
  const _MapPreviewCard({this.titleStyle, this.pillStyle});

  final TextStyle? titleStyle;
  final TextStyle? pillStyle;

  @override
  State<_MapPreviewCard> createState() => _MapPreviewCardState();
}

class _DbscanPoint {
  _DbscanPoint({
    required this.marker,
    required this.x,
    required this.y,
    required this.visitCount,
  });

  final Map<String, dynamic> marker;
  final double x;
  final double y;
  final int visitCount;

  int clusterId = 0;
}

class _DbscanCluster {
  const _DbscanCluster({required this.id, required this.points});

  final int id;
  final List<_DbscanPoint> points;
}

class _DbscanResult {
  const _DbscanResult({required this.clusters, required this.noise});

  final List<_DbscanCluster> clusters;
  final List<_DbscanPoint> noise;
}

class _MapPreviewCardState extends State<_MapPreviewCard> {
  static final LatLng _tagumMapCenter = LatLng(7.3793125, 125.753328125);
  static const double _initialZoom = 18;
  static const double _mapLatSpan = 0.0036;
  static const double _mapLngSpan = 0.0046;

  final MapController _mapController = MapController();

  bool _isLoading = true;
  String? _errorMessage;
  double? _entranceXPercent;
  double? _entranceYPercent;
  LatLng _mapCenter = _tagumMapCenter;
  double _activeMapLatSpan = _mapLatSpan;
  double _activeMapLngSpan = _mapLngSpan;
  double _currentZoom = _initialZoom;
  LatLng _currentCenter = _tagumMapCenter;
  List<Map<String, dynamic>> _lotMarkers = [];
  Map<int, int> _lotVisitCounts = {};
  static const double _dbscanEpsilon = 0.075;
  static const int _dbscanMinWeight = 4;

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase
            .from('cemetery_map')
            .select(
              'entrance_x_percent, entrance_y_percent, center_lat, center_lng, lat_span, lng_span',
            )
            .order('uploaded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        supabase
            .from('lot_markers')
            .select(
              'marker_id, lot_id, x_percent, y_percent, cemetery_lot(lot_id, lot_number, block_number, price, status)',
            )
            .order('marker_id'),
        supabase
            .from('visitor_log')
            .select('burial:burial_id (burial_id, lot_id)')
            .order('log_id'),
      ]);

      if (!mounted) return;
      setState(() {
        final mapConfig = results[0] as Map<String, dynamic>?;
        final centerLat = (mapConfig?['center_lat'] as num?)?.toDouble();
        final centerLng = (mapConfig?['center_lng'] as num?)?.toDouble();
        if (centerLat != null && centerLng != null) {
          _mapCenter = LatLng(centerLat, centerLng);
          _currentCenter = _mapCenter;
        }
        _activeMapLatSpan =
            (mapConfig?['lat_span'] as num?)?.toDouble() ?? _mapLatSpan;
        _activeMapLngSpan =
            (mapConfig?['lng_span'] as num?)?.toDouble() ?? _mapLngSpan;
        _entranceXPercent = (mapConfig?['entrance_x_percent'] as num?)
            ?.toDouble();
        _entranceYPercent = (mapConfig?['entrance_y_percent'] as num?)
            ?.toDouble();
        _lotMarkers = List<Map<String, dynamic>>.from(results[1] as List);
        _lotVisitCounts = _buildVisitCounts(results[2] as List);
        _mergeVisitCountsIntoMarkers();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load map data: $e';
        _isLoading = false;
      });
    }
  }

  Map<int, int> _buildVisitCounts(List<dynamic> rows) {
    final counts = <int, int>{};
    for (final row in rows) {
      final burial = row['burial'] as Map<String, dynamic>?;
      final lotId = burial?['lot_id'];
      if (lotId is int) {
        counts[lotId] = (counts[lotId] ?? 0) + 1;
      } else if (lotId is num) {
        final id = lotId.toInt();
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return counts;
  }

  void _mergeVisitCountsIntoMarkers() {
    _lotMarkers = _lotMarkers.map((marker) {
      final normalizedMarker = Map<String, dynamic>.from(marker);
      final lot = Map<String, dynamic>.from(
        normalizedMarker['cemetery_lot'] ?? {},
      );
      final lotId = lot['lot_id'];
      final id = lotId is int
          ? lotId
          : lotId is num
          ? lotId.toInt()
          : null;
      lot['visit_count'] = id == null ? 0 : (_lotVisitCounts[id] ?? 0);
      normalizedMarker['cemetery_lot'] = lot;
      return normalizedMarker;
    }).toList();
  }

  LatLng get _entranceLatLng {
    final x = _entranceXPercent ?? 0.5;
    final y = _entranceYPercent ?? 0.5;
    return _percentToLatLng(x, y);
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _activeMapLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _activeMapLngSpan;
    final lat = _mapCenter.latitude + latOffset;
    final lng = _mapCenter.longitude + lngOffset;
    return LatLng(lat, lng);
  }

  List<_DbscanPoint> _dbscanPoints() {
    return _lotMarkers.map((marker) {
      final lot = marker['cemetery_lot'] ?? {};
      final x = (marker['x_percent'] as num?)?.toDouble() ?? 0.5;
      final y = (marker['y_percent'] as num?)?.toDouble() ?? 0.5;
      final visitCount = (lot['visit_count'] as num?)?.toInt() ?? 0;
      return _DbscanPoint(marker: marker, x: x, y: y, visitCount: visitCount);
    }).toList();
  }

  _DbscanResult _clusterHeatmap() {
    final points = _dbscanPoints();
    final clusters = <_DbscanCluster>[];
    final noise = <_DbscanPoint>[];
    var clusterId = 0;

    List<_DbscanPoint> regionQuery(_DbscanPoint point) {
      return points.where((other) {
        final dx = point.x - other.x;
        final dy = point.y - other.y;
        return sqrt(dx * dx + dy * dy) <= _dbscanEpsilon;
      }).toList();
    }

    int neighborhoodWeight(List<_DbscanPoint> items) {
      return items.fold<int>(0, (sum, item) => sum + item.visitCount);
    }

    void expandCluster(
      _DbscanPoint point,
      List<_DbscanPoint> neighbors,
      int id,
    ) {
      final clusterPoints = <_DbscanPoint>[];
      point.clusterId = id;
      clusterPoints.add(point);

      final queue = List<_DbscanPoint>.from(neighbors);
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        if (current.clusterId == -1) {
          current.clusterId = id;
        }
        if (current.clusterId != 0) continue;
        current.clusterId = id;
        clusterPoints.add(current);

        final currentNeighbors = regionQuery(current);
        if (neighborhoodWeight(currentNeighbors) >= _dbscanMinWeight) {
          for (final neighbor in currentNeighbors) {
            if (!queue.contains(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }

      clusters.add(_DbscanCluster(id: id, points: clusterPoints));
    }

    for (final point in points) {
      if (point.clusterId != 0) continue;
      final neighbors = regionQuery(point);
      if (neighborhoodWeight(neighbors) < _dbscanMinWeight) {
        point.clusterId = -1;
        noise.add(point);
        continue;
      }
      clusterId++;
      expandCluster(point, neighbors, clusterId);
    }

    return _DbscanResult(clusters: clusters, noise: noise);
  }

  List<CircleMarker> _heatCircles(_DbscanResult result) {
    final circles = <CircleMarker>[];

    for (final noisePoint in result.noise) {
      final weight = noisePoint.visitCount;
      if (weight <= 0) continue;
      circles.add(
        CircleMarker(
          point: _percentToLatLng(noisePoint.x, noisePoint.y),
          radius: (8 + weight * 2.2).clamp(8.0, 30.0),
          color: const Color(0xFF8ABF92).withValues(alpha: 0.14),
          borderColor: const Color(0xFF6D9F75).withValues(alpha: 0.28),
          borderStrokeWidth: 1.25,
          useRadiusInMeter: false,
        ),
      );
    }

    for (final cluster in result.clusters) {
      final visitCount = cluster.points.fold<int>(
        0,
        (sum, point) => sum + point.visitCount,
      );
      if (visitCount <= 0) continue;
      final centerX =
          cluster.points.fold<double>(0, (sum, p) => sum + p.x) /
          cluster.points.length;
      final centerY =
          cluster.points.fold<double>(0, (sum, p) => sum + p.y) /
          cluster.points.length;
      final intensity = (visitCount / 24).clamp(0.0, 1.0);
      final color = Color.lerp(_primaryFixed, _primaryContainer, intensity)!;
      final radius = (18 + visitCount * 1.6).clamp(22.0, 72.0);

      circles.add(
        CircleMarker(
          point: _percentToLatLng(centerX, centerY),
          radius: radius,
          color: color.withValues(alpha: 0.20 + intensity * 0.26),
          borderColor: color.withValues(alpha: 0.55),
          borderStrokeWidth: 2,
          useRadiusInMeter: false,
        ),
      );
    }

    return circles;
  }

  Marker _entranceMarker() {
    return Marker(
      point: _entranceLatLng,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: _primary.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: _primary, width: 2),
        ),
        child: const Icon(Icons.place_rounded, size: 14, color: _primary),
      ),
    );
  }

  List<Marker> _clusterMarkers(_DbscanResult result) {
    return result.clusters.map((cluster) {
      final count = cluster.points.fold<int>(
        0,
        (sum, point) => sum + point.visitCount,
      );
      final centerX =
          cluster.points.fold<double>(0, (sum, p) => sum + p.x) /
          cluster.points.length;
      final centerY =
          cluster.points.fold<double>(0, (sum, p) => sum + p.y) /
          cluster.points.length;
      return Marker(
        point: _percentToLatLng(centerX, centerY),
        width: 42,
        height: 42,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: _primary.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x25000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: _primary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }).toList();
  }

  int get _occupiedLots => _lotMarkers.where((marker) {
    final lot = marker['cemetery_lot'] ?? {};
    return ((lot['visit_count'] as num?)?.toInt() ?? 0) > 0;
  }).length;

  int get _totalVisits => _lotMarkers.fold<int>(0, (sum, marker) {
    final lot = marker['cemetery_lot'] ?? {};
    return sum + ((lot['visit_count'] as num?)?.toInt() ?? 0);
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        widget.titleStyle ?? Theme.of(context).textTheme.titleLarge;
    final pillStyle =
        widget.pillStyle ?? Theme.of(context).textTheme.labelMedium;
    final heatmap = _clusterHeatmap();

    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFC2C8BF).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B6E4F).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_errorMessage!, textAlign: TextAlign.center),
                    ),
                  )
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: _initialZoom,
                      minZoom: 14,
                      maxZoom: 20,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onPositionChanged: (position, _) {
                        _currentZoom = position.zoom;
                        _currentCenter = position.center;
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.cemetery_app',
                        maxZoom: 20,
                      ),
                      CircleLayer(circles: _heatCircles(heatmap)),
                      MarkerLayer(
                        markers: [
                          _entranceMarker(),
                          ..._clusterMarkers(heatmap),
                        ],
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFFC2C8BF).withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Visitor Heatmap',
                    style: pillStyle?.copyWith(color: _onSurface),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFC2C8BF).withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                'Visits $_totalVisits - Hotspots ${heatmap.clusters.length} - Noise ${heatmap.noise.length} - Active lots $_occupiedLots',
                style: titleStyle?.copyWith(
                  color: _onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: Column(
              children: [
                _MapToolButton(
                  icon: Icons.add,
                  onPressed: () => _mapController.move(
                    _currentCenter,
                    (_currentZoom + 1).clamp(14, 20),
                  ),
                ),
                const SizedBox(height: 8),
                _MapToolButton(
                  icon: Icons.remove,
                  onPressed: () => _mapController.move(
                    _currentCenter,
                    (_currentZoom - 1).clamp(14, 20),
                  ),
                ),
                const SizedBox(height: 8),
                _MapToolButton(
                  icon: Icons.my_location_outlined,
                  onPressed: () =>
                      _mapController.move(_mapCenter, _initialZoom),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapToolButton extends StatelessWidget {
  const _MapToolButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: _primary),
        ),
      ),
    );
  }
}
