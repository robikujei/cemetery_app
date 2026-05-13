import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../providers/session_providers.dart';
import '../../models/app_user.dart';

class VisitorProfileScreen extends ConsumerStatefulWidget {
  const VisitorProfileScreen({super.key});

  @override
  ConsumerState<VisitorProfileScreen> createState() => _VisitorProfileScreenState();
}

class _VisitorProfileScreenState extends ConsumerState<VisitorProfileScreen> {
  static const Color _brandGreen = Color(0xFF4B6E4F);
  static const Color _errorContainer = Color(0xFFFFDAD6);
  static const Color _onErrorContainer = Color(0xFF93000A);
  
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  int _savedMemorials = 0;
  
  // Edit dialog controllers
  final _editNameController = TextEditingController();
  
  // Password change controllers
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          _errorMessage = 'Please log in';
          _isLoading = false;
        });
        return;
      }

      // Get user details from users table
      final userData = await supabase
          .from('users')
          .select('*')
          .eq('email', user.email!)
          .maybeSingle();

      if (userData != null) {
        _userData = userData;
        _editNameController.text = userData['name'] ?? '';
        
        // Get visit count
        final memorialsResult = await supabase
            .from('visitor_log')
            .select('log_id')
            .eq('user_id', user.id);
        
        _savedMemorials = memorialsResult.length;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateDisplayName() async {
    final newName = _editNameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) throw Exception('Not logged in');

      // Update users table
      await supabase
          .from('users')
          .update({'name': newName})
          .eq('email', user.email!);

      // Update local data
      if (_userData != null) {
        _userData!['name'] = newName;
      }

      // Update session provider
      final currentUser = ref.read(sessionProvider);
      if (currentUser != null) {
        final updatedUser = AppUser(
          id: currentUser.id,
          displayName: newName,
          role: currentUser.role,
        );
        ref.read(sessionProvider.notifier).state = updatedUser;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all password fields')),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // Update password via Supabase Auth
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed!'), backgroundColor: Colors.green),
        );
        // Clear password fields
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        // Close dialog if open
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error changing password: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showEditPhotoDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile photo update coming soon!')),
    );
  }

  void _showEditNameDialog() {
    _editNameController.text = _userData?['name'] ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: _editNameController,
          decoration: const InputDecoration(
            labelText: 'Full Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateDisplayName();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    // Reset controllers
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
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
    final user = Supabase.instance.client.auth.currentUser;
    
    // ✅ ADD AUDIT LOG FOR LOGOUT
    await AuditService.log(
      action: 'LOGOUT',
      entityType: 'user',
      entityId: user?.id,
      details: 'User logged out',
    );
    
    await Supabase.instance.client.auth.signOut();
    ref.read(sessionProvider.notifier).state = null;
    if (mounted) {
      context.go('/login');
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    
    final displayName = _userData?['name'] ?? 'Loading...';
    final email = _userData?['email'] ?? '';
    final role = _userData?['role']?.toString().toUpperCase() ?? 'VISITOR';

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadUserData,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.white.withOpacity(0.90),
          elevation: 0,
          leading: IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menu (next).')),
              );
            },
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF1B1C1A)),
          ),
          title: const Text(
            'Eternal Rest',
            style: TextStyle(
              color: _brandGreen,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF1B1C1A)),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 110),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // User Info Card
              _UserInfoCard(
                displayName: displayName,
                email: email,
                role: role,
                t: t,
                cs: cs,
                onEditPhotoTap: _showEditPhotoDialog,
              ),
              const SizedBox(height: 16),
              
              // Saved Memorials Card
              _SavedMemorialsCard(
                count: _savedMemorials,
                t: t,
                cs: cs,
              ),
              const SizedBox(height: 20),
              
              // Settings Card
              _SettingsCard(
                t: t,
                cs: cs,
                onEditNameTap: _showEditNameDialog,
                onChangePasswordTap: _showChangePasswordDialog,
              ),
              const SizedBox(height: 20),
              
              // Logout Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout from Account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _errorContainer,
                    foregroundColor: _onErrorContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'App Version 1.0.0',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: Colors.black45),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// User Info Card
// User Info Card
class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({
    required this.displayName,
    required this.email,
    required this.role,
    required this.t,
    required this.cs,
    required this.onEditPhotoTap,
  });

  final String displayName;
  final String email;
  final String role;
  final TextTheme t;
  final ColorScheme cs;
  final VoidCallback onEditPhotoTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF47626F).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: cs.surfaceContainerHighest,
                child: const Icon(Icons.person, size: 48, color: Color(0xFF4B6E4F)),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: InkWell(
                  onTap: onEditPhotoTap,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: t.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 16, color: cs.onSecondaryFixedVariant),
                      const SizedBox(width: 6),
                      Text(
                        role,
                        style: t.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSecondaryFixedVariant,
                        ),
                      ),
                    ],
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
// Saved Memorials Card
class _SavedMemorialsCard extends StatelessWidget {
  const _SavedMemorialsCard({
    required this.count,
    required this.t,
    required this.cs,
  });

  final int count;
  final TextTheme t;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Visits',
                style: t.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.history, color: cs.onPrimaryContainer),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: t.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count == 1 ? 'visit recorded' : 'visits recorded',
            style: t.labelSmall?.copyWith(
              color: cs.onPrimaryContainer.withOpacity(0.70),
            ),
          ),
        ],
      ),
    );
  }
}

// Settings Card - Now has separate callbacks
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.t,
    required this.cs,
    required this.onEditNameTap,
    required this.onChangePasswordTap,
  });

  final TextTheme t;
  final ColorScheme cs;
  final VoidCallback onEditNameTap;
  final VoidCallback onChangePasswordTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF47626F).withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Account Settings',
              style: t.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          Divider(height: 1, color: cs.surfaceContainerLow),
          _SettingTile(
            icon: Icons.person_outline,
            title: 'Edit Name',
            subtitle: 'Update your display name',
            onTap: onEditNameTap,  // ← Now updates name
            cs: cs,
            t: t,
          ),
          Divider(height: 1, color: cs.surfaceContainerLow),
          _SettingTile(
            icon: Icons.lock_outline,
            title: 'Change Password',
            subtitle: 'Update your login password',
            onTap: onChangePasswordTap,  // ← Now updates password
            cs: cs,
            t: t,
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cs,
    required this.t,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final ColorScheme cs;
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}