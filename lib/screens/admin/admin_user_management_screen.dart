import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/audit_service.dart';

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
      final result = await supabase
          .from('users')
          .select('user_id, name, email, phone, role')
          .order('name', ascending: true);

      setState(() {
        _users = List<Map<String, dynamic>>.from(result);
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
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query) ||
            role.contains(query);
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
      builder: (context) => _UserFormDialog(user: user),
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

      if (isEditing) {
        final updateData = <String, dynamic>{
          'name': name,
          'email': email,
          'phone': phone,
          'role': role,
        };

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

        await _createAuthUser(
          name: name,
          email: email,
          phone: phone,
          role: role,
          password: password,
        );

        await AuditService.log(
          action: 'CREATE_USER',
          entityType: 'user',
          entityId: email,
          details: 'Created user $name ($role)',
        );
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

  Future<void> _createAuthUser({
    required String name,
    required String email,
    required String phone,
    required String role,
    required String password,
  }) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.functions.invoke(
        'admin-user-management',
        body: {
          'action': 'create',
          'name': name,
          'email': email,
          'phone': phone,
          'role': role,
          'password': password,
        },
      );

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
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
    return {
      'all': _users.length,
      'admins': admins,
      'officers': officers,
      'visitors': visitors,
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
  const _UserFormDialog({this.user});

  final Map<String, dynamic>? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  String _role = 'visitor';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user?['name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: widget.user?['email']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.user?['phone']?.toString() ?? '',
    );
    _passwordController = TextEditingController();
    _role = widget.user?['role']?.toString() ?? 'visitor';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.user != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
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
                const SizedBox(height: 12),
                _Field(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
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
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: _fieldDecoration('Role', Icons.group_rounded),
                  items: const [
                    DropdownMenuItem(value: 'visitor', child: Text('Visitor')),
                    DropdownMenuItem(
                      value: 'lot_owner',
                      child: Text('Lot Owner'),
                    ),
                    DropdownMenuItem(
                      value: 'gate_officer',
                      child: Text('Gate Officer'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _role = value);
                    }
                  },
                ),
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
                          Navigator.pop(context, {
                            'name': _nameController.text,
                            'email': _emailController.text,
                            'phone': _phoneController.text,
                            'role': _role,
                            'password': _passwordController.text,
                          });
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.obscureText = false,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool obscureText;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      readOnly: readOnly,
      validator: validator,
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
