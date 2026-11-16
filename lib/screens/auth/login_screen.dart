import 'dart:async';

import '../../core/surface_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../models/app_user.dart';
import '../../providers/session_providers.dart';
import '../../utils/sign_in_error_message.dart';
import '../../utils/app_audience.dart';
import '../../widgets/brand_logo.dart';

// ── Design tokens (mirrors the HTML template's Tailwind config) ──────────────
class _C {
  static const background = Color(0xFFFFFBF3);
  static const primary = Color(0xFF123D27);
  static const primaryContainer = Color(0xFF1F5737);
  static const onPrimaryContainer = Colors.white;
  static const surfaceContainerLow = Color(0xFFFFF8EA);
  static const surfaceContainerHighest = Color(0xFFEBDDBD);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const outline = Color(0xFF6D735E);
  static const outlineVariant = Color(0xFFCFC5AD);
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      if (authState.event == AuthChangeEvent.passwordRecovery && mounted) {
        context.go('/update-password');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
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
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final emailError = email.isEmpty
        ? 'Please enter your email address'
        : !_isValidEmail(email)
        ? 'Please enter a valid email address'
        : null;
    final passwordError = password.isEmpty
        ? 'Please enter your password'
        : null;

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });

    if (emailError != null || passwordError != null) {
      final message = email.isEmpty && password.isEmpty
          ? 'Please enter your email address and password.'
          : emailError ?? passwordError!;
      _showErrorSnackBar(message);
      return false;
    }
    return true;
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
        final role = userData['role']?.toString();
        if (!isRoleAllowedInThisApp(role)) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(audienceAccessMessage);
          return;
        }
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
          role: _mapRoleToEnum(role),
        );
        ref.read(sessionProvider.notifier).state = appUser;
        if (mounted) _navigateByRole(role);
      } else {
        _showErrorSnackBar('Invalid email or password. Please try again.');
      }
    } catch (e) {
      _showErrorSnackBar(signInErrorMessage(e));
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
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextInputAction? textInputAction,
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
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: textInputAction,
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
                  const BrandLogo(height: 124),
                  const SizedBox(height: 10),
                  const Text(
                    'Eternal Garden',
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
                    decoration: SurfaceStyle.panel(
                      color: Colors.white,
                      radius: 24,
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
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          hint: '••••••••',
                          prefixIcon: Icons.lock_outline_rounded,
                          errorText: _passwordError,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _signInWithSupabase(),
                          onChanged: (_) {
                            if (_passwordError != null) {
                              setState(() => _passwordError = null);
                            }
                          },
                          obscure: _obscure,
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push(
                              '/forgot-password',
                              extra: _emailCtrl.text.trim(),
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.padded,
                            ),
                            child: const Text('Forgot password?'),
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

                        if (!isAdminApp) ...[
                          // Divider + Create Account
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
