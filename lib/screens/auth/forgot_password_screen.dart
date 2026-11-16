import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _isSending = false;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    // The email form is replaced by the code form after the first request.
    if (!_codeSent && !(_emailFormKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim().toLowerCase(),
      );
      if (mounted) setState(() => _codeSent = true);
    } catch (error) {
      final detail = error is AuthException ? error.message : error.toString();
      final lower = detail.toLowerCase();
      final message =
          lower.contains('rate') &&
              (lower.contains('email') || lower.contains('limit'))
          ? 'Supabase has temporarily limited reset emails. Wait before trying again. If this continues, configure custom SMTP for the Supabase project.'
          : error is AuthException
          ? error.message
          : 'Could not send the reset code. Check your connection and try again.';
      if (mounted) setState(() => _errorMessage = message);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth.verifyOTP(
        email: _emailController.text.trim().toLowerCase(),
        token: _codeController.text.trim(),
        type: OtpType.recovery,
      );
      if (mounted) context.go('/update-password');
    } catch (error) {
      final message = error is AuthException
          ? error.message
          : 'Could not verify the code. Check it and try again.';
      if (mounted) setState(() => _errorMessage = message);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your account email address';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validateCode(String? value) => (value?.trim().length ?? 0) < 6
      ? 'Enter the recovery code from your email'
      : null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to sign in',
        ),
        title: const Text('Reset password'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _codeSent
                      ? _buildCodeStep(scheme)
                      : _buildEmailStep(scheme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep(ColorScheme scheme) => Form(
    key: _emailFormKey,
    child: Column(
      key: const ValueKey('reset-email'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_reset_rounded, size: 48, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Forgot your password?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Step 1 of 3: Enter your account email and we’ll send a reset code.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          onFieldSubmitted: (_) => _sendResetCode(),
          validator: _validateEmail,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isSending ? null : _sendResetCode,
          icon: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_email_unread_outlined),
          label: Text(_isSending ? 'Sending code…' : 'Send reset code'),
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );

  Widget _buildCodeStep(ColorScheme scheme) => Form(
    key: _codeFormKey,
    child: Column(
      key: const ValueKey('reset-code'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 52, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Enter your recovery code',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Step 2 of 3: Enter the code sent to ${_emailController.text.trim()}. You’ll set a new password after verification.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _verifyCode(),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: _validateCode,
          decoration: const InputDecoration(
            labelText: 'Recovery code',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isVerifying ? null : _verifyCode,
          child: _isVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify code'),
        ),
        TextButton(
          onPressed: _isSending ? null : _sendResetCode,
          child: const Text('Resend code'),
        ),
        TextButton(
          onPressed: _isSending
              ? null
              : () => setState(() {
                  _codeSent = false;
                  _errorMessage = null;
                }),
          child: const Text('Use a different email'),
        ),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );
}
