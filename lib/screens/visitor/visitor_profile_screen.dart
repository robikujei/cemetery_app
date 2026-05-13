import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/session_providers.dart';

/// Profile tab — converted from Stitch HTML (header, bento cards, settings, logout).
class VisitorProfileScreen extends ConsumerWidget {
  const VisitorProfileScreen({super.key});

  static const _avatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuD0dBW5FyU8Htt1-yUbw_BNOBw1ZeH8G9ZMb7ipo-xuPJtE5d9yYA5Eeg0hJhRci9AxK72YHVYQnvu_vUYHatIgX0fS0uk6Botpum2786IgtnwXRxyl1p6-kMDDhLrkrTujs7wZlYaIzwCL9QUMgTuoGNko7MpVK5FueljSj_K5GVHFpGg2EcMkdlhOTRR3GgazOQsWlaA4c2lC3m9MKEKFR--4aCUpJLQ_IDuYimet9YqfDUIxabBinvEUEKCKUulN2f0lqWjNAVq8';

  static const Color _brandGreen = Color(0xFF4B6E4F);
  static const Color _errorContainer = Color(0xFFFFDAD6);
  static const Color _onErrorContainer = Color(0xFF93000A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final displayName = session?.displayName ?? 'Eleanor Vance';
    final email = 'eleanor.vance@email.com';
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

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
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 720;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _UserInfoCard(
                            displayName: displayName,
                            email: email,
                            t: t,
                            cs: cs,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SavedMemorialsCard(t: t),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UserInfoCard(
                        displayName: displayName,
                        email: email,
                        t: t,
                        cs: cs,
                      ),
                      const SizedBox(height: 16),
                      _SavedMemorialsCard(t: t),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _SettingsCard(t: t, cs: cs),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(sessionProvider.notifier).state = null;
                    context.go('/welcome');
                  },
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
                'App Version 2.4.1 (Build 1092)',
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

class _UserInfoCard extends StatelessWidget {
  const _UserInfoCard({
    required this.displayName,
    required this.email,
    required this.t,
    required this.cs,
  });

  final String displayName;
  final String email;
  final TextTheme t;
  final ColorScheme cs;

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
                backgroundImage: const NetworkImage(VisitorProfileScreen._avatarUrl),
              ),
              Positioned(
                right: -2,
                bottom: -2,
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
                        'Lot Owner',
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

class _SavedMemorialsCard extends StatelessWidget {
  const _SavedMemorialsCard({required this.t});

  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                'Saved Memorials',
                style: t.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.bookmark_outline, color: cs.onPrimaryContainer),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '12',
            style: t.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onPrimaryContainer,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '3 updated recently',
            style: t.labelSmall?.copyWith(
              color: cs.onPrimaryContainer.withOpacity(0.70),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.t, required this.cs});

  final TextTheme t;
  final ColorScheme cs;

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
            title: 'Personal Information',
            subtitle: 'Update your name and phone number',
            onTap: () => _toast(context, 'Personal Information (next).'),
          ),
          Divider(height: 1, color: cs.surfaceContainerLow),
          _SettingTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications',
            subtitle: 'Manage commemorative alerts and news',
            onTap: () => _toast(context, 'Notifications (next).'),
          ),
          Divider(height: 1, color: cs.surfaceContainerLow),
          _SettingTile(
            icon: Icons.lock_outline,
            title: 'Security & Privacy',
            subtitle: 'Password, biometric and privacy data',
            onTap: () => _toast(context, 'Security & Privacy (next).'),
          ),
          Divider(height: 1, color: cs.surfaceContainerLow),
          _SettingTile(
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'FAQs, contact support, and guides',
            onTap: () => _toast(context, 'Help Center (next).'),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
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
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
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
