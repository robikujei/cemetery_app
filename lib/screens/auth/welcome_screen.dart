import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _heroUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuB6A8zIVHh5InxrkiXdDwl_Rx5i0JkivDM5n_s2fbpbvHXq4rWc-i6_fje2Nx8dKSPYVovAj93qzKyIbqrGGZ-2pAsFTfimZw4q8rfuxOOfhpISBXwIbcyP7wnJFghs5tEPCRLKklDCU5jQqsuUFvRXzEUykFQyzWWhJosoJzFWhzTFjrjABIjyt7ypWZ132Yz1ZZbAsYBwhCg8F3CqY5L3Bc7LYogcnY-yfoMIpzWlaE2dwLsKyFxjDc06wsfj_VvVtRFynoFaFDw-';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              _heroUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primaryContainer, cs.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withValues(alpha: 0.40),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            right: -100,
            top: -100,
            child: _BlurBlob(color: cs.primary.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: -100,
            bottom: -100,
            child: _BlurBlob(color: cs.secondary.withValues(alpha: 0.16)),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.church,
                          color: cs.onPrimaryContainer,
                          size: 34,
                        ),
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
                        'Find graves easily and navigate cemetery locations',
                        style: t.bodyLarge?.copyWith(color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/register'),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Register as Visitor'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.tonalIcon(
                          onPressed: () => context.go('/login'),
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Login'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.black.withValues(alpha: 0.16),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'OR',
                              style: t.labelSmall?.copyWith(
                                color: Colors.black45,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.black.withValues(alpha: 0.16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton.icon(
                          onPressed: () => context.go('/visitor'),
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            color: cs.primary,
                          ),
                          label: Text(
                            'Continue as Guest',
                            style: t.labelLarge?.copyWith(color: cs.primary),
                          ),
                          style: TextButton.styleFrom(
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: 0.62,
                        child: Column(
                          children: [
                            Text(
                              'By continuing, you agree to our Terms of Service',
                              style: t.labelSmall?.copyWith(
                                color: Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Dot(color: cs.primary.withValues(alpha: 0.30)),
                                const SizedBox(width: 8),
                                _Dot(color: cs.primary.withValues(alpha: 0.30)),
                                const SizedBox(width: 8),
                                _Dot(color: cs.primary.withValues(alpha: 0.30)),
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
        ],
      ),
    );
  }
}

class _BlurBlob extends StatelessWidget {
  const _BlurBlob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 40)],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
