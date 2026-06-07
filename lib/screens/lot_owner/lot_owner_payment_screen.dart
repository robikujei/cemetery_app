import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../utils/lot_formatters.dart';

const _background = Color(0xFFFBF9F6);
const _surface = Color(0xFFFFFFFF);
const _surfaceLow = Color(0xFFF5F3F0);
const _primary = Color(0xFF335538);
const _primaryContainer = Color(0xFFC5EDC6);
const _onSurface = Color(0xFF1B1C1A);
const _onSurfaceVariant = Color(0xFF424841);
const _outlineVariant = Color(0xFFC2C8BF);

const _lotOwnerPaymentProfileSelect = '''
  purchase_term,
  lot_price,
  interment_fee,
  certification_fee,
  burial_permit_fee,
  total_amount,
  or_number,
  receipt_amount,
  receipt_date,
  approved_date
''';

class LotOwnerPaymentScreen extends ConsumerStatefulWidget {
  const LotOwnerPaymentScreen({super.key});

  @override
  ConsumerState<LotOwnerPaymentScreen> createState() =>
      _LotOwnerPaymentScreenState();
}

class _LotOwnerPaymentScreenState extends ConsumerState<LotOwnerPaymentScreen> {
  List<Map<String, dynamic>> _ownedLots = [];
  List<Map<String, dynamic>> _paymentRequests = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  Map<String, dynamic> _profile = {};
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  int? _selectedOwnershipId;

  // Calculated values for selected lot
  double _monthlyPayment = 0;
  int _monthsPaid = 0;
  int _totalMonths = 0;
  double _remainingBalance = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
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
  }

  Future<void> _fetchData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      try {
        final profile = await supabase
            .from('users')
            .select(_lotOwnerPaymentProfileSelect)
            .eq('user_id', user.id)
            .maybeSingle();
        _profile = profile == null ? {} : Map<String, dynamic>.from(profile);
      } catch (_) {
        _profile = {};
      }

      final lots = await supabase
          .from('lot_ownership')
          .select('''
            ownership_id,
            total_months,
            months_paid,
            start_date,
            status,
            cemetery_lot!inner (
              lot_id,
              lot_number,
              lot_label,
              block_number,
              lot_class_type,
              price,
              status
            ),
            transaction_history (
              transaction_id,
              amount,
              payment_date
            )
          ''')
          .eq('user_id', user.id);

      final lotsWithBalance = <Map<String, dynamic>>[];
      for (var lot in lots) {
        final lotPrice =
            (lot['cemetery_lot']?['price'] as num?)?.toDouble() ?? 0;
        final transactions = lot['transaction_history'] as List? ?? [];
        final totalPaid = transactions.fold<double>(
          0,
          (sum, t) => sum + ((t['amount'] as num?)?.toDouble() ?? 0),
        );
        final remainingBalance = lotPrice - totalPaid;
        final monthlyPayment = lot['total_months'] > 0
            ? lotPrice / lot['total_months']
            : 0;

        lotsWithBalance.add({
          ...lot,
          'lot_price': lotPrice,
          'total_paid': totalPaid,
          'remaining_balance': remainingBalance,
          'monthly_payment': monthlyPayment,
          'months_remaining': lot['total_months'] - lot['months_paid'],
        });
      }

      final requests = await supabase
          .from('payment_requests')
          .select('*')
          .inFilter('ownership_id', lots.map((l) => l['ownership_id']).toList())
          .order('created_at', ascending: false);

      setState(() {
        _ownedLots = lotsWithBalance;
        _paymentRequests = List<Map<String, dynamic>>.from(requests);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  void _onLotSelected(int? ownershipId) {
    setState(() {
      _selectedOwnershipId = ownershipId;
      if (ownershipId != null) {
        final selected = _ownedLots.firstWhere(
          (l) => l['ownership_id'] == ownershipId,
        );
        _monthlyPayment = selected['monthly_payment'];
        _monthsPaid = selected['months_paid'];
        _totalMonths = selected['total_months'];
        _remainingBalance = selected['remaining_balance'];
        _amountController.clear();
      } else {
        _monthlyPayment = 0;
        _monthsPaid = 0;
        _totalMonths = 0;
        _remainingBalance = 0;
      }
    });
  }

  int _calculateMonthsToPay(double amount) {
    if (_monthlyPayment <= 0) return 0;
    return (amount / _monthlyPayment).floor();
  }

  Future<void> _submitPaymentRequest() async {
    final amount = double.tryParse(_amountController.text);
    final selectedLot = _ownedLots.firstWhere(
      (l) => l['ownership_id'] == _selectedOwnershipId,
      orElse: () => {},
    );

    if (_selectedOwnershipId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a lot'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount > selectedLot['remaining_balance']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amount exceeds remaining balance'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final monthsToPay = _calculateMonthsToPay(amount);
    final newMonthsPaid = _monthsPaid + monthsToPay;
    final newRemainingBalance = _remainingBalance - amount;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lot: ${lotReference(selectedLot['cemetery_lot'])}'),
            Text('Amount: ${_formatCurrency(amount)}'),
            Text('Months to be paid: $monthsToPay months'),
            Text('Current months paid: $_monthsPaid/$_totalMonths'),
            Text('New months paid: $newMonthsPaid/$_totalMonths'),
            Text('Remaining balance: ${_formatCurrency(newRemainingBalance)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);

      try {
        final supabase = Supabase.instance.client;

        await supabase.from('payment_requests').insert({
          'ownership_id': _selectedOwnershipId,
          'amount': amount,
          'payment_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'notes': _notesController.text,
          'status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment request submitted! +$monthsToPay months paid',
            ),
            backgroundColor: Colors.green,
          ),
        );

        _amountController.clear();
        _notesController.clear();
        _selectedOwnershipId = null;

        await _fetchData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'N/A';
    return 'PHP ${amount.toStringAsFixed(2)}';
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: const Text('My Payments'),
          backgroundColor: _surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: _primary,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: const Color(0x1A000000),
          titleTextStyle: const TextStyle(
            color: _primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          actions: [
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              onPressed: _refreshData,
              tooltip: 'Refresh',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _surfaceLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: const TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: _primaryContainer,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                labelColor: _primary,
                unselectedLabelColor: _onSurfaceVariant,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                tabs: [
                  Tab(icon: Icon(Icons.payment_outlined), text: 'Make Payment'),
                  Tab(
                    icon: Icon(Icons.history_rounded),
                    text: 'Payment History',
                  ),
                ],
              ),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : _errorMessage != null
            ? _buildErrorWidget()
            : TabBarView(
                children: [_buildPaymentFormTab(), _buildPaymentHistoryTab()],
              ),
      ),
    );
  }

  Widget _buildPaymentFormTab() {
    if (_ownedLots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off_outlined, size: 64, color: _primary),
            SizedBox(height: 16),
            Text(
              'No lots owned yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _onSurface,
              ),
            ),
          ],
        ),
      );
    }

    final monthsToPay = _amountController.text.isNotEmpty
        ? _calculateMonthsToPay(double.tryParse(_amountController.text) ?? 0)
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select Lot',
            style: TextStyle(fontWeight: FontWeight.w800, color: _onSurface),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _selectedOwnershipId,
            decoration: _fieldDecoration(
              labelText: 'Owned Lot',
              icon: Icons.location_on_outlined,
            ),
            items: _ownedLots.map((lot) {
              return DropdownMenuItem<int>(
                value: lot['ownership_id'],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lot ${lotReference(lot['cemetery_lot'])}'),
                    Text(
                      'Balance: ${_formatCurrency(lot['remaining_balance'])} • ${lot['months_paid']}/${lot['total_months']} months paid',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: _onLotSelected,
          ),

          if (_selectedOwnershipId != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    'Monthly Payment',
                    _formatCurrency(_monthlyPayment),
                  ),
                  _buildInfoRow('Months Paid', '$_monthsPaid/$_totalMonths'),
                  _buildInfoRow(
                    'Remaining Balance',
                    _formatCurrency(_remainingBalance),
                  ),
                  const SizedBox(height: 14),
                  _buildOfficialPayablePanel(),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          const Text(
            'Payment Amount',
            style: TextStyle(fontWeight: FontWeight.w800, color: _onSurface),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            decoration: _fieldDecoration(
              labelText: 'Amount (₱)',
              icon: Icons.payments_outlined,
              prefixText: '₱',
              helperText: monthsToPay > 0
                  ? 'This will pay $monthsToPay month(s)'
                  : null,
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 16),

          const Text(
            'Notes (Optional)',
            style: TextStyle(fontWeight: FontWeight.w800, color: _onSurface),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            decoration: _fieldDecoration(
              hintText: 'e.g., Check #1234, Bank Transfer',
              labelText: 'Notes',
              icon: Icons.note_outlined,
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _submitPaymentRequest,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Submit Payment Request'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildOfficialPayablePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Official Amount Payable',
                style: TextStyle(
                  color: _onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            'Terms',
            _purchaseTermLabel(_profileText('purchase_term')),
          ),
          _buildInfoRow('Lot Price', _profileMoney('lot_price')),
          _buildInfoRow('Interment Fee', _profileMoney('interment_fee')),
          _buildInfoRow(
            'Certification Fee',
            _profileMoney('certification_fee'),
          ),
          _buildInfoRow(
            'Burial Permit Fee',
            _profileMoney('burial_permit_fee'),
          ),
          _buildInfoRow('Total', _profileMoney('total_amount')),
          _buildInfoRow('OR #', _profileText('or_number')),
          _buildInfoRow('P', _profileMoney('receipt_amount')),
          _buildInfoRow('Receipt Date', _profileDate('receipt_date')),
          _buildInfoRow('Approved Date', _profileDate('approved_date')),
        ],
      ),
    );
  }

  String _profileText(String key) {
    final value = _profile[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  String _profileDate(String key) {
    final value = _profileText(key);
    if (value.isEmpty) return 'Not recorded';
    return _formatDate(value);
  }

  String _profileMoney(String key) {
    final value = _profile[key];
    if (value == null) return 'Not recorded';
    final numeric = value is num ? value.toDouble() : double.tryParse('$value');
    return numeric == null ? value.toString() : _formatCurrency(numeric);
  }

  String _purchaseTermLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'cash') return 'Cash';
    if (normalized == 'at_need') return 'At Need';
    return value.isEmpty ? 'Not recorded' : value;
  }

  Widget _buildPaymentHistoryTab() {
    if (_paymentRequests.isEmpty) {
      return const Center(
        child: Text(
          'No payment requests yet',
          style: TextStyle(color: _onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _paymentRequests.length,
        itemBuilder: (context, index) {
          final request = _paymentRequests[index];
          final statusColor = _getStatusColor(request['status']);
          final ownership = _ownedLots.firstWhere(
            (l) => l['ownership_id'] == request['ownership_id'],
            orElse: () => {},
          );
          final lot = ownership['cemetery_lot'] ?? {};

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.14),
                child: Icon(Icons.receipt, color: statusColor),
              ),
              title: Text('₱${request['amount']} - Lot ${lotReference(lot)}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date: ${_formatDate(request['payment_date'])}'),
                  Text(
                    'Status: ${request['status'].toUpperCase()}',
                    style: TextStyle(color: statusColor),
                  ),
                  if (request['admin_notes'] != null)
                    Text(
                      'Note: ${request['admin_notes']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              trailing: Chip(
                label: Text(request['status'].toUpperCase()),
                backgroundColor: statusColor.withValues(alpha: 0.18),
              ),
            ),
          );
        },
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
          FilledButton(
            onPressed: _loadData,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
    String? prefixText,
    String? hintText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      prefixIcon: Icon(icon, color: _primary),
      prefixText: prefixText,
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.4),
      ),
    );
  }
}
