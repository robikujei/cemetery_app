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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Trail'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAuditLogs,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAuditLogs,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorWidget()
                : _auditLogs.isEmpty
                    ? const Center(child: Text('No audit logs found'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _auditLogs.length,
                        itemBuilder: (context, index) {
                          final log = _auditLogs[index];
                          final action = log['action'] ?? 'UNKNOWN';
                          final details = log['details'] ?? '';
                          final userEmail = log['user_email'] ?? 'Unknown';
                          final userRole = log['user_role'] ?? '?';
                          final timestamp = _formatDateTime(log['created_at']);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getActionColor(action).withOpacity(0.1),
                                child: Icon(
                                  _getActionIcon(action),
                                  color: _getActionColor(action),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                action.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _getActionColor(action),
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('User: $userEmail ($userRole)'),
                                  if (details.isNotEmpty)
                                    Text(details, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  Text(timestamp, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
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