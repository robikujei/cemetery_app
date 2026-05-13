import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminVisitorLogsScreen extends ConsumerStatefulWidget {
  const AdminVisitorLogsScreen({super.key});

  @override
  ConsumerState<AdminVisitorLogsScreen> createState() => _AdminVisitorLogsScreenState();
}

class _AdminVisitorLogsScreenState extends ConsumerState<AdminVisitorLogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _dateFilter = 'Today'; // Today, Week, Month, All
  
  // Date range for custom filter
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // Get all visitor logs with user and burial info
      final logs = await supabase
          .from('visitor_log')
          .select('''
            log_id,
            time_in,
            method,
            user:user_id (
              user_id,
              name,
              email
            ),
            burial:burial_id (
              burial_id,
              name_of_deceased,
              cemetery_lot (
                lot_number,
                section:section_id (name)
              )
            )
          ''')
          .order('time_in', ascending: false);
      
      setState(() {
        _logs = List<Map<String, dynamic>>.from(logs);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading logs: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    DateTime now = DateTime.now();
    DateTime filterDate = now;
    
    switch (_dateFilter) {
      case 'Today':
        filterDate = now;
        break;
      case 'Week':
        filterDate = now.subtract(const Duration(days: 7));
        break;
      case 'Month':
        filterDate = now.subtract(const Duration(days: 30));
        break;
      case 'All':
        filterDate = DateTime(2000);
        break;
    }
    
    setState(() {
      _filteredLogs = _logs.where((log) {
        // Date filter
        final timeIn = DateTime.parse(log['time_in']);
        if (_dateFilter != 'All' && timeIn.isBefore(filterDate)) {
          return false;
        }
        
        // Custom date range filter
        if (_startDate != null && timeIn.isBefore(_startDate!)) {
          return false;
        }
        if (_endDate != null && timeIn.isAfter(_endDate!)) {
          return false;
        }
        
        // Search filter
        if (_searchQuery.isNotEmpty) {
          final visitorName = log['user']?['name']?.toLowerCase() ?? '';
          final graveName = log['burial']?['name_of_deceased']?.toLowerCase() ?? '';
          final lotNumber = log['burial']?['cemetery_lot']?['lot_number']?.toLowerCase() ?? '';
          
          return visitorName.contains(_searchQuery.toLowerCase()) ||
                 graveName.contains(_searchQuery.toLowerCase()) ||
                 lotNumber.contains(_searchQuery.toLowerCase());
        }
        
        return true;
      }).toList();
    });
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
        _dateFilter = 'Custom';
        _applyFilters();
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _dateFilter = 'Today';
      _applyFilters();
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

  Color _getMethodColor(String method) {
    switch (method) {
      case 'QR': return Colors.green;
      case 'Manual': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitor Logs'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : Column(
                  children: [
                    // Filters
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          // Search bar
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Search by visitor name or grave...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _applyFilters();
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onChanged: (value) {
                              _searchQuery = value;
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 8),
                          
                          // Date filter row
                          Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(value: 'Today', label: Text('Today')),
                                    ButtonSegment(value: 'Week', label: Text('Week')),
                                    ButtonSegment(value: 'Month', label: Text('Month')),
                                    ButtonSegment(value: 'All', label: Text('All')),
                                  ],
                                  selected: {_dateFilter},
                                  onSelectionChanged: (Set<String> selection) {
                                    setState(() {
                                      _dateFilter = selection.first;
                                      if (_dateFilter != 'Custom') {
                                        _startDate = null;
                                        _endDate = null;
                                      }
                                      _applyFilters();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.date_range),
                                onPressed: _pickDateRange,
                                tooltip: 'Custom date range',
                              ),
                              if (_startDate != null || _endDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearDateFilter,
                                  tooltip: 'Clear date filter',
                                ),
                            ],
                          ),
                          
                          // Custom date range display
                          if (_startDate != null || _endDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_startDate != null ? DateFormat('MMM d, y').format(_startDate!) : 'Any'} - ${_endDate != null ? DateFormat('MMM d, y').format(_endDate!) : 'Any'}',
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Results count
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_filteredLogs.length} records found',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Logs list
                    Expanded(
                      child: _filteredLogs.isEmpty
                          ? const Center(child: Text('No visitor logs found'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredLogs.length,
                              itemBuilder: (context, index) {
                                final log = _filteredLogs[index];
                                final user = log['user'] ?? {};
                                final burial = log['burial'] ?? {};
                                final lot = burial['cemetery_lot'] ?? {};
                                final section = lot['section'] ?? {};
                                
                                final timeIn = _formatDateTime(log['time_in']);
                                final method = log['method'] ?? 'Manual';
                                final visitorName = user['name'] ?? 'Unknown Visitor';
                                final visitorEmail = user['email'] ?? '';
                                final graveName = burial['name_of_deceased'];
                                final lotNumber = lot['lot_number'];
                                final sectionName = section['name'];
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _getMethodColor(method).withOpacity(0.1),
                                      child: Icon(
                                        method == 'QR' ? Icons.qr_code_scanner : Icons.person,
                                        color: _getMethodColor(method),
                                      ),
                                    ),
                                    title: Text(
                                      visitorName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (graveName != null)
                                          Text('Visited: $graveName'),
                                        if (lotNumber != null)
                                          Text('Lot $lotNumber • Section ${sectionName ?? 'N/A'}'),
                                        Text(timeIn, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                    trailing: Chip(
                                      label: Text(method),
                                      backgroundColor: _getMethodColor(method).withOpacity(0.1),
                                      labelStyle: TextStyle(
                                        color: _getMethodColor(method),
                                        fontSize: 11,
                                      ),
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
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
            onPressed: _loadLogs,
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