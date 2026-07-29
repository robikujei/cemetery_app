import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/lot_formatters.dart';
import '../../utils/csv_download.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic> _metrics = {'recent_activities': []};
  Map<String, int> _blockDistribution = {};
  Map<String, dynamic> _summary = {
    'total_burials': 0,
    'total_lots': 0,
    'available_lots': 0,
    'occupied_lots': 0,
    'total_visitors': 0,
    'qr_scans': 0,
    'revenue': 0,
  };
  String _selectedReportType = 'burials';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final burials = await supabase.from('burial_record').select('burial_id');
      final lots = await supabase.from('cemetery_lot').select('''
            lot_id,
            status,
            price,
            block_number,
            burial_record (burial_id)
          ''');
      final availableLots = lots
          .where((l) => l['status'] == 'Available')
          .length;
      final occupiedLots = lots.where((l) => l['status'] == 'Occupied').length;

      double revenue = 0;
      for (final lot in lots) {
        if (lot['status'] == 'Occupied' && lot['price'] != null) {
          revenue += (lot['price'] as num).toDouble();
        }
      }

      final visitors = await supabase
          .from('visitor_log')
          .select('log_id, method');
      final qrScans = visitors.where((v) => v['method'] == 'QR').length;
      final recentActivities = await supabase
          .from('visitor_log')
          .select('''
            log_id,
            time_in,
            method,
            user:user_id (name),
            burial:burial_id (name_of_deceased)
          ''')
          .order('time_in', ascending: false)
          .limit(5);

      final blockDistribution = <String, int>{};
      for (final lot in lots) {
        final blockNumber = lot['block_number']?.toString().trim();
        final blockName = blockNumber == null || blockNumber.isEmpty
            ? 'Unassigned Block'
            : 'Block $blockNumber';
        final burialsInLot = lot['burial_record'] as List? ?? [];
        final burialCount = burialsInLot.length;
        if (burialCount > 0) {
          blockDistribution[blockName] =
              (blockDistribution[blockName] ?? 0) + burialCount;
        }
      }

      setState(() {
        _summary = {
          'total_burials': burials.length,
          'total_lots': lots.length,
          'available_lots': availableLots,
          'occupied_lots': occupiedLots,
          'total_visitors': visitors.length,
          'qr_scans': qrScans,
          'revenue': revenue,
        };
        _metrics = {'recent_activities': recentActivities};
        _blockDistribution = blockDistribution;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading summary: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _exportReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      List<Map<String, dynamic>> data = [];
      String fileName = '';
      String csvContent = '';

      switch (_selectedReportType) {
        case 'burials':
          var query = supabase.from('burial_record').select('''
                burial_id,
                name_of_deceased,
                birth_date,
                death_date,
                burial_date,
                cemetery_lot (
                  lot_number,
                  lot_label,
                  block_number
                )
              ''');

          if (_startDate != null) {
            query = query.gte('death_date', _startDate!.toIso8601String());
          }
          if (_endDate != null) {
            query = query.lte('death_date', _endDate!.toIso8601String());
          }

          final records = await query;
          data = List<Map<String, dynamic>>.from(records);
          fileName =
              'burial_records_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          csvContent =
              'ID,Name of Deceased,Birth Date,Death Date,Burial Date,Lot Number,Block\n';
          for (final record in data) {
            final lot = record['cemetery_lot'] ?? {};
            csvContent += '"${record['burial_id']}",';
            csvContent += '"${record['name_of_deceased']}",';
            csvContent += '"${record['birth_date'] ?? ''}",';
            csvContent += '"${record['death_date'] ?? ''}",';
            csvContent += '"${record['burial_date'] ?? ''}",';
            csvContent += '"${lotReference(lot, fallback: '')}",';
            csvContent += '"${lotBlockLabel(lot, fallback: '')}"\n';
          }
          break;
        case 'lots':
          final lots = await supabase.from('cemetery_lot').select('''
                lot_id,
                lot_number,
                lot_label,
                block_number,
                status,
                price,
                x_coord,
                y_coord
              ''');
          data = List<Map<String, dynamic>>.from(lots);
          fileName =
              'lot_inventory_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          csvContent =
              'ID,Lot Number,Block,Status,Price,X Coordinate,Y Coordinate\n';
          for (final lot in data) {
            csvContent += '"${lot['lot_id']}",';
            csvContent += '"${lotReference(lot, fallback: '')}",';
            csvContent += '"${lotBlockLabel(lot, fallback: '')}",';
            csvContent += '"${lot['status']}",';
            csvContent += '"${lot['price'] ?? 0}",';
            csvContent += '"${lot['x_coord'] ?? 0}",';
            csvContent += '"${lot['y_coord'] ?? 0}"\n';
          }
          break;
        case 'visitors':
          var query = supabase.from('visitor_log').select('''
                log_id,
                time_in,
                method,
                user:user_id (name, email),
                burial:burial_id (name_of_deceased)
              ''');
          if (_startDate != null) {
            query = query.gte('time_in', _startDate!.toIso8601String());
          }
          if (_endDate != null) {
            query = query.lte('time_in', _endDate!.toIso8601String());
          }
          final logs = await query.order('time_in', ascending: false);
          data = List<Map<String, dynamic>>.from(logs);
          fileName =
              'visitor_logs_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          csvContent =
              'ID,Visitor Name,Visitor Email,Time In,Method,Grave Visited\n';
          for (final log in data) {
            final user = log['user'] ?? {};
            final burial = log['burial'] ?? {};
            csvContent += '"${log['log_id']}",';
            csvContent += '"${user['name'] ?? 'Unknown'}",';
            csvContent += '"${user['email'] ?? ''}",';
            csvContent += '"${log['time_in'] ?? ''}",';
            csvContent += '"${log['method'] ?? 'Manual'}",';
            csvContent += '"${burial['name_of_deceased'] ?? 'N/A'}"\n';
          }
          break;
      }

      await downloadCsv(csvContent, fileName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report exported: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error exporting report: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateTimeString);
      return DateFormat('MMM d, y • h:mm a').format(date);
    } catch (e) {
      return dateTimeString;
    }
  }

  Widget _buildReportOverview() {
    final totalBurials = _summary['total_burials'] as int;
    final totalLots = _summary['total_lots'] as int;
    final availableLots = _summary['available_lots'] as int;
    final occupiedLots = _summary['occupied_lots'] as int;
    final visitors = _summary['total_visitors'] as int;
    final revenue = (_summary['revenue'] as num).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 700 ? 2 : 4;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: constraints.maxWidth < 700 ? 1.15 : 1.55,
          children: [
            _reportMetricCard(
              'Total Burials',
              totalBurials.toString(),
              Icons.people_outline_rounded,
              const Color(0xFF335538),
              const Color(0xFFC5EDC6),
            ),
            _reportMetricCard(
              'Total Lots',
              totalLots.toString(),
              Icons.grid_view_rounded,
              const Color(0xFF47626F),
              const Color(0xFFC7E4F3),
            ),
            _reportMetricCard(
              'Available Lots',
              availableLots.toString(),
              Icons.check_circle_outline_rounded,
              const Color(0xFF2F6F50),
              const Color(0xFFAAD0AB),
            ),
            _reportMetricCard(
              'Occupied Lots',
              occupiedLots.toString(),
              Icons.location_on_outlined,
              const Color(0xFFBA1A1A),
              const Color(0xFFFFDAD6),
            ),
            _reportMetricCard(
              'Visitors',
              visitors.toString(),
              Icons.groups_outlined,
              const Color(0xFF5A4B3F),
              const Color(0xFFF5DECE),
            ),
            _reportMetricCard(
              'QR Scans',
              (_summary['qr_scans'] as int).toString(),
              Icons.qr_code_2_rounded,
              const Color(0xFF335538),
              const Color(0xFFC5EDC6),
            ),
            _reportMetricCard(
              'Revenue',
              'PHP ${revenue.toStringAsFixed(2)}',
              Icons.payments_outlined,
              const Color(0xFF4B6E4F),
              const Color(0xFFC5EDC6),
            ),
          ],
        );
      },
    );
  }

  Widget _reportMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color bg,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bg.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(
                title.split(' ').first,
                style: const TextStyle(color: Color(0xFF424841), fontSize: 11),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1B1C1A),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(color: Color(0xFF424841), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportLayouts() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 950;
        final visitorCard = _buildRecentVisitorCard();
        if (wide) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildLotStatusCard()),
                  const SizedBox(width: 24),
                  Expanded(child: _buildRevenueCard()),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: visitorCard),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: _buildLotBreakdownCard()),
                ],
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildLotStatusCard(),
            const SizedBox(height: 24),
            _buildRevenueCard(),
            const SizedBox(height: 24),
            visitorCard,
            const SizedBox(height: 24),
            _buildLotBreakdownCard(),
          ],
        );
      },
    );
  }

  Widget _buildLotStatusCard() {
    final totalLots = (_summary['total_lots'] as int).toDouble();
    final availableLots = (_summary['available_lots'] as int).toDouble();
    final occupiedLots = (_summary['occupied_lots'] as int).toDouble();
    final occupiedPct = totalLots == 0 ? 0.0 : occupiedLots / totalLots;
    final availablePct = totalLots == 0 ? 0.0 : availableLots / totalLots;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lot Status Report',
            style: TextStyle(
              color: Color(0xFF1B1C1A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _statusStat(
                  'Occupied',
                  '${(occupiedPct * 100).round()}%',
                  const Color(0xFF335538),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusStat(
                  'Available',
                  '${(availablePct * 100).round()}%',
                  const Color(0xFF47626F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 12,
              color: const Color(0xFFEFEEEB),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: occupiedPct.clamp(0, 1),
                child: Container(color: const Color(0xFF335538)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 12,
              color: const Color(0xFFEFEEEB),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: availablePct.clamp(0, 1),
                child: Container(color: const Color(0xFFC7E4F3)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF424841), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentVisitorCard() {
    final recentActivities =
        (_metrics['recent_activities'] as List? ?? const [])
            .cast<Map<String, dynamic>>();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Visitor Activity',
            style: TextStyle(
              color: Color(0xFF1B1C1A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Latest logs recorded in the system.',
            style: TextStyle(color: Color(0xFF424841), fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (recentActivities.isEmpty)
            const Text('No recent activity found.')
          else
            Column(
              children: recentActivities.map((log) {
                final user = log['user'] as Map<String, dynamic>?;
                final burial = log['burial'] as Map<String, dynamic>?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3F0),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC5EDC6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFF335538),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?['name']?.toString() ?? 'Unknown visitor',
                              style: const TextStyle(
                                color: Color(0xFF1B1C1A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${burial?['name_of_deceased'] ?? 'N/A'} • ${log['method'] ?? 'Manual'}',
                              style: const TextStyle(
                                color: Color(0xFF424841),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDateTime(log['time_in']?.toString()),
                        style: const TextStyle(
                          color: Color(0xFF424841),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRevenueCard() {
    final revenue = (_summary['revenue'] as num).toDouble();
    final totalBurials = (_summary['total_burials'] as int);
    final totalVisitors = (_summary['total_visitors'] as int);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operational Snapshot',
            style: TextStyle(
              color: Color(0xFF1B1C1A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estimated Revenue',
                  style: TextStyle(color: Color(0xFF424841), fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'PHP ${revenue.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF335538),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Burials: $totalBurials',
                  style: const TextStyle(color: Color(0xFF424841)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Visitors: $totalVisitors',
                  style: const TextStyle(color: Color(0xFF424841)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFC7E4F3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF2F4A57)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Use the export controls below to generate CSV reports for burial, lot, or visitor records.',
                    style: TextStyle(
                      color: Color(0xFF2F4A57),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLotBreakdownCard() {
    final entries = _blockDistribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lot Breakdown by Block',
            style: TextStyle(
              color: Color(0xFF1B1C1A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Occupancy counts grouped by cemetery block.',
            style: TextStyle(color: Color(0xFF424841), fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Text('No block data available.')
          else
            Column(
              children: entries.take(6).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(color: Color(0xFF424841)),
                        ),
                      ),
                      Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          color: Color(0xFF1B1C1A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReportControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Report Export',
            style: TextStyle(
              color: Color(0xFF1B1C1A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Report Type',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'burials', label: Text('Burial Records')),
              ButtonSegment(value: 'lots', label: Text('Lot Inventory')),
              ButtonSegment(value: 'visitors', label: Text('Visitor Logs')),
            ],
            selected: {_selectedReportType},
            onSelectionChanged: (Set<String> selection) {
              setState(() {
                _selectedReportType = selection.first;
              });
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Date Range',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: const Text('Select Range'),
                ),
              ),
              if (_startDate != null || _endDate != null)
                IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: _clearDateFilter,
                ),
            ],
          ),
          if (_startDate != null || _endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Filter: ${_startDate != null ? DateFormat('MMM d, y').format(_startDate!) : 'Any'} - ${_endDate != null ? DateFormat('MMM d, y').format(_endDate!) : 'Any'}',
                style: const TextStyle(color: Color(0xFF424841), fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportReport,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_isLoading ? 'Generating...' : 'Export Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF335538),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F6),
      body: _isLoading && _summary['total_lots'] == 0
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorWidget()
          : SafeArea(
              child: RefreshIndicator(
                color: const Color(0xFF335538),
                onRefresh: _loadSummary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderBlock(),
                      const SizedBox(height: 24),
                      _buildReportOverview(),
                      const SizedBox(height: 24),
                      _buildReportLayouts(),
                      const SizedBox(height: 24),
                      _buildReportControls(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderBlock() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics & Reports',
          style: TextStyle(
            color: Color(0xFF335538),
            fontSize: 28,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Insightful summaries of cemetery operations and block occupancy.',
          style: TextStyle(color: Color(0xFF424841), fontSize: 14, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadSummary,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF335538),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
