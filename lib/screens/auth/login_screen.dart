import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../models/app_user.dart';
import '../../providers/session_providers.dart';

// ── Design tokens (mirrors the HTML template's Tailwind config) ──────────────
class _C {
  static const background = Color(0xFFFBF9F6);
  static const primary = Color(0xFF335538);
  static const primaryContainer = Color(0xFF4B6E4F);
  static const onPrimaryContainer = Color(0xFFC7EFC8);
  static const primaryFixed = Color(0xFFC5EDC6);
  static const surfaceContainerLow = Color(0xFFF5F3F0);
  static const surfaceContainerHighest = Color(0xFFE4E2DF);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const outline = Color(0xFF727971);
  static const outlineVariant = Color(0xFFC2C8BF);
  static const error = Color(0xFFBA1A1A);
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
        final userData = await Supabase.instance.client
            .from('users')
            .select('name, role')
            .eq('email', _emailCtrl.text.trim().toLowerCase())
            .single();
        await AuditService.log(
          action: 'LOGIN',
          entityType: 'user',
          entityId: response.user!.id,
          details: 'User ${userData['name']} (${userData['role']}) logged in',
        );
        final appUser = AppUser(
          id: response.user!.id,
          displayName:
              userData['name'] ?? _emailCtrl.text.trim().split('@').first,
          role: _mapRoleToEnum(userData['role']),
        );
        ref.read(sessionProvider.notifier).state = appUser;
        if (mounted) _navigateByRole(userData['role']);
      } else {
        _showErrorSnackBar('Invalid email or password. Please try again.');
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (_) {
      _showErrorSnackBar('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
            hintStyle: const TextStyle(color: _C.outlineVariant, fontSize: 14),
            errorText: errorText,
            errorStyle: const TextStyle(color: _C.error, fontSize: 12),
            prefixIcon: Icon(prefixIcon, size: 20, color: _C.outline),
            suffixIcon: suffix,
            filled: true,
            fillColor: _C.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: _C.primaryContainer,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _C.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
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
                  const Text(
                    'Eternal Rest',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w400,
                      color: _C.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A quiet guide for your journey through memories.',
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _C.surfaceContainerHighest),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F335538),
                          blurRadius: 24,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
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

                        // Divider + Create Account
                        const SizedBox(height: 32),
                        const Divider(color: _C.surfaceContainerHighest),
                        const SizedBox(height: 24),
                        const Text(
                          'New to Eternal Rest?',
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
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                            child: const Text('Create Visitor Account'),
                          ),
                        ),
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
