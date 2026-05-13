import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  
  // Summary statistics
  Map<String, dynamic> _summary = {
    'total_burials': 0,
    'total_lots': 0,
    'available_lots': 0,
    'occupied_lots': 0,
    'total_visitors': 0,
    'qr_scans': 0,
    'revenue': 0,
  };
  
  // Report type selection
  String _selectedReportType = 'burials';
  
  // Date filters
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
      
      // Get total burials
      final burials = await supabase.from('burial_record').select('burial_id');
      
      // Get lot statistics
      final lots = await supabase.from('cemetery_lot').select('lot_id, status, price');
      final availableLots = lots.where((l) => l['status'] == 'Available').length;
      final occupiedLots = lots.where((l) => l['status'] == 'Occupied').length;
      
      // Calculate revenue from occupied lots
      double revenue = 0;
      for (var lot in lots) {
        if (lot['status'] == 'Occupied' && lot['price'] != null) {
          revenue += (lot['price'] as num).toDouble();
        }
      }
      
      // Get visitor statistics
      final visitors = await supabase.from('visitor_log').select('log_id, method');
      final qrScans = visitors.where((v) => v['method'] == 'QR').length;
      
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
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading summary: $e';
        _isLoading = false;
      });
    }
  }

  void _downloadAsCSV(String csvContent, String fileName) {
  // Web download
  final blob = html.Blob([csvContent], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..target = 'blank'
    ..download = fileName;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();  // ← Fixed: no argument needed
  html.Url.revokeObjectUrl(url);
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
      
      // Fetch data based on report type
      switch (_selectedReportType) {
        case 'burials':
          var query = supabase
              .from('burial_record')
              .select('''
                burial_id,
                name_of_deceased,
                birth_date,
                death_date,
                burial_date,
                cemetery_lot (
                  lot_number,
                  section:section_id (name)
                )
              ''');
          
          // Apply date filters
          if (_startDate != null) {
            query = query.gte('death_date', _startDate!.toIso8601String());
          }
          if (_endDate != null) {
            query = query.lte('death_date', _endDate!.toIso8601String());
          }
          
          final records = await query;
          data = List<Map<String, dynamic>>.from(records);
          fileName = 'burial_records_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          
          // Create CSV content
          csvContent = 'ID,Name of Deceased,Birth Date,Death Date,Burial Date,Lot Number,Section\n';
          for (var record in data) {
            final lot = record['cemetery_lot'] ?? {};
            final section = lot['section'] ?? {};
            csvContent += '"${record['burial_id']}",';
            csvContent += '"${record['name_of_deceased']}",';
            csvContent += '"${record['birth_date'] ?? ''}",';
            csvContent += '"${record['death_date'] ?? ''}",';
            csvContent += '"${record['burial_date'] ?? ''}",';
            csvContent += '"${lot['lot_number'] ?? ''}",';
            csvContent += '"${section['name'] ?? ''}"\n';
          }
          break;
          
        case 'lots':
          final lots = await supabase
              .from('cemetery_lot')
              .select('''
                lot_id,
                lot_number,
                status,
                price,
                x_coord,
                y_coord,
                section:section_id (name)
              ''');
          data = List<Map<String, dynamic>>.from(lots);
          fileName = 'lot_inventory_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          
          csvContent = 'ID,Lot Number,Section,Status,Price,X Coordinate,Y Coordinate\n';
          for (var lot in data) {
            final section = lot['section'] ?? {};
            csvContent += '"${lot['lot_id']}",';
            csvContent += '"${lot['lot_number']}",';
            csvContent += '"${section['name'] ?? ''}",';
            csvContent += '"${lot['status']}",';
            csvContent += '"${lot['price'] ?? 0}",';
            csvContent += '"${lot['x_coord'] ?? 0}",';
            csvContent += '"${lot['y_coord'] ?? 0}"\n';
          }
          break;
          
        case 'visitors':
          var query = supabase
              .from('visitor_log')
              .select('''
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
          fileName = 'visitor_logs_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
          
          csvContent = 'ID,Visitor Name,Visitor Email,Time In,Method,Grave Visited\n';
          for (var log in data) {
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
      
      // Download the file
      _downloadAsCSV(csvContent, fileName);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report exported: $fileName'), backgroundColor: Colors.green),
      );
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error exporting report: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSummary,
          ),
        ],
      ),
      body: _isLoading && _summary['total_lots'] == 0
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Summary Cards
                      _buildSummarySection(),
                      const SizedBox(height: 24),
                      
                      // Report Generation Section
                      _buildReportSection(),
                      const SizedBox(height: 24),
                      
                      // Export Section
                      _buildExportSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummarySection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cemetery Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4B6E4F)),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildSummaryCard('Total Burials', _summary['total_burials'].toString(), Icons.people, Colors.blue),
                _buildSummaryCard('Total Lots', _summary['total_lots'].toString(), Icons.location_on, Colors.green),
                _buildSummaryCard('Available Lots', _summary['available_lots'].toString(), Icons.check_circle, Colors.green.shade300),
                _buildSummaryCard('Occupied Lots', _summary['occupied_lots'].toString(), Icons.check_circle, Colors.orange),
                _buildSummaryCard('Total Visitors', _summary['total_visitors'].toString(), Icons.people_outline, Colors.purple),
                _buildSummaryCard('QR Scans', _summary['qr_scans'].toString(), Icons.qr_code_scanner, Colors.teal),
                _buildSummaryCard('Total Revenue', '₱${_summary['revenue'].toStringAsFixed(2)}', Icons.attach_money, Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generate Report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4B6E4F)),
            ),
            const SizedBox(height: 16),
            
            // Report Type
            const Text('Report Type', style: TextStyle(fontWeight: FontWeight.w600)),
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
            
            // Date Range Filter
            const Text('Date Range (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range),
                    label: const Text('Select Range'),
                  ),
                ),
                if (_startDate != null || _endDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearDateFilter,
                  ),
              ],
            ),
            if (_startDate != null || _endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Filter: ${_startDate != null ? DateFormat('MMM d, y').format(_startDate!) : 'Any'} - ${_endDate != null ? DateFormat('MMM d, y').format(_endDate!) : 'Any'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export Options',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF4B6E4F)),
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _exportReport,
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_isLoading ? 'Generating...' : 'Export Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B6E4F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reports will be downloaded as CSV files. Date filters apply to death date (burials) or check-in time (visitors).',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
              backgroundColor: const Color(0xFF4B6E4F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}