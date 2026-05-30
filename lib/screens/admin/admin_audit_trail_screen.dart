import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminAuditTrailScreen extends ConsumerStatefulWidget {
  const AdminAuditTrailScreen({super.key});

  @override
  ConsumerState<AdminAuditTrailScreen> createState() => _AdminAuditTrailScreenState();
}

class _AdminAuditTrailScreenState extends ConsumerState<AdminAuditTrailScreen> {
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      final logs = await supabase
          .from('audit_log')
          .select('*')
          .order('created_at', ascending: false);
      
      setState(() {
        _auditLogs = List<Map<String, dynamic>>.from(logs);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading audit logs: $e';
        _isLoading = false;
      });
    }
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

 IconData _getActionIcon(String action) {
  if (action == 'CREATE') {
    return Icons.add_circle;
  } else if (action == 'UPDATE') {
    return Icons.edit;
  } else if (action == 'DELETE') {
    return Icons.delete;
  } else {
    return Icons.info;
  }
}

  Color _getActionColor(String action) {
  if (action == 'CREATE') {
    return Colors.green;
  } else if (action == 'UPDATE') {
    return Colors.blue;
  } else if (action == 'DELETE') {
    return Colors.red;
  } else {
    return Colors.grey;
  }
}

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredAuditLogs();
    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F6),
      body: RefreshIndicator(
        color: const Color(0xFF335538),
        onRefresh: _loadAuditLogs,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorWidget()
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(),
                        const SizedBox(height: 24),
                        _buildStatsGrid(),
                        const SizedBox(height: 24),
                        _buildTableCard(filteredLogs),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Audit Trail',
                style: TextStyle(
                  color: Color(0xFF335538),
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Real-time monitoring of site attendance and security checks.',
                style: TextStyle(
                  color: Color(0xFF424841),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3F0),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFC2C8BF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFC2C8BF)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF335538)),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMMM d, y').format(DateTime(2023, 10, 24)),
                      style: const TextStyle(
                        color: Color(0xFF1B1C1A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFC7E4F3).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _loadAuditLogs,
                      icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF335538)),
                    ),
                    Container(width: 1, height: 18, color: const Color(0xFFC2C8BF)),
                    IconButton(
                      onPressed: _loadAuditLogs,
                      icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF335538)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _filteredAuditLogs() {
    if (_searchQuery.isEmpty) return _auditLogs;
    final query = _searchQuery.toLowerCase();
    return _auditLogs.where((log) {
      final action = (log['action'] ?? '').toString().toLowerCase();
      final details = (log['details'] ?? '').toString().toLowerCase();
      final userEmail = (log['user_email'] ?? '').toString().toLowerCase();
      final userRole = (log['user_role'] ?? '').toString().toLowerCase();
      return action.contains(query) ||
          details.contains(query) ||
          userEmail.contains(query) ||
          userRole.contains(query);
    }).toList();
  }

  Widget _buildStatsGrid() {
    final total = _auditLogs.length;
    final createCount = _auditLogs.where((log) => (log['action'] ?? '') == 'CREATE').length;
    final updateCount = _auditLogs.where((log) => (log['action'] ?? '') == 'UPDATE').length;
    final deleteCount = _auditLogs.where((log) => (log['action'] ?? '') == 'DELETE').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 700 ? 2 : 4;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.55,
          children: [
            _statCard('Total Logs', '$total', Icons.list_alt_rounded, const Color(0xFF4B6E4F), const Color(0xFFC5EDC6)),
            _statCard('Creates', '$createCount', Icons.add_circle_outline_rounded, const Color(0xFF335538), const Color(0xFFC5EDC6)),
            _statCard('Updates', '$updateCount', Icons.edit_outlined, const Color(0xFF47626F), const Color(0xFFC7E4F3)),
            _statCard('Deletes', '$deleteCount', Icons.delete_outline_rounded, const Color(0xFFBA1A1A), const Color(0xFFFFDAD6)),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color == const Color(0xFFBA1A1A) ? const Color(0xFFFFDAD6) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE4E2DF)),
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
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox.shrink(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF424841), fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1B1C1A),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(List<Map<String, dynamic>> logs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE4E2DF)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF9F6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFC2C8BF)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search action, user, or details...',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B1C1A),
                    side: const BorderSide(color: Color(0xFF727971)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  ),
                  icon: const Icon(Icons.filter_list_rounded),
                  label: const Text('Filter'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loadAuditLogs,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF335538),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  ),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F3F0)),
              columns: const [
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Details')),
                DataColumn(label: Text('Timestamp')),
              ],
              rows: logs.map((log) {
                final action = log['action'] ?? 'UNKNOWN';
                final details = log['details'] ?? '';
                final userEmail = log['user_email'] ?? 'Unknown';
                final userRole = log['user_role'] ?? '?';
                final timestamp = _formatDateTime(log['created_at']);
                final actionColor = _getActionColor(action);
                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: actionColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getActionIcon(action), color: actionColor, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            action.replaceAll('_', ' '),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: actionColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(Text('$userEmail ($userRole)')),
                    DataCell(Text(details.isEmpty ? '-' : details)),
                    DataCell(Text(timestamp)),
                  ],
                );
              }).toList(),
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
            onPressed: _loadAuditLogs,
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
