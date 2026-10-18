import '../../widgets/logout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/session_providers.dart';
import '../../models/app_user.dart';
import '../../widgets/theme_mode_switch_tile.dart';

class VisitorProfileScreen extends ConsumerStatefulWidget {
  const VisitorProfileScreen({super.key});

  @override
  ConsumerState<VisitorProfileScreen> createState() =>
      _VisitorProfileScreenState();
}

class _VisitorProfileScreenState extends ConsumerState<VisitorProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  int _savedMemorials = 0;
  String? _avatarUrl;
  bool _isUploadingPhoto = false;
  static const String _avatarBucket = 'avatars';

  final _editNameController = TextEditingController();
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

      final userData = await supabase
          .from('users')
          .select('*')
          .eq('email', user.email!)
          .maybeSingle();

      if (userData != null) {
        _userData = userData;
        _editNameController.text = userData['name'] ?? '';
        _avatarUrl = userData['avatar_url']?.toString();

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) throw Exception('Not logged in');

      await supabase
          .from('users')
          .update({'name': newName})
          .eq('email', user.email!);

      if (_userData != null) {
        _userData!['name'] = newName;
      }

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
          SnackBar(
            content: Text('Name updated!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
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

      await supabase.auth.updateUser(UserAttributes(password: newPassword));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password changed!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing password: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
    _showPhotoActions();
  }

  Future<void> _showPhotoActions() async {
    final choice = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(context, _PhotoAction.remove),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == _PhotoAction.gallery) {
      await _pickAndUploadProfilePhoto();
    } else if (choice == _PhotoAction.remove) {
      await _removeProfilePhoto();
    }
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1200,
    );

    if (image == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final bytes = await image.readAsBytes();
      final filePath =
          '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from(_avatarBucket)
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final publicUrl = supabase.storage
          .from(_avatarBucket)
          .getPublicUrl(filePath);

      await supabase
          .from('users')
          .update({'avatar_url': publicUrl})
          .eq('email', user.email!);

      if (!mounted) return;
      setState(() {
        _avatarUrl = publicUrl;
        if (_userData != null) {
          _userData!['avatar_url'] = publicUrl;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile photo updated!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading photo: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    setState(() => _isUploadingPhoto = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      await supabase
          .from('users')
          .update({'avatar_url': null})
          .eq('email', user.email!);

      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
        if (_userData != null) {
          _userData!['avatar_url'] = null;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile photo removed!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing photo: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  InputDecoration _profileFieldDecoration({
    required String labelText,
    required IconData icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, color: colors.primary),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colors.primary, width: 1.4),
      ),
    );
  }

  void _showEditNameDialog() {
    _editNameController.text = _userData?['name'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.badge_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Change Name',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: TextField(
            controller: _editNameController,
            decoration: _profileFieldDecoration(
              labelText: 'Full Name',
              icon: Icons.person_outline_rounded,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateDisplayName();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showChangePasswordDialog() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();

    showDialog(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                decoration: _profileFieldDecoration(
                  labelText: 'Current Password',
                  icon: Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: _profileFieldDecoration(
                  labelText: 'New Password',
                  icon: Icons.password_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: _profileFieldDecoration(
                  labelText: 'Confirm New Password',
                  icon: Icons.verified_user_outlined,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Change Password'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() => showLogoutDialog(context);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final displayName = _userData?['name'] ?? 'Loading...';
    final email = _userData?['email'] ?? '';
    final role = _userData?['role']?.toString().toUpperCase() ?? 'VISITOR';
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadUserData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: _buildTopBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(displayName, email, role),
            const SizedBox(height: 24),
            _buildSettingsCard(),
            const SizedBox(height: 24),
            _buildLogoutButton(),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'App Version 1.0.0',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopBar() {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: colors.surface.withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.menu_rounded, color: colors.primary),
            tooltip: 'Menu',
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              'Eternal Garden',
              style: TextStyle(
                color: colors.primary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: Icon(Icons.notifications_outlined, color: colors.primary),
          tooltip: 'Notifications',
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );
  }

  Widget _buildProfileHeader(String displayName, String email, String role) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final available = constraints.maxWidth - 16;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: compact ? constraints.maxWidth : available * 2 / 3,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F47626F),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage:
                              _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null || _avatarUrl!.isEmpty
                              ? Text(
                                  _initials(displayName),
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: InkWell(
                            onTap: _isUploadingPhoto
                                ? null
                                : _showEditPhotoDialog,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.onPrimary,
                                  width: 2,
                                ),
                              ),
                              child: _isUploadingPhoto
                                  ? SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.onPrimary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: colorScheme.onPrimary,
                                    ),
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
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 14,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  role == 'LOT_OWNER' ? 'Lot Owner' : role,
                                  style: textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSecondaryContainer,
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
              ),
            ),
            SizedBox(
              width: compact ? constraints.maxWidth : available / 3,
              child: Container(
                height: 172,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Saved Memorials',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimary.withValues(
                              alpha: 0.82,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.bookmark_rounded,
                          color: colorScheme.onPrimary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _savedMemorials.toString(),
                      style: textTheme.displayMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _savedMemorials == 1
                          ? '1 visit recorded'
                          : '$_savedMemorials visits recorded',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsCard() {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F47626F),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              child: Text(
                'Account Settings',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            _ProfileSettingTile(
              icon: Icons.person_outline_rounded,
              title: 'Change Name',
              subtitle: 'Update your display name',
              onTap: _showEditNameDialog,
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            _ProfileSettingTile(
              icon: Icons.lock_outline_rounded,
              title: 'Change Password',
              subtitle: 'Update your login password',
              onTap: _showChangePasswordDialog,
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const ThemeModeSwitchTile(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _logout,
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.errorContainer,
          foregroundColor: colorScheme.onErrorContainer,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Logout from Account'),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _ProfileSettingTile extends StatelessWidget {
  const _ProfileSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PhotoAction { gallery, remove }
