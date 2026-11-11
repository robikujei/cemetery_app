import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../services/user_profile_service.dart';
import '../../models/app_user.dart';
import '../../providers/session_providers.dart';
import '../../utils/app_role.dart';
import '../../utils/sign_in_error_message.dart';
import '../../widgets/brand_logo.dart';

// ── Design tokens (mirrors the HTML template's Tailwind config) ──────────────
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
  String? _signInError;

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
    setState(() {
      _isLoading = true;
      _signInError = null;
    });
    try {
      final response = await Supabase.instance.client.auth
          .signInWithPassword(
            email: _emailCtrl.text.trim().toLowerCase(),
            password: _passwordCtrl.text,
          )
          .timeout(const Duration(seconds: 15));
      if (response.user != null) {
        final userData = await loadAppUserProfile(
          Supabase.instance.client,
          response.user!,
        );
        if (userData == null) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            widget.requiredRole == 'gate_officer'
                ? 'Your password is correct, but this Gate Officer profile is not linked to the account. Ask an administrator to run the Gate Officer access repair in Supabase.'
                : 'Your account is valid, but its portal profile is missing. Contact an administrator.',
          );
          return;
        }

        final actualRole = normalizeAppRole(userData['role']);
        final requiredRole = widget.requiredRole == null
            ? null
            : normalizeAppRole(widget.requiredRole);
        if (!isGeoGraveAllowedRole(actualRole)) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            'This GeoGrave app is available only to visitors, lot owners, and gate officers.',
          );
          return;
        }
        if (appHomeForRole(actualRole) == null) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            'This account does not have a valid portal role. Contact an administrator.',
          );
          return;
        }
        if (requiredRole != null && actualRole != requiredRole) {
          await Supabase.instance.client.auth.signOut();
          _showErrorSnackBar(
            'This account is for ${appRoleName(actualRole)}. Use the ${widget.portalName ?? 'correct'} login page.',
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
      _showErrorSnackBar(
        e is TimeoutException
            ? 'Sign-in timed out. Check the internet connection and try again.'
            : signInErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateByRole(String? role) {
    final home = appHomeForRole(role);
    if (home != null) context.go(home);
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
    setState(() => _signInError = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
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
    final scheme = Theme.of(context).colorScheme;
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                  color: scheme.onSurfaceVariant,
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
          style: TextStyle(fontSize: 14, color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            errorText: errorText,
            errorStyle: TextStyle(color: scheme.error, fontSize: 12),
            prefixIcon: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(prefixIcon, size: 19, color: scheme.primary),
              ),
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: scheme.error, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────────────
                  const BrandLogo(height: 152),
                  const SizedBox(height: 24),

                  // ── Card ────────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
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
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        if (_signInError != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: scheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _signInError!,
                                    style: TextStyle(
                                      color: scheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          suffix: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: scheme.outline,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              /* TODO: forgot password */
                            },
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Sign In button
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                scheme.primary,
                                scheme.primary.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                          child: SizedBox(
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _signInWithSupabase,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: scheme.onPrimary,
                                disabledBackgroundColor: Colors.transparent,
                                disabledForegroundColor: scheme.onPrimary
                                    .withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              icon: _isLoading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
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
                        ),
                        if (widget.requiredRole == null) ...[
                          const SizedBox(height: 32),
                          Divider(color: scheme.outlineVariant),
                          const SizedBox(height: 24),
                          Text(
                            'New to Eternal Garden?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.25,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => context.go('/register'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: scheme.primary,
                                side: BorderSide(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
                          foregroundColor: scheme.outline,
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
                          foregroundColor: scheme.outline,
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
                  Text(
                    'Respecting legacy, protecting privacy.',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: scheme.outlineVariant,
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
