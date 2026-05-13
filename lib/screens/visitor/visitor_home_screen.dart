import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/visitor_nav_providers.dart';
import 'visitor_history_screen.dart';
import 'visitor_search_screen.dart';

class VisitorHomeScreen extends ConsumerStatefulWidget {
  const VisitorHomeScreen({super.key});

  @override
  ConsumerState<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends ConsumerState<VisitorHomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openSearch([String? query]) {
    final q = (query ?? _searchCtrl.text).trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitorSearchScreen(initialQuery: q.isEmpty ? null : q),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.white.withOpacity(0.90),
          elevation: 0,
          shadowColor: Colors.black12,
          leading: IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menu (next).')),
              );
            },
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF4B6E4F)),
          ),
          title: const Text(
            'Eternal Rest',
            style: TextStyle(
              color: Color(0xFF4B6E4F),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF4B6E4F)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 110),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 576),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(
                  'Welcome Back',
                  style: t.labelLarge?.copyWith(
                    color: cs.primary,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find a peaceful place of rest.',
                  style: t.headlineSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 16),
                _HomeSearchField(
                  controller: _searchCtrl,
                  hint: 'Search deceased name, lot number, or section',
                  onSubmitted: _openSearch,
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1,
                  ),
                  itemCount: 4,
                  itemBuilder: (context, i) {
                    switch (i) {
                      case 0:
                        return _QuickActionCard(
                          bg: const Color(0xFF335538),
                          fg: Colors.white,
                          icon: Icons.person_search_rounded,
                          label: 'Find Grave',
                          iconBg: Colors.white.withOpacity(0.20),
                          border: null,
                          onTap: () => _openSearch(),
                        );
                      case 1:
                        return _QuickActionCard(
                          bg: const Color(0xFFC7E4F3),
                          fg: const Color(0xFF4B6673),
                          icon: Icons.map_outlined,
                          label: 'View Map',
                          iconBg: const Color(0xFF335538).withOpacity(0.10),
                          border: Border.all(
                            color: const Color(0xFF47626F).withOpacity(0.10),
                          ),
                          onTap: () => ref.read(visitorNavIndexProvider.notifier).state = 1,
                        );
                      case 2:
                        return _QuickActionCard(
                          bg: const Color(0xFF746356),
                          fg: const Color(0xFFF7E1D0),
                          icon: Icons.event_note_rounded,
                          label: 'My Visits',
                          iconBg: Colors.white.withOpacity(0.10),
                          border: null,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const VisitorHistoryScreen()),
                            );
                          },
                        );
                      default:
                        return _QuickActionCard(
                          bg: const Color(0xFFE4E2DF),
                          fg: const Color(0xFF1B1C1A),
                          icon: Icons.yard_outlined,
                          label: 'My Lots',
                          iconTint: const Color(0xFF335538),
                          iconBg: const Color(0xFF335538).withOpacity(0.10),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lot owner view (next).')),
                            );
                          },
                        );
                    }
                  },
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent Searches',
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text('Clear all', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _RecentSearchTile(
                  title: 'Arthur J. Harrison',
                  subtitle: 'Section 4, Lot 112 • 1942-2018',
                  imageUrl:
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuDTGB723htarAhFRQ2GCjWR0FTRF2u8emrKrpwt3yOCqn3K__h2cqU0jjuaCkVcvnLsOLKVlTLlDsbrXwvppfe0MczAo2gZwMBDgNZxmr85lEmGB0rNHH05iBcmLXMnrqUXmUnfTD51iHpk21DGIfUsfM3zscLYEAvrIVEl1TWgiY0xv0Mjfq2cju8vVQfaxE1muBR_rh1Jkqi5Vvr7EF7J__Z5KfpxDZCxQ8DwdNHsMejq202mHCiw3c8RJN8PFVTwYtU58nxw_zQi',
                ),
                const SizedBox(height: 10),
                const _RecentSearchTile(
                  title: 'Elena S. Miller',
                  subtitle: 'Garden of Peace • 1955-2022',
                  imageUrl:
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuAGSA3CuB6y8YkexVOK1MsEYc5Ycz_QdFqgmNCqlBZ_IfuiUcoCAdFzszGoBjPI4hcVjX8Cc6L4IJglHjGDOI4ZAE0B6oFQUfY-YBmOquOdVZLr3UPS_PrYOiL4juEkCtOv-Uv0Nmpg1a0kqINwkSTsLzuPE2kS1xVXTnGGpGdgw9IF5hpZs_BgSuoGxnTIRL-0If0LHKqGDOGJf7pXCvSBJJAUaAD5Gt-oL7YloDCxeYfXzMPeRjhv1xNUWa_H2L1UZZOyvnPO4_MU',
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Cemetery Map', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuBSxCjn-VSSaGRKfghgeRi6tjX3HF08XLORB6wA0wKtfkTDOjbkMlerfoaFt9yWVWnp8S6E8cH5rmtOCvKq1W8_0I4PGykPFFk3iOuYY6H5rCSrPW6ZUjbZDj0SdL_qN20pBKCHdw9yQiKFZYCNigytOwKAm-N7wOa0Y2TfA2164mSNy12hdxPfNuF6pvGxsmihQCWdtymvG4KyafN1h9BE3KaBaIe6lKxeLKcq8ZyqT_xZFUy_ge5QF8tX7Ml-ieZQ7ppNjNGrNIEc',
                                fit: BoxFit.cover,
                              ),
                              Container(color: Colors.black.withOpacity(0.10)),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 46,
                                    child: FilledButton.icon(
                                      onPressed: () => ref.read(visitorNavIndexProvider.notifier).state = 1,
                                      icon: const Icon(Icons.explore_rounded, color: Colors.white),
                                      label: const Text('Open Interactive Map'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF335538),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
    );
  }
}

class _HomeSearchField extends StatelessWidget {
  const _HomeSearchField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final void Function(String value) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: cs.outline),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              style: t.bodyLarge?.copyWith(color: cs.onSurface),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: t.bodyLarge?.copyWith(color: cs.outline.withOpacity(0.60)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.label,
    required this.iconBg,
    required this.onTap,
    this.border,
    this.iconTint,
  });

  final Color bg;
  final Color fg;
  final Color iconBg;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final BoxBorder? border;
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: border,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: iconTint ?? fg),
              ),
              const Spacer(),
              Text(
                label,
                style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSearchTile extends StatelessWidget {
  const _RecentSearchTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  final String title;
  final String subtitle;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.surfaceContainer),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Image.network(imageUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: t.bodySmall?.copyWith(color: cs.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.history_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

