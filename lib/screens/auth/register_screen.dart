import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';

class _C {
  static const background = Color(0xFFFBF9F6);
  static const primary = Color(0xFF335538);
  static const primaryContainer = Color(0xFF4B6E4F);
  static const primaryFixed = Color(0xFFC5EDC6);
  static const surfaceContainerLow = Color(0xFFF5F3F0);
  static const surfaceContainerHighest = Color(0xFFE4E2DF);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const error = Color(0xFFBA1A1A);
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  // Error messages
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // Email validation function
  bool _isValidEmail(String email) {
    if (email.isEmpty) return false;
    // Regular expression for email validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  bool _validateForm() {
    bool isValid = true;

    // Validate name
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'Please enter your full name');
      isValid = false;
    } else {
      setState(() => _nameError = null);
    }

    // Validate email format
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address');
      isValid = false;
    } else if (!_isValidEmail(email)) {
      setState(
        () => _emailError =
            'Please enter a valid email address (e.g., name@example.com)',
      );
      isValid = false;
    } else {
      setState(() => _emailError = null);
    }

    // Validate password
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _passwordError = 'Please enter a password');
      isValid = false;
    } else if (password.length < 6) {
      setState(() => _passwordError = 'Password must be at least 6 characters');
      isValid = false;
    } else {
      setState(() => _passwordError = null);
    }

    // Validate confirm password
    if (_confirmPasswordCtrl.text.isEmpty) {
      setState(() => _confirmPasswordError = 'Please confirm your password');
      isValid = false;
    } else if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _confirmPasswordError = 'Passwords do not match');
      isValid = false;
    } else {
      setState(() => _confirmPasswordError = null);
    }

    return isValid;
  }

  Future<void> _registerWithSupabase() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await ref
          .read(authProvider.notifier)
          .register(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
            _nameCtrl.text.trim(),
            'visitor',
          );

      if (!success) {
        final error = ref.read(authProvider).errorMessage;
        _showErrorSnackBar(error ?? 'Registration failed. Please try again.');
        return;
      }

      await ref.read(authProvider.notifier).logout();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Please login.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
      }
    } on AuthException catch (e) {
      if (e.message.contains('already registered')) {
        _showErrorSnackBar(
          'This email is already registered. Please login instead.',
        );
      } else {
        _showErrorSnackBar(e.message);
      }
    } catch (e) {
      _showErrorSnackBar('An error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: _C.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_add_alt_rounded,
                      size: 34,
                      color: _C.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w400,
                      color: _C.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Join Eternal Rest to manage visits and keep family records connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: _C.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
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
                        _buildField(
                          controller: _nameCtrl,
                          label: 'Full Name',
                          hint: 'Jane Doe',
                          prefixIcon: Icons.person_outline_rounded,
                          errorText: _nameError,
                          keyboardType: TextInputType.name,
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _emailCtrl,
                          label: 'Email Address',
                          hint: 'name@example.com',
                          prefixIcon: Icons.mail_outline_rounded,
                          errorText: _emailError,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _C.primaryFixed.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _C.primaryFixed),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                color: _C.primary,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Visitor / Family Member account',
                                  style: TextStyle(
                                    color: _C.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _passwordCtrl,
                          label: 'Password',
                          hint: 'At least 6 characters',
                          prefixIcon: Icons.lock_outline_rounded,
                          errorText: _passwordError,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _C.onSurfaceVariant,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _confirmPasswordCtrl,
                          label: 'Confirm Password',
                          hint: 'Re-enter your password',
                          prefixIcon: Icons.lock_reset_rounded,
                          errorText: _confirmPasswordError,
                          obscureText: _obscureConfirmPassword,
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirmPassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _C.onSurfaceVariant,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _isLoading
                                ? null
                                : _registerWithSupabase,
                            style: FilledButton.styleFrom(
                              backgroundColor: _C.primaryContainer,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _C.primaryContainer
                                  .withValues(alpha: 0.55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Already have an account?',
                              style: TextStyle(color: _C.onSurfaceVariant),
                            ),
                            TextButton(
                              onPressed: () => context.go('/login'),
                              child: const Text(
                                'Sign In',
                                style: TextStyle(
                                  color: _C.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    String? errorText,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: _C.onSurface, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(prefixIcon, color: _C.primary),
        suffixIcon: suffixIcon,
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
          borderSide: const BorderSide(color: _C.primaryContainer, width: 2),
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
    );
  }
}
