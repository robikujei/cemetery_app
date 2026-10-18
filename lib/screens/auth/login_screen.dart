import '../../core/app_colors.dart';
import '../../core/surface_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../models/app_user.dart';
import '../../providers/session_providers.dart';
import '../../utils/sign_in_error_message.dart';

// ── Design tokens (mirrors the HTML template's Tailwind config) ──────────────
class _C {
  static const background = AppColors.background;
  static const primary = AppColors.brandDark;
  static const primaryContainer = AppColors.brand;
  static const onPrimaryContainer = AppColors.onBrand;
  static const primaryFixed = AppColors.brandLight;
  static const surfaceContainerHighest = AppColors.surfaceHighest;
  static const onSurface = AppColors.text;
  static const onSurfaceVariant = AppColors.textSecondary;
  static const outline = AppColors.textMuted;
  static const outlineVariant = AppColors.border;
  static const error = Color(0xFFBA1A1A);
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.requiredRole, this.portalName});

  /// When set, this portal accepts only accounts with this database role.
  final String? requiredRole;
  final String? portalName;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    if (email.isEmpty) return false;
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }

  bool _validateForm() {
    bool isValid = true;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      isValid = false;
    } else if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Please enter a valid email address');
      isValid = false;
    } else {
      setState(() => _emailError = null);
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _passwordError = 'Please enter your password');
      isValid = false;
    } else {
      setState(() => _passwordError = null);
    }
    return isValid;
  }

  Future<void> _signInWithSupabase() async {
    if (!_validateForm()) return;
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passwordCtrl.text,
      );
      if (response.user != null) {
        final userData = await _loadUserProfile(response.user!);
        if (userData == null) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            'Your account is valid, but its portal profile is missing. Contact an administrator.',
          );
          return;
        }

        final actualRole = userData['role']?.toString().trim().toLowerCase();
        final requiredRole = widget.requiredRole?.trim().toLowerCase();
        if (requiredRole != null && actualRole != requiredRole) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            'This account is for ${_roleName(actualRole)}. Use the ${widget.portalName ?? 'correct'} login page.',
          );
          return;
        }
        await AuditService.log(
          action: 'LOGIN',
          entityType: 'user',
          entityId: response.user!.id,
          details: 'User ${userData['name']} ($actualRole) logged in',
        );
        final appUser = AppUser(
          id: response.user!.id,
          displayName:
              userData['name'] ?? _emailCtrl.text.trim().split('@').first,
          role: _mapRoleToEnum(actualRole),
        );
        ref.read(sessionProvider.notifier).state = appUser;
        if (mounted) _navigateByRole(actualRole);
      } else {
        _showErrorSnackBar('Invalid email or password. Please try again.');
      }
    } catch (e) {
      _showErrorSnackBar(signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Older profiles can retain a legacy user_id after their Supabase Auth
  /// account is recreated. Prefer the Auth ID, then fall back to the verified
  /// email so those accounts can still reach the correct portal.
  Future<Map<String, dynamic>?> _loadUserProfile(User authUser) async {
    final client = Supabase.instance.client;
    final byId = await client
        .from('users')
        .select('name, role, email')
        .eq('user_id', authUser.id)
        .maybeSingle();
    if (byId != null) return Map<String, dynamic>.from(byId);

    final email = authUser.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return null;
    final byEmail = await client
        .from('users')
        .select('name, role, email')
        .eq('email', email)
        .maybeSingle();
    return byEmail == null ? null : Map<String, dynamic>.from(byEmail);
  }

  String _roleName(String? role) => switch (role) {
    'admin' => 'administrators',
    'gate_officer' => 'gate officers',
    'lot_owner' => 'lot owners',
    _ => 'visitors',
  };

  void _navigateByRole(String? role) {
    switch (role) {
      case 'admin':
        context.go('/admin');
        break;
      case 'gate_officer':
        context.go('/gate-officer');
        break;
      case 'lot_owner':
        context.go('/lot-owner');
        break;
      default:
        context.go('/visitor');
    }
  }

  UserRole _mapRoleToEnum(String? role) {
    switch (role) {
      case 'admin':
        return UserRole.admin;
      case 'gate_officer':
        return UserRole.gateOfficer;
      case 'lot_owner':
        return UserRole.lotOwner;
      default:
        return UserRole.visitor;
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _C.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Reusable styled text field ─────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    String? errorText,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
    Widget? labelTrailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                  color: _C.onSurfaceVariant,
                ),
              ),
              ?labelTrailing,
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14, color: _C.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
            errorText: errorText,
            errorStyle: const TextStyle(color: _C.error, fontSize: 12),
            prefixIcon: Icon(prefixIcon, size: 20, color: _C.outline),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: _C.primaryContainer,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _C.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _C.error, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: _C.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.church,
                      size: 32,
                      color: _C.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.portalName ?? 'Eternal Garden',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: _C.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.requiredRole == null
                        ? 'A quiet guide for your journey through memories.'
                        : 'Sign in to the ${widget.portalName ?? 'role'} portal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      letterSpacing: 0.5,
                      color: _C.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Card ────────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: SurfaceStyle.panel(
                      color: Colors.white,
                      radius: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Sign in',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.requiredRole == 'gate_officer'
                              ? 'Scan visitor passes and manage cemetery entry.'
                              : widget.requiredRole == 'admin'
                                  ? 'Manage cemetery operations and records.'
                                  : 'Access your visits, maps, and cemetery services.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        // Email
                        _buildField(
                          controller: _emailCtrl,
                          label: 'Email Address',
                          hint: 'name@example.com',
                          prefixIcon: Icons.mail_outline_rounded,
                          errorText: _emailError,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          hint: '••••••••',
                          prefixIcon: Icons.lock_outline_rounded,
                          errorText: _passwordError,
                          obscure: _obscure,
                          labelTrailing: TextButton(
                            onPressed: () {
                              /* TODO: forgot password */
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                                color: _C.primary,
                              ),
                            ),
                          ),
                          suffix: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: _C.outline,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Sign In button
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _signInWithSupabase,
                            style: FilledButton.styleFrom(
                              backgroundColor: _C.primaryContainer,
                              foregroundColor: _C.onPrimaryContainer,
                              disabledBackgroundColor: _C.primaryContainer
                                  .withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: '.SF Pro Text',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _C.onPrimaryContainer,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                            iconAlignment: IconAlignment.end,
                            label: const Text('Sign In'),
                          ),
                        ),

                        if (widget.requiredRole == null) ...[
                          const SizedBox(height: 32),
                          const Divider(color: _C.surfaceContainerHighest),
                          const SizedBox(height: 24),
                          const Text(
                            'New to Eternal Garden?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _C.onSurfaceVariant,
                              letterSpacing: 0.25,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => context.go('/register'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _C.primaryContainer,
                                side: const BorderSide(
                                  color: _C.primaryContainer,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              child: const Text('Create Visitor Account'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Footer ──────────────────────────────────────────────
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          foregroundColor: _C.outline,
                          textStyle: const TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        child: const Text('Terms of Service'),
                      ),
                      TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          foregroundColor: _C.outline,
                          textStyle: const TextStyle(
                            fontFamily: '.SF Pro Text',
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        child: const Text('Privacy Policy'),
                      ),
                    ],
                  ),
                  const Text(
                    'Respecting legacy, protecting privacy.',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: _C.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
