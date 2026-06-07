import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/audit_service.dart';
import '../../utils/lot_formatters.dart';
import '../../widgets/app_date_field.dart';

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

String? _textOrNull(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _intOrNull(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

double? _moneyOrNull(String? value) {
  final text =
      value
          ?.trim()
          .toUpperCase()
          .replaceAll('PHP', '')
          .replaceAll('₱', '')
          .replaceAll(',', '') ??
      '';
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String _fullNameFromParts({
  required String firstName,
  required String middleName,
  required String lastName,
}) {
  return [
    firstName.trim(),
    middleName.trim(),
    lastName.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
}

String? _choiceOrNull(String? value, List<String> choices) {
  final text = value?.trim().toLowerCase() ?? '';
  if (text.isEmpty) return null;
  for (final choice in choices) {
    if (choice.toLowerCase() == text) return choice;
  }
  return null;
}

String _purchaseTermValue(String? value) {
  final text = value?.trim().toLowerCase().replaceAll(' ', '_') ?? '';
  if (text == 'at_need') return 'at_need';
  return 'cash';
}

Map<String, dynamic> _lotOwnerProfilePayload(Map<String, String> result) {
  return {
    'control_number': _textOrNull(result['control_number']),
    'first_name': _textOrNull(result['first_name']),
    'middle_name': _textOrNull(result['middle_name']),
    'last_name': _textOrNull(result['last_name']),
    'address': _textOrNull(result['address']),
    'occupation': _textOrNull(result['occupation']),
    'age': _intOrNull(result['age']),
    'civil_status': _textOrNull(result['civil_status']),
    'date_of_birth': _textOrNull(result['date_of_birth']),
    'gender': _textOrNull(result['gender']),
    'spouse_beneficiary': _textOrNull(result['spouse_beneficiary']),
    'beneficiary_relationship': _textOrNull(result['beneficiary_relationship']),
    'lot_class_type': _textOrNull(result['lot_class_type']),
    'block_number': _textOrNull(result['block_number']),
    'lot_number': _textOrNull(result['lot_number']),
    'number_of_lots': _intOrNull(result['number_of_lots']),
    'purchase_term': _textOrNull(result['purchase_term']),
    'lot_price': _moneyOrNull(result['lot_price']),
    'interment_fee': _moneyOrNull(result['interment_fee']),
    'certification_fee': _moneyOrNull(result['certification_fee']),
    'burial_permit_fee': _moneyOrNull(result['burial_permit_fee']),
    'total_amount': _moneyOrNull(result['total_amount']),
    'or_number': _textOrNull(result['or_number']),
    'receipt_amount': _moneyOrNull(result['receipt_amount']),
    'receipt_date': _textOrNull(result['receipt_date']),
    'approved_date': _textOrNull(result['approved_date']),
    'approved_by_name': _textOrNull(result['approved_by_name']),
    'approval_signature': _textOrNull(result['approval_signature']),
  };
}

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key, this.onMenuPressed});

  final VoidCallback? onMenuPressed;

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _lots = [];
  bool _isLoading = true;
  String _selectedRoleFilter = 'All';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applyFilters)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase
            .from('users')
            .select('''
              user_id,
              name,
              email,
              phone,
              role,
              $_lotOwnerProfileSelect
            ''')
            .order('name', ascending: true),
        supabase
            .from('cemetery_lot')
            .select(
              'lot_id, lot_number, lot_label, block_number, lot_class_type, price, status',
            )
            .order('block_number')
            .order('lot_number'),
        supabase
            .from('lot_ownership')
            .select('ownership_id, user_id, lot_id, total_months, status')
            .order('ownership_id'),
      ]);

      final ownershipByUserId = <String, Map<String, dynamic>>{};
      for (final ownership in results[2] as List) {
        final row = Map<String, dynamic>.from(ownership);
        final userId = row['user_id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          ownershipByUserId[userId] = row;
        }
      }

      final users = (results[0] as List).map((user) {
        final row = Map<String, dynamic>.from(user);
        final ownership = ownershipByUserId[row['user_id']?.toString() ?? ''];
        if (ownership != null) {
          row['linked_lot_id'] = ownership['lot_id'];
          row['linked_ownership_id'] = ownership['ownership_id'];
          row['linked_total_months'] = ownership['total_months'];
        }
        return row;
      }).toList();

      setState(() {
        _users = users;
        _lots = List<Map<String, dynamic>>.from(results[1] as List);
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading users: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(_users);

    if (_selectedRoleFilter != 'All') {
      data = data.where((user) {
        final role = (user['role'] ?? '').toString().toLowerCase();
        return role == _selectedRoleFilter.toLowerCase();
      }).toList();
    }

    if (query.isNotEmpty) {
      data = data.where((user) {
        final name = (user['name'] ?? '').toString().toLowerCase();
        final email = (user['email'] ?? '').toString().toLowerCase();
        final phone = (user['phone'] ?? '').toString().toLowerCase();
        final role = (user['role'] ?? '').toString().toLowerCase();
        final controlNumber = (user['control_number'] ?? '')
            .toString()
            .toLowerCase();
        final address = (user['address'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query) ||
            role.contains(query) ||
            controlNumber.contains(query) ||
            address.contains(query);
      }).toList();
    }

    if (!mounted) return;
    setState(() => _filteredUsers = data);
  }

  Future<void> _refresh() => _loadUsers();

  Future<void> _showUserDialog({Map<String, dynamic>? user}) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UserFormDialog(user: user, lots: _lots),
    );

    if (result == null) return;

    try {
      final supabase = Supabase.instance.client;
      final isEditing = user != null;
      final userId = user?['user_id']?.toString();
      final email = result['email']!.trim().toLowerCase();
      final name = result['name']!.trim();
      final phone = result['phone']!.trim();
      final role = result['role']!.trim();
      final lotOwnerProfile = role == 'lot_owner'
          ? _lotOwnerProfilePayload(result)
          : null;
      String? createdUserId;

      if (isEditing) {
        final updateData = <String, dynamic>{
          'name': name,
          'email': email,
          'phone': phone,
          'role': role,
        };
        if (lotOwnerProfile != null) {
          updateData.addAll(lotOwnerProfile);
        }

        final target = userId != null && userId.isNotEmpty
            ? supabase.from('users').update(updateData).eq('user_id', userId)
            : supabase
                  .from('users')
                  .update(updateData)
                  .eq('email', user['email']);

        await target;

        await AuditService.log(
          action: 'UPDATE_USER',
          entityType: 'user',
          entityId: userId ?? email,
          details: 'Updated user $name ($role)',
        );
      } else {
        final password = result['password']!.trim();

        createdUserId = await _createAuthUser(
          name: name,
          email: email,
          phone: phone,
          role: role,
          password: password,
          lotOwnerProfile: lotOwnerProfile,
        );

        await AuditService.log(
          action: 'CREATE_USER',
          entityType: 'user',
          entityId: email,
          details: 'Created user $name ($role)',
        );
      }

      final syncedUserId = isEditing
          ? userId
          : createdUserId ?? await _findUserIdByEmail(email);
      if (role == 'lot_owner' && syncedUserId != null) {
        await _syncLotOwnerLotLink(userId: syncedUserId, result: result);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'User updated!' : 'User created!'),
          backgroundColor: const Color(0xFF335538),
        ),
      );
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving user: $e'),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
    }
  }

  Future<String?> _createAuthUser({
    required String name,
    required String email,
    required String phone,
    required String role,
    required String password,
    Map<String, dynamic>? lotOwnerProfile,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      final body = <String, dynamic>{
        'action': 'create',
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'password': password,
      };
      if (lotOwnerProfile != null) {
        body['lotOwnerProfile'] = lotOwnerProfile;
      }

      final response = await supabase.functions.invoke(
        'admin-user-management',
        body: body,
      );

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      if (data is Map) {
        final user = data['user'];
        if (user is Map) return user['id']?.toString();
      }
      return null;
    } catch (e) {
      final message = e.toString();
      if (message.contains('Failed to fetch') ||
          message.contains('ClientException')) {
        throw Exception(
          'Unable to reach the Supabase edge function "admin-user-management". '
          'Deploy it in Supabase or check the project URL and function name.',
        );
      }
      rethrow;
    }
  }

  Future<String?> _findUserIdByEmail(String email) async {
    final user = await Supabase.instance.client
        .from('users')
        .select('user_id')
        .eq('email', email)
        .maybeSingle();
    return user?['user_id']?.toString();
  }

  Future<void> _syncLotOwnerLotLink({
    required String userId,
    required Map<String, String> result,
  }) async {
    final supabase = Supabase.instance.client;
    final selectedLotId = int.tryParse(result['linked_lot_id'] ?? '');
    final resolvedLotId =
        selectedLotId ?? await _findLotIdFromLotDetails(result);

    if (resolvedLotId == null) {
      final hasLotDetails = [
        result['block_number'],
        result['lot_number'],
        result['lot_class_type'],
      ].any((value) => (value ?? '').trim().isNotEmpty);
      if (hasLotDetails) {
        throw Exception(
          'Select the linked app lot so the owner dashboard can show it.',
        );
      }
      return;
    }

    final lotData = <String, dynamic>{'status': 'Reserved'};
    final blockNumber = _textOrNull(result['block_number']);
    final lotNumber = _textOrNull(result['lot_number']);
    final lotClassType = _textOrNull(result['lot_class_type']);
    final lotPrice = _moneyOrNull(result['lot_price']);

    if (blockNumber != null) lotData['block_number'] = blockNumber;
    if (lotNumber != null) {
      lotData['lot_number'] = lotNumber;
      lotData['lot_label'] = blockNumber == null
          ? lotNumber
          : '$blockNumber-$lotNumber';
    }
    if (lotClassType != null) lotData['lot_class_type'] = lotClassType;
    if (lotPrice != null) lotData['price'] = lotPrice;

    await supabase
        .from('cemetery_lot')
        .update(lotData)
        .eq('lot_id', resolvedLotId);

    final purchaseTerm = result['purchase_term']?.trim() ?? 'cash';
    final totalMonths = purchaseTerm == 'cash' ? 1 : 24;

    final existingForUser = await supabase
        .from('lot_ownership')
        .select('ownership_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (existingForUser != null) {
      await supabase
          .from('lot_ownership')
          .update({
            'lot_id': resolvedLotId,
            'total_months': totalMonths,
            'status': 'Active',
          })
          .eq('ownership_id', existingForUser['ownership_id']);
      return;
    }

    final existingForLot = await supabase
        .from('lot_ownership')
        .select('ownership_id, user_id')
        .eq('lot_id', resolvedLotId)
        .maybeSingle();

    if (existingForLot != null) {
      final existingUserId = existingForLot['user_id']?.toString();
      if (existingUserId != null &&
          existingUserId.isNotEmpty &&
          existingUserId != userId) {
        throw Exception('Selected lot is already linked to another owner.');
      }
      await supabase
          .from('lot_ownership')
          .update({
            'user_id': userId,
            'total_months': totalMonths,
            'status': 'Active',
          })
          .eq('ownership_id', existingForLot['ownership_id']);
      return;
    }

    await supabase.from('lot_ownership').insert({
      'user_id': userId,
      'lot_id': resolvedLotId,
      'total_months': totalMonths,
      'months_paid': 0,
      'start_date': DateTime.now().toIso8601String(),
      'status': 'Active',
    });
  }

  Future<int?> _findLotIdFromLotDetails(Map<String, String> result) async {
    final lotNumber = _textOrNull(result['lot_number']);
    if (lotNumber == null) return null;

    final blockNumber = _textOrNull(result['block_number']);
    final supabase = Supabase.instance.client;

    final rows = blockNumber == null
        ? await supabase
              .from('cemetery_lot')
              .select('lot_id')
              .eq('lot_number', lotNumber)
              .limit(1)
        : await supabase
              .from('cemetery_lot')
              .select('lot_id')
              .eq('block_number', blockNumber)
              .eq('lot_number', lotNumber)
              .limit(1);
    if (rows.isNotEmpty) {
      final lotId = rows.first['lot_id'];
      return lotId is int ? lotId : int.tryParse(lotId.toString());
    }
    return null;
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete user?'),
        content: Text(
          'Remove ${user['name'] ?? 'this user'} from the directory?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFBA1A1A)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final supabase = Supabase.instance.client;
      final userId = user['user_id']?.toString();
      final email = user['email']?.toString();

      if (userId != null && userId.isNotEmpty) {
        await supabase.from('users').delete().eq('user_id', userId);
      } else if (email != null && email.isNotEmpty) {
        await supabase.from('users').delete().eq('email', email);
      }

      await AuditService.log(
        action: 'DELETE_USER',
        entityType: 'user',
        entityId: userId ?? email ?? '',
        details: 'Deleted user ${user['name'] ?? 'Unknown'}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User deleted!'),
          backgroundColor: Color(0xFF335538),
        ),
      );
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting user: $e'),
          backgroundColor: const Color(0xFFBA1A1A),
        ),
      );
    }
  }

  Map<String, int> get _summaryCounts {
    final admins = _users.where((u) => _roleKey(u['role']) == 'admin').length;
    final officers = _users
        .where((u) => _roleKey(u['role']) == 'gate_officer')
        .length;
    final visitors = _users
        .where((u) => _roleKey(u['role']) == 'visitor')
        .length;
    final owners = _users
        .where((u) => _roleKey(u['role']) == 'lot_owner')
        .length;
    return {
      'all': _users.length,
      'admins': admins,
      'officers': officers,
      'visitors': visitors,
      'owners': owners,
    };
  }

  @override
  Widget build(BuildContext context) {
    final counts = _summaryCounts;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFDAD6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFF93000A)),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User Management',
                      style: TextStyle(
                        color: Color(0xFF1B1C1A),
                        fontSize: 28,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage administrative staff, field officers, and visitor access permissions.',
                      style: TextStyle(color: Color(0xFF424841), fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showUserDialog(),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF335538),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              return compact
                  ? Column(
                      children: [
                        _SummaryStrip(counts: counts),
                        const SizedBox(height: 14),
                        _SearchField(controller: _searchController),
                        const SizedBox(height: 12),
                        _RoleChips(
                          selected: _selectedRoleFilter,
                          onChanged: (value) {
                            setState(() => _selectedRoleFilter = value);
                            _applyFilters();
                          },
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                title: 'Total Users',
                                value: counts['all'].toString(),
                                icon: Icons.group_rounded,
                                color: const Color(0xFFC5EDC6),
                                textColor: const Color(0xFF335538),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                title: 'Admins',
                                value: counts['admins'].toString(),
                                icon: Icons.verified_user_rounded,
                                color: const Color(0xFFC7E4F3),
                                textColor: const Color(0xFF2F4A57),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                title: 'Gate Officers',
                                value: counts['officers'].toString(),
                                icon: Icons.badge_rounded,
                                color: const Color(0xFFF5DECE),
                                textColor: const Color(0xFF5A4B3F),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                title: 'Visitors',
                                value: counts['visitors'].toString(),
                                icon: Icons.person_rounded,
                                color: const Color(0xFFEAE8E5),
                                textColor: const Color(0xFF424841),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                title: 'Lot Owners',
                                value: counts['owners'].toString(),
                                icon: Icons.assignment_ind_rounded,
                                color: const Color(0xFFF5DECE),
                                textColor: const Color(0xFF5A4B3F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _SearchField(
                                controller: _searchController,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _RoleChips(
                              selected: _selectedRoleFilter,
                              onChanged: (value) {
                                setState(() => _selectedRoleFilter = value);
                                _applyFilters();
                              },
                              compact: false,
                            ),
                          ],
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.group_off_rounded,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No users found',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (final user in _filteredUsers) ...[
                  _UserCard(
                    user: user,
                    onEdit: () => _showUserDialog(user: user),
                    onDelete: () => _deleteUser(user),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  String _roleKey(dynamic role) {
    return (role ?? '').toString().toLowerCase();
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search by name, email or role...',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: Color(0xFF335538), width: 1.2),
        ),
      ),
    );
  }
}

class _RoleChips extends StatelessWidget {
  const _RoleChips({
    required this.selected,
    required this.onChanged,
    this.compact = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = const [
      'All',
      'admin',
      'gate_officer',
      'visitor',
      'lot_owner',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final item in items)
          ChoiceChip(
            selected: selected.toLowerCase() == item.toLowerCase(),
            label: Text(_label(item)),
            onSelected: (_) => onChanged(item),
            selectedColor: const Color(0xFFC5EDC6),
            backgroundColor: const Color(0xFFEAE8E5),
            labelStyle: TextStyle(
              color: selected.toLowerCase() == item.toLowerCase()
                  ? const Color(0xFF335538)
                  : const Color(0xFF424841),
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide.none,
            ),
          ),
      ],
    );
  }

  String _label(String role) {
    return switch (role) {
      'All' => 'All Users',
      'admin' => 'Admins',
      'gate_officer' => 'Gate Officers',
      'visitor' => 'Visitors',
      'lot_owner' => 'Lot Owners',
      _ => role,
    };
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactSummary(
            title: 'Total',
            value: counts['all'].toString(),
            color: const Color(0xFF335538),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactSummary(
            title: 'Admins',
            value: counts['admins'].toString(),
            color: const Color(0xFF2F4A57),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactSummary(
            title: 'Officers',
            value: counts['officers'].toString(),
            color: const Color(0xFF5A4B3F),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CompactSummary(
            title: 'Visitors',
            value: counts['visitors'].toString(),
            color: const Color(0xFF424841),
          ),
        ),
      ],
    );
  }
}

class _CompactSummary extends StatelessWidget {
  const _CompactSummary({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E2DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF424841),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.textColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E2DF)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: textColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF424841),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = user['name']?.toString() ?? 'Unknown';
    final email = user['email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '';
    final role = user['role']?.toString() ?? 'visitor';
    final controlNumber = user['control_number']?.toString() ?? '';
    final address = user['address']?.toString() ?? '';
    final initials = _initials(name);
    final roleStyle = _roleStyle(role);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: roleStyle.background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: roleStyle.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF1B1C1A),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: roleStyle.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _roleLabel(role),
                        style: TextStyle(
                          color: roleStyle.foreground,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFF424841),
                    fontSize: 13,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: const TextStyle(
                      color: Color(0xFF424841),
                      fontSize: 13,
                    ),
                  ),
                ],
                if (role == 'lot_owner' && controlNumber.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Control No. $controlNumber',
                    style: const TextStyle(
                      color: Color(0xFF5A4B3F),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (role == 'lot_owner' && address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF424841),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            color: const Color(0xFF335538),
            tooltip: 'Edit user',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: const Color(0xFFBA1A1A),
            tooltip: 'Delete user',
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first.substring(0, 1).toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '?';
    final second = parts[1].isNotEmpty ? parts[1][0] : '?';
    return (first + second).toUpperCase();
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'gate_officer':
        return 'Gate Officer';
      case 'lot_owner':
        return 'Lot Owner';
      case 'visitor':
      default:
        return 'Visitor';
    }
  }

  _RoleStyle _roleStyle(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const _RoleStyle(
          background: Color(0xFFC5EDC6),
          foreground: Color(0xFF335538),
        );
      case 'gate_officer':
        return const _RoleStyle(
          background: Color(0xFFC7E4F3),
          foreground: Color(0xFF2F4A57),
        );
      case 'lot_owner':
        return const _RoleStyle(
          background: Color(0xFFF5DECE),
          foreground: Color(0xFF5A4B3F),
        );
      case 'visitor':
      default:
        return const _RoleStyle(
          background: Color(0xFFEAE8E5),
          foreground: Color(0xFF424841),
        );
    }
  }
}

class _RoleStyle {
  const _RoleStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user, required this.lots});

  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> lots;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late final TextEditingController _controlNumberController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _occupationController;
  late final TextEditingController _ageController;
  late final TextEditingController _dateOfBirthController;
  late final TextEditingController _spouseBeneficiaryController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _lotClassTypeController;
  late final TextEditingController _blockNumberController;
  late final TextEditingController _lotNumberController;
  late final TextEditingController _numberOfLotsController;
  late final TextEditingController _lotPriceController;
  late final TextEditingController _intermentFeeController;
  late final TextEditingController _certificationFeeController;
  late final TextEditingController _burialPermitFeeController;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _orNumberController;
  late final TextEditingController _receiptAmountController;
  late final TextEditingController _receiptDateController;
  late final TextEditingController _approvedDateController;
  late final TextEditingController _approvedByNameController;
  late final TextEditingController _approvalSignatureController;
  String _role = 'visitor';
  String? _civilStatus;
  String? _gender;
  String? _linkedLotId;
  String _purchaseTerm = 'cash';

  bool get _isLotOwner => _role == 'lot_owner';

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _nameController = TextEditingController(
      text: user?['name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: user?['email']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: user?['phone']?.toString() ?? '',
    );
    _passwordController = TextEditingController();
    _controlNumberController = _controller(user, 'control_number');
    _firstNameController = _controller(user, 'first_name');
    _middleNameController = _controller(user, 'middle_name');
    _lastNameController = _controller(user, 'last_name');
    _addressController = _controller(user, 'address');
    _occupationController = _controller(user, 'occupation');
    _ageController = _controller(user, 'age');
    _dateOfBirthController = _controller(user, 'date_of_birth');
    _spouseBeneficiaryController = _controller(user, 'spouse_beneficiary');
    _relationshipController = _controller(user, 'beneficiary_relationship');
    _lotClassTypeController = _controller(user, 'lot_class_type');
    _blockNumberController = _controller(user, 'block_number');
    _lotNumberController = _controller(user, 'lot_number');
    _numberOfLotsController = _controller(user, 'number_of_lots');
    _lotPriceController = _moneyController(user, 'lot_price');
    _intermentFeeController = _moneyController(user, 'interment_fee');
    _certificationFeeController = _moneyController(user, 'certification_fee');
    _burialPermitFeeController = _moneyController(user, 'burial_permit_fee');
    _totalAmountController = _moneyController(user, 'total_amount');
    _lotPriceController.addListener(_updateTotalAmount);
    _intermentFeeController.addListener(_updateTotalAmount);
    _certificationFeeController.addListener(_updateTotalAmount);
    _burialPermitFeeController.addListener(_updateTotalAmount);
    _orNumberController = _controller(user, 'or_number');
    _receiptAmountController = _moneyController(user, 'receipt_amount');
    _receiptDateController = _controller(user, 'receipt_date');
    _approvedDateController = _controller(user, 'approved_date');
    _approvedByNameController = _controller(user, 'approved_by_name');
    _approvalSignatureController = _controller(user, 'approval_signature');
    _role = user?['role']?.toString() ?? 'visitor';
    _linkedLotId = user?['linked_lot_id']?.toString();
    if (_linkedLotId != null &&
        !widget.lots.any((lot) => lot['lot_id']?.toString() == _linkedLotId)) {
      _linkedLotId = null;
    }
    _civilStatus = _choiceOrNull(user?['civil_status']?.toString(), const [
      'Single',
      'Married',
      'Widowed',
      'Separated',
    ]);
    _gender = _choiceOrNull(user?['gender']?.toString(), const [
      'Male',
      'Female',
    ]);
    _purchaseTerm = _purchaseTermValue(user?['purchase_term']?.toString());
    if (_isLotOwner) {
      _seedNamePartsFromFullName();
    }
    _updateTotalAmount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _controlNumberController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _occupationController.dispose();
    _ageController.dispose();
    _dateOfBirthController.dispose();
    _spouseBeneficiaryController.dispose();
    _relationshipController.dispose();
    _lotClassTypeController.dispose();
    _blockNumberController.dispose();
    _lotNumberController.dispose();
    _numberOfLotsController.dispose();
    _lotPriceController.removeListener(_updateTotalAmount);
    _intermentFeeController.removeListener(_updateTotalAmount);
    _certificationFeeController.removeListener(_updateTotalAmount);
    _burialPermitFeeController.removeListener(_updateTotalAmount);
    _lotPriceController.dispose();
    _intermentFeeController.dispose();
    _certificationFeeController.dispose();
    _burialPermitFeeController.dispose();
    _totalAmountController.dispose();
    _orNumberController.dispose();
    _receiptAmountController.dispose();
    _receiptDateController.dispose();
    _approvedDateController.dispose();
    _approvedByNameController.dispose();
    _approvalSignatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.user != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF9F6),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE4E2DF)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit User' : 'Add User',
                        style: const TextStyle(
                          color: Color(0xFF1B1C1A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create a Supabase Auth account and cemetery directory profile.',
                  style: TextStyle(color: Color(0xFF424841), fontSize: 13),
                ),
                const SizedBox(height: 20),
                _Field(
                  controller: _emailController,
                  label: 'Email Address',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: isEditing,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!value.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                if (!isEditing) ...[
                  const SizedBox(height: 12),
                  _Field(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_rounded,
                    keyboardType: TextInputType.visiblePassword,
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required';
                      }
                      if (value.trim().length < 6) {
                        return 'Use at least 6 characters';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                _roleDropdown(),
                const SizedBox(height: 16),
                if (_isLotOwner)
                  ..._lotOwnerFields()
                else
                  ..._standardUserFields(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (!_formKey.currentState!.validate()) return;
                          Navigator.pop(context, _formResult());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF335538),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(isEditing ? 'Save Changes' : 'Create User'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextEditingController _controller(Map<String, dynamic>? user, String key) {
    return TextEditingController(text: user?[key]?.toString() ?? '');
  }

  TextEditingController _moneyController(
    Map<String, dynamic>? user,
    String key,
  ) {
    final value = user?[key];
    if (value == null) return TextEditingController();
    final numeric = value is num ? value.toDouble() : double.tryParse('$value');
    return TextEditingController(
      text: numeric == null ? value.toString() : numeric.toStringAsFixed(2),
    );
  }

  void _seedNamePartsFromFullName() {
    if (_firstNameController.text.trim().isNotEmpty ||
        _lastNameController.text.trim().isNotEmpty) {
      return;
    }

    final parts = _nameController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    _firstNameController.text = parts.first;
    if (parts.length == 2) {
      _lastNameController.text = parts.last;
    } else if (parts.length > 2) {
      _middleNameController.text = parts.sublist(1, parts.length - 1).join(' ');
      _lastNameController.text = parts.last;
    }
  }

  Widget _roleDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _role,
      decoration: _fieldDecoration('Role', Icons.group_rounded),
      items: const [
        DropdownMenuItem(value: 'visitor', child: Text('Visitor')),
        DropdownMenuItem(value: 'lot_owner', child: Text('Lot Owner')),
        DropdownMenuItem(value: 'gate_officer', child: Text('Gate Officer')),
        DropdownMenuItem(value: 'admin', child: Text('Admin')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _role = value;
          if (_isLotOwner) {
            _seedNamePartsFromFullName();
          }
        });
      },
    );
  }

  List<Widget> _standardUserFields() {
    return [
      _Field(
        controller: _nameController,
        label: 'Full Name',
        icon: Icons.person_rounded,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Name is required';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      _Field(
        controller: _phoneController,
        label: 'Phone Number',
        icon: Icons.phone_rounded,
        keyboardType: TextInputType.phone,
      ),
    ];
  }

  List<Widget> _lotOwnerFields() {
    return [
      const _SectionTitle(
        icon: Icons.assignment_ind_rounded,
        title: "Purchaser's Profile",
      ),
      const SizedBox(height: 12),
      _Field(
        controller: _controlNumberController,
        label: 'Control No.',
        icon: Icons.tag_rounded,
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _Field(
          controller: _lastNameController,
          label: 'Last Name',
          icon: Icons.person_rounded,
          validator: (value) {
            if (_isLotOwner && (value == null || value.trim().isEmpty)) {
              return 'Last name is required';
            }
            return null;
          },
        ),
        _Field(
          controller: _firstNameController,
          label: 'First Name',
          icon: Icons.person_rounded,
          validator: (value) {
            if (_isLotOwner && (value == null || value.trim().isEmpty)) {
              return 'First name is required';
            }
            return null;
          },
        ),
        _Field(
          controller: _middleNameController,
          label: 'Middle Name',
          icon: Icons.person_outline_rounded,
        ),
        _Field(
          controller: _phoneController,
          label: 'Mobile',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
      ]),
      const SizedBox(height: 12),
      _Field(
        controller: _addressController,
        label: 'Address',
        icon: Icons.home_outlined,
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _Field(
          controller: _occupationController,
          label: 'Occupation',
          icon: Icons.work_outline_rounded,
        ),
        _Field(
          controller: _ageController,
          label: 'Age',
          icon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
        ),
        DropdownButtonFormField<String>(
          initialValue: _civilStatus,
          decoration: _fieldDecoration(
            'Civil Status',
            Icons.favorite_border_rounded,
          ),
          items: const [
            DropdownMenuItem(value: 'Single', child: Text('Single')),
            DropdownMenuItem(value: 'Married', child: Text('Married')),
            DropdownMenuItem(value: 'Widowed', child: Text('Widowed')),
            DropdownMenuItem(value: 'Separated', child: Text('Separated')),
          ],
          onChanged: (value) => setState(() => _civilStatus = value),
        ),
        _DateField(
          controller: _dateOfBirthController,
          label: 'Date of Birth',
          icon: Icons.event_rounded,
          lastDate: DateTime.now(),
          onChanged: _updateAgeFromBirthDate,
        ),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: _fieldDecoration('Gender', Icons.wc_rounded),
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
          ],
          onChanged: (value) => setState(() => _gender = value),
        ),
        _Field(
          controller: _spouseBeneficiaryController,
          label: 'Spouse / Beneficiary',
          icon: Icons.diversity_1_rounded,
        ),
        _Field(
          controller: _relationshipController,
          label: 'Relationship',
          icon: Icons.handshake_outlined,
        ),
      ]),
      const SizedBox(height: 18),
      const _SectionTitle(
        icon: Icons.location_on_rounded,
        title: 'Lot Details',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _linkedLotId,
        isExpanded: true,
        decoration: _fieldDecoration('Linked App Lot', Icons.map_rounded),
        items: [
          const DropdownMenuItem(value: '', child: Text('No linked lot yet')),
          ...widget.lots.map((lot) {
            final lotId = lot['lot_id']?.toString() ?? '';
            final status = lot['status']?.toString() ?? 'Unknown';
            final meta = lotMeta(lot);
            final label = [
              lotReference(lot),
              if (meta.isNotEmpty) meta,
              status,
            ].join(' • ');
            return DropdownMenuItem(value: lotId, child: Text(label));
          }),
        ],
        onChanged: (value) {
          setState(() {
            _linkedLotId = value == null || value.isEmpty ? null : value;
            _applyLinkedLotDetails();
          });
        },
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _Field(
          controller: _lotClassTypeController,
          label: 'Lot Class / Type',
          icon: Icons.category_outlined,
        ),
        _Field(
          controller: _blockNumberController,
          label: 'Block',
          icon: Icons.grid_view_rounded,
        ),
        _Field(
          controller: _lotNumberController,
          label: 'Lot',
          icon: Icons.place_outlined,
        ),
        _Field(
          controller: _numberOfLotsController,
          label: 'No. of Lots',
          icon: Icons.format_list_numbered_rounded,
          keyboardType: TextInputType.number,
        ),
      ]),
      const SizedBox(height: 18),
      const _SectionTitle(icon: Icons.payments_outlined, title: 'Terms'),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'cash', label: Text('Cash')),
          ButtonSegment(value: 'at_need', label: Text('At Need')),
        ],
        selected: {_purchaseTerm},
        showSelectedIcon: false,
        onSelectionChanged: (values) {
          setState(() => _purchaseTerm = values.first);
        },
      ),
      const SizedBox(height: 18),
      const _SectionTitle(
        icon: Icons.receipt_long_outlined,
        title: 'Amount Payable',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _Field(
          controller: _lotPriceController,
          label: 'Lot Price',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          onChanged: (_) => _updateTotalAmount(),
        ),
        _Field(
          controller: _intermentFeeController,
          label: 'Interment Fee',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          onChanged: (_) => _updateTotalAmount(),
        ),
        _Field(
          controller: _certificationFeeController,
          label: 'Certification Fee',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          onChanged: (_) => _updateTotalAmount(),
        ),
        _Field(
          controller: _burialPermitFeeController,
          label: 'Burial Permit Fee',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          onChanged: (_) => _updateTotalAmount(),
        ),
        _Field(
          controller: _totalAmountController,
          label: 'Total',
          icon: Icons.summarize_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          readOnly: true,
        ),
      ]),
      const SizedBox(height: 18),
      const _SectionTitle(
        icon: Icons.approval_outlined,
        title: 'Receipt and Approval',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _Field(
          controller: _orNumberController,
          label: 'OR #',
          icon: Icons.confirmation_number_outlined,
        ),
        _Field(
          controller: _receiptAmountController,
          label: 'P',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
        ),
        _DateField(
          controller: _receiptDateController,
          label: 'Date',
          icon: Icons.event_note_outlined,
        ),
        _DateField(
          controller: _approvedDateController,
          label: 'Approved Date',
          icon: Icons.verified_outlined,
        ),
        _Field(
          controller: _approvedByNameController,
          label: 'Approved By',
          icon: Icons.badge_outlined,
        ),
        _Field(
          controller: _approvalSignatureController,
          label: 'Approver Signature',
          icon: Icons.draw_outlined,
        ),
      ]),
    ];
  }

  Widget _fieldGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }

  void _applyLinkedLotDetails() {
    final lotId = _linkedLotId;
    if (lotId == null || lotId.isEmpty) return;

    final lot = widget.lots.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['lot_id']?.toString() == lotId,
      orElse: () => null,
    );
    if (lot == null) return;

    final blockNumber = lotText(lot, 'block_number');
    final lotNumber = lotText(lot, 'lot_number');
    final lotClassType = lotText(lot, 'lot_class_type');
    final price = lot['price'];

    if (blockNumber.isNotEmpty) _blockNumberController.text = blockNumber;
    if (lotNumber.isNotEmpty) _lotNumberController.text = lotNumber;
    if (lotClassType.isNotEmpty) _lotClassTypeController.text = lotClassType;
    if (price != null && _lotPriceController.text.trim().isEmpty) {
      final numeric = price is num
          ? price.toDouble()
          : double.tryParse('$price');
      if (numeric != null) {
        _lotPriceController.text = numeric.toStringAsFixed(2);
        _updateTotalAmount();
      }
    }
  }

  Map<String, String> _formResult() {
    _updateTotalAmount();
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final fullName = _isLotOwner
        ? _fullNameFromParts(
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
          )
        : _nameController.text.trim();

    return {
      'name': fullName,
      'email': _emailController.text,
      'phone': _phoneController.text,
      'role': _role,
      'password': _passwordController.text,
      'linked_lot_id': _linkedLotId ?? '',
      'control_number': _controlNumberController.text,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'address': _addressController.text,
      'occupation': _occupationController.text,
      'age': _ageController.text,
      'civil_status': _civilStatus ?? '',
      'date_of_birth': _dateOfBirthController.text,
      'gender': _gender ?? '',
      'spouse_beneficiary': _spouseBeneficiaryController.text,
      'beneficiary_relationship': _relationshipController.text,
      'lot_class_type': _lotClassTypeController.text,
      'block_number': _blockNumberController.text,
      'lot_number': _lotNumberController.text,
      'number_of_lots': _numberOfLotsController.text,
      'purchase_term': _purchaseTerm,
      'lot_price': _lotPriceController.text,
      'interment_fee': _intermentFeeController.text,
      'certification_fee': _certificationFeeController.text,
      'burial_permit_fee': _burialPermitFeeController.text,
      'total_amount': _totalAmountController.text,
      'or_number': _orNumberController.text,
      'receipt_amount': _receiptAmountController.text,
      'receipt_date': _receiptDateController.text,
      'approved_date': _approvedDateController.text,
      'approved_by_name': _approvedByNameController.text,
      'approval_signature': _approvalSignatureController.text,
    };
  }

  void _updateAgeFromBirthDate(String value) {
    final birthDate = _DateField.parse(value);
    if (birthDate == null) {
      setState(_ageController.clear);
      return;
    }
    final today = DateTime.now();
    var age = today.year - birthDate.year;
    final birthdayHasPassed =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayHasPassed) age--;
    setState(() => _ageController.text = age.toString());
  }

  void _updateTotalAmount() {
    final total = [
      _lotPriceController.text,
      _intermentFeeController.text,
      _certificationFeeController.text,
      _burialPermitFeeController.text,
    ].fold<double>(0, (sum, value) => sum + (_moneyOrNull(value) ?? 0));
    _totalAmountController.text = total.toStringAsFixed(2);
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF335538)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF335538), width: 1.2),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF335538)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1B1C1A),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.icon,
    this.lastDate,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final DateTime? lastDate;
  final ValueChanged<String>? onChanged;

  static DateTime? parse(String value) {
    return AppDateField.parse(value);
  }

  @override
  Widget build(BuildContext context) {
    return AppDateField(
      controller: controller,
      label: label,
      icon: icon,
      lastDate: lastDate,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF335538)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF335538), width: 1.2),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.prefixText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool obscureText;
  final bool readOnly;
  final int maxLines;
  final String? prefixText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      validator: validator,
      maxLines: obscureText ? 1 : maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF335538)),
        prefixText: prefixText,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE4E2DF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF335538), width: 1.2),
        ),
      ),
    );
  }
}
