import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../services/map_feature_service.dart';
import '../../services/supabase_pagination_service.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/lot_pricing.dart';
import '../../utils/map_feature_geometry.dart';

const _background = Color(0xFFFBF9F6);
const _surface = Color(0xFFFFFFFF);
const _surfaceLow = Color(0xFFF5F3F0);
const _primary = Color(0xFF335538);
const _primaryContainer = Color(0xFFC5EDC6);
const _onSurface = Color(0xFF1B1C1A);
const _onSurfaceVariant = Color(0xFF424841);
const _outlineVariant = Color(0xFFC2C8BF);

const _lotOwnerProfileSelect = '''
  control_number,
  first_name,
  middle_name,
  last_name,
  address,
  occupation,
  age,
  civil_status,
  date_of_birth,
  gender,
  spouse_beneficiary,
  beneficiary_relationship,
  lot_class_type,
  block_number,
  lot_number,
  number_of_lots,
  purchase_term,
  lot_price,
  interment_fee,
  certification_fee,
  burial_permit_fee,
  total_amount,
  or_number,
  receipt_amount,
  receipt_date,
  approved_date,
  approved_by_name,
  approval_signature
''';

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
  String _userName = '';
  String _userEmail = '';
  String _userPhone = '';
  String _adminPhone = '+63 912 345 6789';
  String _adminEmail = 'admin@cemetery.com';
  Map<String, dynamic> _profile = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
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

    if (!mounted) return;
    setState(() {
      _isRefreshing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data refreshed!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _loadUserProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      Map<String, dynamic>? userData;
      try {
        userData = await supabase
            .from('users')
            .select('name, email, phone, $_lotOwnerProfileSelect')
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (_) {
        userData = await supabase
            .from('users')
            .select('name, email, phone')
            .eq('user_id', user.id)
            .maybeSingle();
      }

      if (userData != null) {
        final firstName = _profileTextFrom(userData, 'first_name');
        final middleName = _profileTextFrom(userData, 'middle_name');
        final lastName = _profileTextFrom(userData, 'last_name');
        final profileName = [
          firstName,
          middleName,
          lastName,
        ].where((part) => part.isNotEmpty).join(' ');

        _userName = userData['name'] ?? 'Lot Owner';
        if (profileName.isNotEmpty) _userName = profileName;
        _userEmail = userData['email'] ?? user.email ?? '';
        _userPhone = userData['phone'] ?? '';
        _profile = Map<String, dynamic>.from(userData);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
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

      setState(() {
        _ownedLots = List<Map<String, dynamic>>.from(lots);
      });
    } catch (e) {
      debugPrint('Error loading owned lots: $e');
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
            lot_label,
            block_number,
            lot_class_type,
            price,
            status
          ''')
          .eq('status', 'Available');

      setState(() {
        _availableLots = List<Map<String, dynamic>>.from(lots);
        _isLoadingAvailable = false;
      });
    } catch (e) {
      debugPrint('Error loading available lots: $e');
      setState(() {
        _isLoadingAvailable = false;
      });
    }
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
      debugPrint('Error loading admin contact: $e');
    }
  }

  void _editProfile() {
    _showEditProfileDialog();
  }

  void _inquireAboutLot(Map<String, dynamic> lot) {
    final lotNumber = lotReference(lot);
    final meta = lotMeta(lot);
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
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.isEmpty ? lotBlockLabel(lot) : meta),
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
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact the admin',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _onSurface,
                    ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
                  const Text(
                    'Change Password (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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

  Future<void> _saveProfile(
    String name,
    String phone,
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      await supabase
          .from('users')
          .update({'name': name, 'phone': phone})
          .eq('user_id', user.id);

      if (!mounted) return;
      if (newPassword.isNotEmpty) {
        if (newPassword != confirmPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('New passwords do not match'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (newPassword.length < 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password must be at least 6 characters'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
        if (!mounted) return;
      }

      setState(() {
        _userName = name;
        _userPhone = phone;
        _profile = {..._profile, 'name': name, 'phone': phone};
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
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

  String _profileText(String key) => _profileTextFrom(_profile, key);

  String _profileTextFrom(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  String _profileDate(String key) {
    final value = _profileText(key);
    if (value.isEmpty) return '';
    return _formatDate(value);
  }

  String _profileMoney(String key) {
    final value = _profile[key];
    if (value == null) return '';
    final numeric = value is num ? value.toDouble() : double.tryParse('$value');
    return numeric == null ? value.toString() : _formatCurrency(numeric);
  }

  String _purchaseTermLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'cash') return 'Cash';
    if (normalized == 'at_need') return 'At Need';
    return value;
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
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.45),
                ),
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
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.my_library_books_outlined),
                    text: 'My Lots',
                  ),
                  Tab(
                    icon: Icon(Icons.shopping_cart_outlined),
                    text: 'Shop Lots',
                  ),
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
      ),
    );
  }

  Widget _buildMyLotsTab() {
    if (_ownedLots.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No lots owned yet',
                    style: const TextStyle(
                      color: _onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _ownedLots.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return _buildOwnerSummaryCard();
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 16),
                    child: _buildPurchaserProfileCard(),
                  );
                }

                final ownership = _ownedLots[index - 2];
                final lot = ownership['cemetery_lot'] ?? {};
                final locationText = lotMeta(lot).isEmpty
                    ? lotBlockLabel(lot)
                    : lotMeta(lot);

                final pricing = lotPriceForType(
                  lot['lot_class_type']?.toString(),
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _outlineVariant.withValues(alpha: 0.45),
                    ),
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
                          'Lot ${lotReference(lot)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(locationText),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'Lot Type',
                              lot['lot_class_type']?.toString() ?? 'Unknown',
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'At-Need Price',
                              pricing == null
                                  ? '--'
                                  : _formatCurrency(pricing.atNeed),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Pre-Need Price',
                              pricing == null
                                  ? '--'
                                  : _formatCurrency(pricing.preNeed),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow('Status', lot['status'] ?? 'Active'),
                            const SizedBox(height: 18),
                            _buildLotProfilePanel(lot),
                            const SizedBox(height: 12),
                            _buildAmountPayablePanel(),
                          ],
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

  Widget _buildOwnerSummaryCard() {
    final controlNumber = _profileText('control_number');
    return _recordCard(
      icon: Icons.assignment_ind_rounded,
      title: "Purchaser's Profile",
      children: [
        _recordRow('Name of Buyer', _userName),
        _recordRow('Email', _userEmail),
        _recordRow('Mobile', _userPhone),
        if (controlNumber.isNotEmpty) _recordRow('Control No.', controlNumber),
        _recordRow('Address', _profileText('address')),
      ],
    );
  }

  Widget _buildPurchaserProfileCard() {
    return _recordCard(
      icon: Icons.badge_outlined,
      title: 'Personal Details',
      children: [
        _recordRow('Occupation', _profileText('occupation')),
        _recordRow('Age', _profileText('age')),
        _recordRow('Civil Status', _profileText('civil_status')),
        _recordRow('Date of Birth', _profileDate('date_of_birth')),
        _recordRow('Gender', _profileText('gender')),
        _recordRow('Spouse / Beneficiary', _profileText('spouse_beneficiary')),
        _recordRow('Relationship', _profileText('beneficiary_relationship')),
      ],
    );
  }

  Widget _buildLotProfilePanel(Map<String, dynamic> lot) {
    final lotClassType = _profileText('lot_class_type').isNotEmpty
        ? _profileText('lot_class_type')
        : lotText(lot, 'lot_class_type');
    final blockNumber = _profileText('block_number').isNotEmpty
        ? _profileText('block_number')
        : lotText(lot, 'block_number');
    final lotNumber = _profileText('lot_number').isNotEmpty
        ? _profileText('lot_number')
        : lotText(lot, 'lot_number');

    return _recordPanel(
      icon: Icons.location_on_outlined,
      title: 'Registered Lot Details',
      children: [
        _recordRow('Lot Class / Type', lotClassType),
        _recordRow('Block', blockNumber),
        _recordRow('Lot', lotNumber),
        _recordRow('No. of Lots', _profileText('number_of_lots')),
        _recordRow('Terms', _purchaseTermLabel(_profileText('purchase_term'))),
      ],
    );
  }

  Widget _buildAmountPayablePanel() {
    return _recordPanel(
      icon: Icons.receipt_long_outlined,
      title: 'Amount Payable',
      children: [
        _recordRow('Lot Price', _profileMoney('lot_price')),
        _recordRow('Interment Fee', _profileMoney('interment_fee')),
        _recordRow('Certification Fee', _profileMoney('certification_fee')),
        _recordRow('Burial Permit Fee', _profileMoney('burial_permit_fee')),
        _recordRow('Total', _profileMoney('total_amount')),
        _recordRow('OR #', _profileText('or_number')),
        _recordRow('P', _profileMoney('receipt_amount')),
        _recordRow('Receipt Date', _profileDate('receipt_date')),
        _recordRow('Approved Date', _profileDate('approved_date')),
        _recordRow('Approved By', _profileText('approved_by_name')),
      ],
    );
  }

  Widget _recordCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _recordTitle(icon: icon, title: title),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _recordPanel({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _recordTitle(icon: icon, title: title, compact: true),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _recordTitle({
    required IconData icon,
    required String title,
    bool compact = false,
  }) {
    return Row(
      children: [
        Container(
          width: compact ? 30 : 38,
          height: compact ? 30 : 38,
          decoration: BoxDecoration(
            color: _primaryContainer,
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
          ),
          child: Icon(icon, color: _primary, size: compact ? 17 : 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: _onSurface,
              fontSize: compact ? 13 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _recordRow(String label, String value) {
    final display = value.trim().isEmpty ? 'Not recorded' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(color: _onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: display == 'Not recorded'
                    ? _onSurfaceVariant
                    : _onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopLotsTab() {
    if (_isLoadingAvailable) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_availableLots.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64, color: _primary),
                  SizedBox(height: 16),
                  Text(
                    'No available lots at the moment',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Check back later for new listings',
                    style: TextStyle(color: _onSurfaceVariant),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _availableLots.length,
              itemBuilder: (context, index) {
                final lot = _availableLots[index];
                final locationText = lotMeta(lot).isEmpty
                    ? lotBlockLabel(lot)
                    : lotMeta(lot);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _outlineVariant.withValues(alpha: 0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: _primaryContainer,
                      child: const Icon(Icons.location_on, color: _primary),
                    ),
                    title: Text(
                      'Lot ${lotReference(lot)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(locationText),
                        Text(
                          'Price: ${_formatCurrency(lot['price'])}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    trailing: ElevatedButton.icon(
                      onPressed: () => _inquireAboutLot(lot),
                      icon: const Icon(Icons.contact_mail),
                      label: const Text('Inquire'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.4),
                ),
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
}

class _LotMapPreview extends StatefulWidget {
  const _LotMapPreview({required this.onInquire});

  final ValueChanged<Map<String, dynamic>> onInquire;

  @override
  State<_LotMapPreview> createState() => _LotMapPreviewState();
}

class _LotMapPreviewState extends State<_LotMapPreview> {
  static final LatLng _tagumMapCenter = LatLng(7.318551542, 125.662934679);
  static const double _initialZoom = 19;
  static const double _lotDetailZoom = 18.75;
  static const double _mapLatSpan = 0.0036;
  static const double _mapLngSpan = 0.0046;

  final MapController _mapController = MapController();
  final LayerHitNotifier<String> _lotPolygonHitNotifier = ValueNotifier(null);
  bool _isLoading = true;
  String? _errorMessage;
  double? _entranceXPercent;
  double? _entranceYPercent;
  LatLng _mapCenter = _tagumMapCenter;
  double _currentZoom = _initialZoom;
  double _activeMapLatSpan = _mapLatSpan;
  double _activeMapLngSpan = _mapLngSpan;
  List<Map<String, dynamic>> _lotMarkers = [];
  List<Map<String, dynamic>> _mapFeatures = [];
  Map<String, dynamic>? _selectedAvailableLot;
  LatLngBounds? _visibleLotBounds;
  Timer? _viewportUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadPreviewData();
  }

  @override
  void dispose() {
    _lotPolygonHitNotifier.dispose();
    _viewportUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreviewData() async {
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        supabase
            .from('cemetery_map')
            .select(
              'entrance_x_percent, entrance_y_percent, center_lat, center_lng, lat_span, lng_span',
            )
            .order('uploaded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        SupabasePaginationService.selectAll(
          supabase: supabase,
          table: 'lot_markers',
          orderColumn: 'marker_id',
          columns: '''
              marker_id,
              lot_id,
              x_percent,
              y_percent,
              cemetery_lot (
                lot_id,
                lot_number,
                lot_label,
                block_number,
                lot_class_type,
                polygon_geo,
                price,
                status
              )
            ''',
        ),
      ]);
      final mapFeatures = await MapFeatureService.loadVisible(supabase);

      if (!mounted) return;
      setState(() {
        final mapConfig = results[0] as Map<String, dynamic>?;
        final centerLat = (mapConfig?['center_lat'] as num?)?.toDouble();
        final centerLng = (mapConfig?['center_lng'] as num?)?.toDouble();
        if (centerLat != null && centerLng != null) {
          _mapCenter = LatLng(centerLat, centerLng);
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
        _mapFeatures = mapFeatures;
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
    if (!_hasMappedEntrance) return _mapCenter;
    return _percentToLatLng(_entranceXPercent!, _entranceYPercent!);
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _activeMapLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _activeMapLngSpan;
    final lat = _mapCenter.latitude + latOffset;
    final lng = _mapCenter.longitude + lngOffset;
    return LatLng(lat, lng);
  }

  LatLngBounds get _cemeteryCameraBounds {
    const marginFactor = 0.60;
    final latMargin = _activeMapLatSpan * marginFactor;
    final lngMargin = _activeMapLngSpan * marginFactor;
    return LatLngBounds(
      LatLng(_mapCenter.latitude - latMargin, _mapCenter.longitude - lngMargin),
      LatLng(_mapCenter.latitude + latMargin, _mapCenter.longitude + lngMargin),
    );
  }

  LatLng _markerToLatLng(Map<String, dynamic> marker) {
    final x = (marker['x_percent'] as num?)?.toDouble() ?? 50;
    final y = (marker['y_percent'] as num?)?.toDouble() ?? 50;
    return _percentToLatLng(x, y);
  }

  Color _statusColor(String? status) {
    return lotStatusStrokeColor(status);
  }

  void _selectAvailableLotById(String lotId) {
    final marker = _lotMarkers.cast<Map<String, dynamic>?>().firstWhere((
      marker,
    ) {
      final lot = marker?['cemetery_lot'];
      return lot is Map && lot['lot_id']?.toString() == lotId;
    }, orElse: () => null);
    final lot = marker?['cemetery_lot'];
    final status = lot is Map ? lot['status']?.toString().toLowerCase() : null;
    if (lot is Map && status == 'available') {
      setState(() => _selectedAvailableLot = Map<String, dynamic>.from(lot));
    }
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
          width: 28,
          height: 28,
          child: minimalistEntranceMarker(color: _primary),
        ),
      ..._lotMarkers.where((marker) => !markerHasLotPolygon(marker)).map((
        marker,
      ) {
        final lot = marker['cemetery_lot'] ?? {};
        final status = lot['status']?.toString() ?? '';
        final lotNumber = lotReference(lot, fallback: '');
        final color = _statusColor(status);
        final fillColor = lotStatusFillColor(status);
        final iconColor = lotStatusForegroundColor(status);
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
                  fillColor: fillColor,
                  iconColor: iconColor,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
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
    final selectedLotId = _selectedAvailableLot?['lot_id'];
    final visibleLotMarkers = _visibleLotBounds == null
        ? const <Map<String, dynamic>>[]
        : lotMarkersWithinBounds(_lotMarkers, _visibleLotBounds!);
    final lotPolygons = _currentZoom >= _lotDetailZoom
        ? lotPolygonsFromMarkers(
            visibleLotMarkers,
            selectedLotId: selectedLotId,
            includeHitValues: true,
            lowDetail: _currentZoom < 20,
          )
        : <Polygon<String>>[];
    final previewMapFeatures = _mapFeatures
        .where(isPublicPreviewMapFeature)
        .toList();
    final baseMapFeatures = previewMapFeatures
        .where(isMapLayerFeature)
        .toList();
    final overlayMapFeatures = previewMapFeatures
        .where((feature) => !isMapLayerFeature(feature))
        .toList();
    final basePolygons = mapFeaturePolygons(baseMapFeatures);
    final basePolylines = mapFeaturePolylines(baseMapFeatures);
    final overlayPolygons = mapFeaturePolygons(overlayMapFeatures);
    final overlayPolylines = mapFeaturePolylines(overlayMapFeatures);
    final overlayPointMarkers = mapFeaturePointMarkers(
      overlayMapFeatures
          .where((feature) => mapFeatureType(feature) != 'entrance')
          .toList(),
    );

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _entranceLatLng,
            initialZoom: _initialZoom,
            minZoom: 18.5,
            maxZoom: 22,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: _cemeteryCameraBounds,
            ),
            onMapReady: () {
              if (!mounted) return;
              setState(() {
                _visibleLotBounds = _mapController.camera.visibleBounds;
              });
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onPositionChanged: (position, _) {
              final wasShowingLots = _currentZoom >= _lotDetailZoom;
              _currentZoom = position.zoom;
              final isShowingLots = _currentZoom >= _lotDetailZoom;
              if (wasShowingLots != isShowingLots && mounted) setState(() {});
              _viewportUpdateTimer?.cancel();
              _viewportUpdateTimer = Timer(
                const Duration(milliseconds: 140),
                () {
                  if (!mounted) return;
                  setState(() => _visibleLotBounds = position.visibleBounds);
                },
              );
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.cemetery_app',
              maxZoom: 22,
              maxNativeZoom: 19,
              keepBuffer: 1,
            ),
            if (basePolygons.isNotEmpty) PolygonLayer(polygons: basePolygons),
            if (basePolylines.isNotEmpty)
              PolylineLayer(polylines: basePolylines),
            if (overlayPolygons.isNotEmpty)
              PolygonLayer(polygons: overlayPolygons),
            if (lotPolygons.isNotEmpty)
              GestureDetector(
                onTap: () {
                  final hitValues = _lotPolygonHitNotifier.value?.hitValues;
                  if (hitValues == null || hitValues.isEmpty) return;
                  _selectAvailableLotById(hitValues.last);
                },
                child: PolygonLayer<String>(
                  polygons: lotPolygons,
                  hitNotifier: _lotPolygonHitNotifier,
                ),
              ),
            if (overlayPolylines.isNotEmpty)
              PolylineLayer(polylines: overlayPolylines),
            if (overlayPointMarkers.isNotEmpty)
              MarkerLayer(markers: overlayPointMarkers),
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 17, color: _onSurface),
                SizedBox(width: 7),
                Text(
                  'Cemetery Map',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _onSurface,
                  ),
                ),
              ],
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
                _LegendDot(
                  color: lotStatusAvailableFill,
                  borderColor: lotStatusAvailableStroke,
                  label: 'Available',
                ),
                _LegendDot(
                  color: lotStatusReservedFill,
                  borderColor: lotStatusReservedStroke,
                  label: 'Owner assigned',
                ),
                _LegendDot(
                  color: lotStatusOccupiedFill,
                  borderColor: lotStatusOccupiedStroke,
                  label: 'Occupied',
                ),
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
    final lotNumber = lotReference(lot);
    final meta = lotMeta(lot);
    final locationText = meta.isEmpty ? lotBlockLabel(lot) : meta;
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
                  locationText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _onSurfaceVariant,
                    fontSize: 12,
                  ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
    final numeric = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 2,
    ).format(numeric);
  }
}

class _PreviewPin extends StatelessWidget {
  const _PreviewPin({
    required this.color,
    required this.icon,
    required this.size,
    this.filled = false,
    this.fillColor,
    this.iconColor,
  });

  final Color color;
  final IconData icon;
  final double size;
  final bool filled;
  final Color? fillColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            fillColor ??
            (filled ? color.withValues(alpha: 0.18) : Colors.white),
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
      child: Icon(icon, color: iconColor ?? color, size: size * 0.42),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor ?? color),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: _onSurface)),
      ],
    );
  }
}
