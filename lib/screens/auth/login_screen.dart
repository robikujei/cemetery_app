import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_user.dart';
import '../../providers/session_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _bgUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuAkb5AyCsXixGEF7IhXZkxOXMIiA-vd_qDO1RvOulOe_orub4kzCUOlfbze2X-edrL-qwV3Vz-ePcWNkP_Ycwz6cwwjCAp-Gi4MWYv6sj9UokGyAm_kD_PvZJJ4HmSX141P8dyugm_zsq378yhY1ZM2pE_PHbZ9DX2QeJ8DlU-rntgDWCFCCo0fVGZtb_FwfnXmYAUxWh7cV8CuwBH1O_BUKSRWGZFtqV2IYKV9CDJXNn8mKSdWugigFFTwDEwjrykSf0nBhGG_sStB';

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _signInMock() {
    // Mock sign-in for now. Backend integration will replace this.
    final user = AppUser(
      id: 'mock-user',
      displayName: 'Visitor',
      role: UserRole.visitor,
    );
    ref.read(sessionProvider.notifier).state = user;
    context.go('/visitor');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              _bgUrl,
              fit: BoxFit.cover,
              color: Colors.white.withOpacity(0.85),
              colorBlendMode: BlendMode.modulate,
              errorBuilder: (context, error, stack) {
                return Container(color: Theme.of(context).scaffoldBackgroundColor);
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surface.withOpacity(0.45),
                    cs.surface.withOpacity(0.82),
                    cs.surface,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: Column(
                    children: [
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withOpacity(0.35),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.church, color: cs.primary, size: 32),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Eternal Rest',
                            style: t.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                              letterSpacing: -0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'A quiet guide for your journey through memories.',
                            style: t.bodyLarge?.copyWith(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: cs.surfaceContainerHighest),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF335538).withOpacity(0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _LabeledField(
                              label: 'Email Address',
                              child: TextField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: 'name@example.com',
                                  prefixIcon: const Icon(Icons.mail_outline),
                                  fillColor: cs.surfaceContainerLow,
                                  filled: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _LabeledField(
                              label: 'Password',
                              trailing: TextButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Forgot password (next).')),
                                  );
                                },
                                child: const Text('Forgot password?'),
                              ),
                              child: TextField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _signInMock(),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  fillColor: cs.surfaceContainerLow,
                                  filled: true,
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton.icon(
                                onPressed: _signInMock,
                                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                                label: const Text('Sign In'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: cs.primaryContainer,
                                  foregroundColor: cs.onPrimaryContainer,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Divider(color: cs.surfaceContainerHighest),
                            const SizedBox(height: 14),
                            Text('New to Eternal Rest?', style: t.bodyMedium?.copyWith(color: Colors.black54)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: OutlinedButton(
                                onPressed: () => context.go('/register'),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: cs.primaryContainer, width: 2),
                                  foregroundColor: cs.primaryContainer,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text('Create an Account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () {},
                                child: const Text('Terms of Service'),
                              ),
                              TextButton(
                                onPressed: () {},
                                child: const Text('Privacy Policy'),
                              ),
                            ],
                          ),
                          Text(
                            'Respecting legacy, protecting privacy.',
                            style: t.labelSmall?.copyWith(color: Colors.black38),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.labelLarge?.copyWith(color: Colors.black54),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

