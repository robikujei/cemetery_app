import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

const _background = Color(0xFFFBF9F6);
const _surface = Color(0xFFFFFFFF);
const _surfaceLow = Color(0xFFF5F3F0);
const _surfaceHigh = Color(0xFFEAE8E5);
const _primary = Color(0xFF335538);
const _primaryContainer = Color(0xFFC5EDC6);
const _onSurface = Color(0xFF1B1C1A);
const _onSurfaceVariant = Color(0xFF424841);
const _outlineVariant = Color(0xFFC2C8BF);

class LotOwnerHomeScreen extends ConsumerStatefulWidget {
  const LotOwnerHomeScreen({super.key});

  @override
  ConsumerState<LotOwnerHomeScreen> createState() => _LotOwnerHomeScreenState();
}

class _LotOwnerHomeScreenState extends ConsumerState<LotOwnerHomeScreen> {
  List<Map<String, dynamic>> _ownedLots = [];
  List<Map<String, dynamic>> _availableLots = [];
  bool _isLoading = true;
  bool _isLoadingAvailable = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _userName = '';
  String _userEmail = '';
  String _userPhone = '';
  String _adminPhone = '+63 912 345 6789';
  String _adminEmail = 'admin@cemetery.com';

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

    await _loadUserProfile();
    await _loadAdminContact();
    await _loadOwnedLots();
    await _loadAvailableLots();
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });
    
    await _loadUserProfile();
    await _loadAdminContact();
    await _loadOwnedLots();
    await _loadAvailableLots();
    
    setState(() {
      _isRefreshing = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data refreshed!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
    );
  }

  Future<void> _loadUserProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select('name, email, phone')
          .eq('user_id', user.id)
          .maybeSingle();
      
      if (userData != null) {
        _userName = userData['name'] ?? 'Lot Owner';
        _userEmail = userData['email'] ?? user.email ?? '';
        _userPhone = userData['phone'] ?? '';
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  Future<void> _loadOwnedLots() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final lots = await supabase
          .from('lot_ownership')
          .select('''
            ownership_id,
            total_months,
            months_paid,
            start_date,
            status,
            cemetery_lot (
              lot_id,
              lot_number,
              price,
              status,
              section:section_id (
                name,
                branch:branch_id (name)
              )
            ),
            transaction_history (
              transaction_id,
              amount,
              payment_date
            )
          ''')
          .eq('user_id', user.id);

      setState(() {
        _ownedLots = List<Map<String, dynamic>>.from(lots);
      });
    } catch (e) {
      print('Error loading owned lots: $e');
    }
  }

  Future<void> _loadAvailableLots() async {
    setState(() {
      _isLoadingAvailable = true;
    });
    
    try {
      final supabase = Supabase.instance.client;
      
      final lots = await supabase
          .from('cemetery_lot')
          .select('''
            lot_id,
            lot_number,
            price,
            status,
            section:section_id (
              name,
              branch:branch_id (name)
            )
          ''')
          .eq('status', 'Available');
      
      setState(() {
        _availableLots = List<Map<String, dynamic>>.from(lots);
        _isLoadingAvailable = false;
      });
    } catch (e) {
      print('Error loading available lots: $e');
      setState(() {
        _isLoadingAvailable = false;
      });
    }
  }

  void _goToPayment() {
    context.push('/lot-owner-payment');
  }

  Future<void> _loadAdminContact() async {
    try {
      final supabase = Supabase.instance.client;
      final admins = await supabase
          .from('users')
          .select('name, email, phone')
          .eq('role', 'admin')
          .order('name', ascending: true);

      final adminList = List<Map<String, dynamic>>.from(admins);
      final adminWithPhone = adminList.cast<Map<String, dynamic>?>().firstWhere(
            (admin) => (admin?['phone'] ?? '').toString().trim().isNotEmpty,
            orElse: () => adminList.isNotEmpty ? adminList.first : null,
          );

      if (adminWithPhone == null) return;

      final phone = (adminWithPhone['phone'] ?? '').toString().trim();
      final email = (adminWithPhone['email'] ?? '').toString().trim();

      _adminPhone = phone.isNotEmpty ? phone : _adminPhone;
      _adminEmail = email.isNotEmpty ? email : _adminEmail;
    } catch (e) {
      print('Error loading admin contact: $e');
    }
  }

  void _editProfile() {
    _showEditProfileDialog();
  }

  void _inquireAboutLot(Map<String, dynamic> lot) {
    final lotNumber = lot['lot_number'];
    final section = lot['section'] ?? {};
    final price = _formatCurrency(lot['price']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Inquire about Lot $lotNumber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Section: ${section['name'] ?? 'N/A'}'),
                  Text('Price: $price'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact the admin',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Phone: $_adminPhone',
                    style: const TextStyle(color: _onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Email: $_adminEmail',
                    style: const TextStyle(color: _onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _userName);
    final phoneController = TextEditingController(text: _userPhone);
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _background,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Edit Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: _fieldDecoration(
                      labelText: 'Full Name',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: _fieldDecoration(
                      labelText: 'Phone Number',
                      icon: Icons.phone_outlined,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const Divider(height: 32),
                  const Text('Change Password (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: _fieldDecoration(
                      labelText: 'Current Password',
                      icon: Icons.lock_outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: _fieldDecoration(
                      labelText: 'New Password',
                      icon: Icons.password_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: _fieldDecoration(
                      labelText: 'Confirm New Password',
                      icon: Icons.password_outlined,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => _saveProfile(
                  nameController.text,
                  phoneController.text,
                  currentPasswordController.text,
                  newPasswordController.text,
                  confirmPasswordController.text,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, color: _primary),
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

  Future<void> _saveProfile(String name, String phone, String currentPassword, String newPassword, String confirmPassword) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      await supabase
          .from('users')
          .update({
            'name': name,
            'phone': phone,
          })
          .eq('user_id', user.id);

      if (newPassword.isNotEmpty) {
        if (newPassword != confirmPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New passwords do not match'), backgroundColor: Colors.red),
          );
          return;
        }
        if (newPassword.length < 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be at least 6 characters'), backgroundColor: Colors.red),
          );
          return;
        }
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
      }

      setState(() {
        _userName = name;
        _userPhone = phone;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green),
      );
      
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.go('/login');
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

  Widget _buildPaymentButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: FilledButton.icon(
        onPressed: _goToPayment,
        icon: const Icon(Icons.payment_rounded, size: 22),
        label: const Text(
          'Make a Payment',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          toolbarHeight: 72,
          titleSpacing: 20,
          title: const Text('Lot Owner Dashboard'),
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
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
                  : const Icon(Icons.refresh_rounded),
              onPressed: _refreshData,
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.payment_rounded),
              onPressed: _goToPayment,
              tooltip: 'Make Payment',
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editProfile,
              tooltip: 'Edit Profile',
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(84),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _surfaceLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: _primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                labelColor: _primary,
                unselectedLabelColor: _onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                tabs: const [
                  Tab(icon: Icon(Icons.my_library_books_outlined), text: 'My Lots'),
                  Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Shop Lots'),
                  Tab(icon: Icon(Icons.map_outlined), text: 'Cemetery Map'),
                ],
              ),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _primary))
            : TabBarView(
                children: [
                  _buildMyLotsTab(),
                  _buildShopLotsTab(),
                  _buildMapTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _goToPayment,
          icon: const Icon(Icons.payment_rounded),
          label: const Text('Make Payment'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildMyLotsTab() {
    if (_ownedLots.isEmpty) {
      return Column(
        children: [
          _buildPaymentButton(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No lots owned yet',
                    style: const TextStyle(color: _onSurface, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse available lots in the Shop tab',
                    style: const TextStyle(color: _onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    return Column(
      children: [
        _buildPaymentButton(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _ownedLots.length,
              itemBuilder: (context, index) {
                final ownership = _ownedLots[index];
                final lot = ownership['cemetery_lot'] ?? {};
                final section = lot['section'] ?? {};
                final branch = section['branch'] ?? {};
                final transactions = ownership['transaction_history'] as List? ?? [];
                
                final lotPrice = (lot['price'] as num?)?.toDouble() ?? 0;
                final totalPaid = transactions.fold<double>(0, (sum, t) => sum + ((t['amount'] as num?)?.toDouble() ?? 0));
                final remaining = lotPrice - totalPaid;
                final totalMonths = (ownership['total_months'] as int?) ?? 0;
                final monthsPaid = (ownership['months_paid'] as int?) ?? 0;
                final monthsRemaining = totalMonths - monthsPaid;
                final paymentProgress = totalMonths > 0 ? monthsPaid / totalMonths : 0.0;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withValues(alpha: 0.06),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _primaryContainer,
                          child: const Icon(Icons.location_on, color: _primary),
                        ),
                        title: Text(
                          'Lot ${lot['lot_number'] ?? 'N/A'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${section['name'] ?? 'N/A'} • ${branch['name'] ?? 'N/A'}'),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('Price', _formatCurrency(lotPrice)),
                            const SizedBox(height: 8),
                            _buildInfoRow('Status', lot['status'] ?? 'Active'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Start Date', _formatDate(ownership['start_date'])),
                            const SizedBox(height: 8),
                            _buildInfoRow('Payment Plan', '$monthsPaid/$totalMonths months'),
                            const SizedBox(height: 8),
                            _buildInfoRow('Total Paid', _formatCurrency(totalPaid)),
                            const SizedBox(height: 8),
                            _buildInfoRow('Remaining Balance', _formatCurrency(remaining)),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: paymentProgress,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(999),
                              backgroundColor: _surfaceHigh,
                              color: _primary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$monthsRemaining months remaining',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showPaymentHistory(transactions, lot['lot_number']),
                            icon: const Icon(Icons.history),
                            label: const Text('View Payment History'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primary,
                              side: const BorderSide(color: _outlineVariant),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShopLotsTab() {
    if (_isLoadingAvailable) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_availableLots.isEmpty) {
      return Column(
        children: [
          _buildPaymentButton(),
          Expanded(
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64, color: _primary),
                  SizedBox(height: 16),
                  Text('No available lots at the moment', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text('Check back later for new listings', style: TextStyle(color: _onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    
    return Column(
      children: [
        _buildPaymentButton(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _availableLots.length,
              itemBuilder: (context, index) {
                final lot = _availableLots[index];
                final section = lot['section'] ?? {};
                final branch = section['branch'] ?? {};
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    leading: CircleAvatar(
                      backgroundColor: _primaryContainer,
                      child: const Icon(Icons.location_on, color: _primary),
                    ),
                    title: Text(
                      'Lot ${lot['lot_number']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${section['name'] ?? 'N/A'} • ${branch['name'] ?? 'N/A'}'),
                        Text('Price: ${_formatCurrency(lot['price'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _inquireAboutLot(lot),
                      icon: const Icon(Icons.contact_mail),
                      label: const Text('Inquire'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
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

  Widget _buildMapTab() {
    return Column(
      children: [
        _buildPaymentButton(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _outlineVariant.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _LotMapPreview(onInquire: _inquireAboutLot),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showPaymentHistory(List<dynamic> transactions, String lotNumber) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Payment History - Lot $lotNumber',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No payment records found'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final amount = (t['amount'] as num?)?.toDouble() ?? 0;
                  return ListTile(
                    leading: const Icon(Icons.receipt, color: Color(0xFF4B6E4F)),
                    title: Text(_formatCurrency(amount)),
                    subtitle: Text(_formatDate(t['payment_date'])),
                    trailing: const Icon(Icons.check_circle, color: Colors.green),
                  );
                },
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B6E4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LotMapPreview extends StatefulWidget {
  const _LotMapPreview({required this.onInquire});

  final ValueChanged<Map<String, dynamic>> onInquire;

  @override
  State<_LotMapPreview> createState() => _LotMapPreviewState();
}

class _LotMapPreviewState extends State<_LotMapPreview> {
  static final LatLng _tagumMapCenter = LatLng(7.3793125, 125.753328125);
  static const double _initialZoom = 18;
  static const double _mapLatSpan = 0.0036;
  static const double _mapLngSpan = 0.0046;

  final MapController _mapController = MapController();
  bool _isLoading = true;
  String? _errorMessage;
  double? _entranceXPercent;
  double? _entranceYPercent;
  List<Map<String, dynamic>> _lotMarkers = [];
  Map<String, dynamic>? _selectedAvailableLot;

  @override
  void initState() {
    super.initState();
    _loadPreviewData();
  }

  Future<void> _loadPreviewData() async {
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase
            .from('cemetery_map')
            .select('entrance_x_percent, entrance_y_percent')
            .order('uploaded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        supabase
            .from('lot_markers')
            .select('''
              marker_id,
              lot_id,
              x_percent,
              y_percent,
              cemetery_lot (
                lot_id,
                lot_number,
                price,
                status,
                section:section_id (
                  name,
                  branch:branch_id (name)
                )
              )
            ''')
            .order('marker_id'),
      ]);

      if (!mounted) return;
      setState(() {
        final mapConfig = results[0] as Map<String, dynamic>?;
        _entranceXPercent = (mapConfig?['entrance_x_percent'] as num?)?.toDouble();
        _entranceYPercent = (mapConfig?['entrance_y_percent'] as num?)?.toDouble();
        _lotMarkers = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  bool get _hasMappedEntrance =>
      _entranceXPercent != null && _entranceYPercent != null;

  LatLng get _entranceLatLng {
    if (!_hasMappedEntrance) return _tagumMapCenter;
    return _percentToLatLng(_entranceXPercent!, _entranceYPercent!);
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _mapLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _mapLngSpan;
    final lat = _tagumMapCenter.latitude + latOffset;
    final lng = _tagumMapCenter.longitude + lngOffset;
    return LatLng(lat, lng);
  }

  LatLng _markerToLatLng(Map<String, dynamic> marker) {
    final x = (marker['x_percent'] as num?)?.toDouble() ?? 50;
    final y = (marker['y_percent'] as num?)?.toDouble() ?? 50;
    return _percentToLatLng(x, y);
  }

  Color _statusColor(String? status) {
    if (status == 'Occupied') return const Color(0xFFBA1A1A);
    if (status == 'Available') return const Color(0xFF335538);
    if (status == 'Reserved') return const Color(0xFF47626F);
    return const Color(0xFF727971);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load map preview\n$_errorMessage',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _onSurfaceVariant),
          ),
        ),
      );
    }

    final markers = <Marker>[
      if (_hasMappedEntrance)
        Marker(
          point: _entranceLatLng,
          width: 40,
          height: 40,
          child: _PreviewPin(
            color: _primary,
            icon: Icons.place_rounded,
            size: 40,
            filled: true,
          ),
        ),
      ..._lotMarkers.map((marker) {
        final lot = marker['cemetery_lot'] ?? {};
        final status = lot['status']?.toString() ?? '';
        final lotNumber = lot['lot_number']?.toString() ?? '';
        final color = _statusColor(status);
        return Marker(
          point: _markerToLatLng(marker),
          width: 52,
          height: 60,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: status == 'Available'
                ? () => setState(() {
                      _selectedAvailableLot = Map<String, dynamic>.from(lot);
                    })
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PreviewPin(
                  color: color,
                  icon: status == 'Occupied'
                      ? Icons.person_rounded
                      : status == 'Reserved'
                          ? Icons.bookmark_rounded
                          : Icons.nature_people_rounded,
                  size: 40,
                  filled: true,
                ),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      lotNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _entranceLatLng,
            initialZoom: _initialZoom,
            minZoom: 14,
            maxZoom: 20,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cemetery_app',
              maxZoom: 20,
            ),
            MarkerLayer(markers: markers),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _outlineVariant.withValues(alpha: 0.5)),
            ),
            child: const Text(
              '9QH3+P8G, Tagum, Davao del Norte',
              style: TextStyle(fontWeight: FontWeight.w700, color: _onSurface),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _LegendDot(color: const Color(0xFF335538), label: 'Available'),
                _LegendDot(color: const Color(0xFFBA1A1A), label: 'Occupied'),
                _LegendDot(color: const Color(0xFF47626F), label: 'Reserved'),
              ],
            ),
          ),
        ),
        if (_selectedAvailableLot != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 76,
            child: _AvailableLotMapCard(
              lot: _selectedAvailableLot!,
              onClose: () => setState(() => _selectedAvailableLot = null),
              onInquire: () => widget.onInquire(_selectedAvailableLot!),
            ),
          ),
      ],
    );
  }
}

class _AvailableLotMapCard extends StatelessWidget {
  const _AvailableLotMapCard({
    required this.lot,
    required this.onClose,
    required this.onInquire,
  });

  final Map<String, dynamic> lot;
  final VoidCallback onClose;
  final VoidCallback onInquire;

  @override
  Widget build(BuildContext context) {
    final section = lot['section'] ?? {};
    final branch = section['branch'] ?? {};
    final lotNumber = lot['lot_number']?.toString() ?? 'N/A';
    final price = _formatPrice(lot['price']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.location_on_rounded, color: _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lot $lotNumber',
                  style: const TextStyle(
                    color: _onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${section['name'] ?? 'N/A'} • ${branch['name'] ?? 'N/A'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Price: $price',
                  style: const TextStyle(
                    color: _primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onInquire,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Inquire'),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: _onSurfaceVariant,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  String _formatPrice(dynamic value) {
    final numeric = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2).format(numeric);
  }
}

class _PreviewPin extends StatelessWidget {
  const _PreviewPin({
    required this.color,
    required this.icon,
    required this.size,
    this.filled = false,
  });

  final Color color;
  final IconData icon;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.42),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: _onSurface)),
      ],
    );
  }
}
