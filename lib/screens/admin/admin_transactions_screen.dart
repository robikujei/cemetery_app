import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminTransactionsScreen extends ConsumerStatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  ConsumerState<AdminTransactionsScreen> createState() => _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends ConsumerState<AdminTransactionsScreen> {
  List<Map<String, dynamic>> _paymentHistory = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _fetchData();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    
    await _fetchData();
    
    setState(() {
      _isRefreshing = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data refreshed!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
    );
  }

  Future<void> _fetchData() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Get pending payment requests
      final pending = await supabase
          .from('payment_requests')
          .select('''
            *,
            lot_ownership!inner (
              user:user_id (name, email),
              cemetery_lot!inner (lot_number, price)
            )
          ''')
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      
      // Get payment history (approved payments)
      final history = await supabase
          .from('payment_requests')
          .select('''
            *,
            lot_ownership!inner (
              user:user_id (name, email),
              cemetery_lot!inner (lot_number, price)
            )
          ''')
          .eq('status', 'approved')
          .order('created_at', ascending: false);
      
      setState(() {
        _pendingRequests = List<Map<String, dynamic>>.from(pending);
        _paymentHistory = List<Map<String, dynamic>>.from(history);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  void _filterHistory(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  Future<void> _approvePaymentRequest(Map<String, dynamic> request) async {
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      
      await supabase
          .from('payment_requests')
          .update({
            'status': 'approved',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('request_id', request['request_id']);
      
      final ownership = await supabase
          .from('lot_ownership')
          .select('*, cemetery_lot!inner (lot_id, lot_number, price)')
          .eq('ownership_id', request['ownership_id'])
          .single();
      
      await supabase.from('transaction_history').insert({
        'ownership_id': request['ownership_id'],
        'amount': request['amount'],
        'payment_date': request['payment_date'],
        'notes': 'Approved payment request #${request['request_id']}',
      });
      
      final monthlyPayment = (ownership['cemetery_lot']['price'] as num).toDouble() / ownership['total_months'];
      final additionalMonths = (request['amount'] / monthlyPayment).floor();
      final newMonthsPaid = (ownership['months_paid'] as int) + additionalMonths;
      
      await supabase
          .from('lot_ownership')
          .update({'months_paid': newMonthsPaid})
          .eq('ownership_id', request['ownership_id']);
      
      if (ownership['months_paid'] == 0 && newMonthsPaid > 0) {
        await supabase
            .from('cemetery_lot')
            .update({'status': 'Occupied'})
            .eq('lot_id', ownership['cemetery_lot']['lot_id']);
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment approved!'), backgroundColor: Colors.green),
      );
      
      await _fetchData();
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectPaymentRequest(Map<String, dynamic> request) async {
    final adminNotesController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFDAD6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.payments_outlined,
                color: Color(0xFFBA1A1A),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Reject Payment',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Amount: ₱${request['amount']}'),
            const SizedBox(height: 12),
            TextField(
              controller: adminNotesController,
              decoration: InputDecoration(
                labelText: 'Reason for Rejection',
                prefixIcon: const Icon(
                  Icons.notes_outlined,
                  color: Color(0xFF335538),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF335538),
                    width: 1.4,
                  ),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF424841),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() => _isLoading = true);
      
      try {
        final supabase = Supabase.instance.client;
        
        await supabase
            .from('payment_requests')
            .update({
              'status': 'rejected',
              'admin_notes': adminNotesController.text,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('request_id', request['request_id']);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment rejected'), backgroundColor: Colors.orange),
        );
        
        await _fetchData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'N/A';
    return '₱${amount.toStringAsFixed(2)}';
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, y').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBF9F6),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Payment Management',
                              style: TextStyle(
                                color: Color(0xFF335538),
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Track pending approvals and approved payment history.',
                              style: TextStyle(
                                color: Color(0xFF424841),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _refreshData,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF335538),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, color: Color(0xFF335538)),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth < 720 ? 2 : 4;
                      return GridView.count(
                        crossAxisCount: columns,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.6,
                        children: [
                          _summaryCard('Pending', '${_pendingRequests.length}', Icons.pending_actions_rounded, const Color(0xFF335538), const Color(0xFFC5EDC6)),
                          _summaryCard('Approved', '${_paymentHistory.length}', Icons.history_rounded, const Color(0xFF47626F), const Color(0xFFC7E4F3)),
                          _summaryCard('Status', 'Live', Icons.verified_rounded, const Color(0xFF4B6E4F), const Color(0xFFC5EDC6)),
                          _summaryCard('Search', _searchQuery.isEmpty ? 'All' : _searchQuery, Icons.search_rounded, const Color(0xFF5A4B3F), const Color(0xFFF5DECE)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE4E2DF)),
                ),
                child: const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.pending_actions), text: 'Pending Approvals'),
                    Tab(icon: Icon(Icons.history), text: 'Payment History'),
                  ],
                  indicatorColor: Color(0xFF335538),
                  labelColor: Color(0xFF335538),
                  unselectedLabelColor: Color(0xFF424841),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildErrorWidget()
                      : TabBarView(
                          children: [
                            _buildApprovalsTab(),
                            _buildHistoryTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalsTab() {
    if (_pendingRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('No pending payment requests'),
            SizedBox(height: 8),
            Text('All payments have been processed', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _pendingRequests.length,
        itemBuilder: (context, index) {
          final request = _pendingRequests[index];
          final ownership = request['lot_ownership'] ?? {};
          final user = ownership['user'] ?? {};
          final lot = ownership['cemetery_lot'] ?? {};
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.withOpacity(0.1),
                        child: const Icon(Icons.pending, color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lot ${lot['lot_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(user['name'] ?? 'Unknown Owner'),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text('₱${request['amount']}'),
                        backgroundColor: const Color(0xFF4B6E4F).withOpacity(0.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Payment Date: ${_formatDate(request['payment_date'])}'),
                  if (request['notes'] != null && request['notes'].isNotEmpty)
                    Text('Notes: ${request['notes']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _rejectPaymentRequest(request),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approvePaymentRequest(request),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_paymentHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No payment history found'),
            SizedBox(height: 8),
            Text('Approved payments will appear here', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by lot number or owner name...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onChanged: _filterHistory,
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _paymentHistory.length,
              itemBuilder: (context, index) {
                final request = _paymentHistory[index];
                final ownership = request['lot_ownership'] ?? {};
                final user = ownership['user'] ?? {};
                final lot = ownership['cemetery_lot'] ?? {};
                
                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  final lotNumber = lot['lot_number']?.toLowerCase() ?? '';
                  final ownerName = user['name']?.toLowerCase() ?? '';
                  final query = _searchQuery.toLowerCase();
                  if (!lotNumber.contains(query) && !ownerName.contains(query)) {
                    return const SizedBox.shrink();
                  }
                }
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.green.withOpacity(0.1),
                              child: const Icon(Icons.check_circle, color: Colors.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Lot ${lot['lot_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(user['name'] ?? 'Unknown Owner'),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text('₱${request['amount']}'),
                              backgroundColor: Colors.green.withOpacity(0.1),
                              labelStyle: const TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text('Payment Date: ${_formatDate(request['payment_date'])}'),
                        Text('Approved: ${_formatDate(request['updated_at'])}'),
                        if (request['notes'] != null && request['notes'].isNotEmpty)
                          Text('Notes: ${request['notes']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
            onPressed: _refreshData,
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

  Widget _summaryCard(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                style: const TextStyle(color: Color(0xFF1B1C1A), fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
