import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/visitor_nav_providers.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/logout_dialog.dart';
import 'visitor_home_screen.dart';
import 'visitor_map_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_profile_screen.dart';
import '../lot_owner/lot_owner_home_screen.dart';

/// Ownership is the capability that unlocks the owner dashboard. A user can
/// keep the visitor experience even if their profile role was previously set
/// to lot_owner, until a lot is actually assigned to the account.
final visitorOwnershipAccessProvider = FutureProvider<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;
  final ownership = await Supabase.instance.client
      .from('lot_ownership')
      .select('ownership_id')
      .eq('user_id', user.id)
      .limit(1)
      .maybeSingle();
  return ownership != null;
});

/// A lot-owner account retains Visitor access, but also needs a clear route
/// back to its dedicated owner dashboard.
final visitorLotOwnerRoleProvider = FutureProvider<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;
  final profile = await Supabase.instance.client
      .from('users')
      .select('role')
      .eq('user_id', user.id)
      .maybeSingle();
  return profile?['role']?.toString().trim().toLowerCase() == 'lot_owner';
});

class VisitorShellScreen extends ConsumerWidget {
  const VisitorShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(visitorNavIndexProvider);
    void select(int value) =>
        ref.read(visitorNavIndexProvider.notifier).state = value;
    final hasOwnership =
        ref.watch(visitorOwnershipAccessProvider).valueOrNull ?? false;
    final isLotOwner =
        ref.watch(visitorLotOwnerRoleProvider).valueOrNull ?? false;
    final screens = [
      const VisitorHomeScreen(),
      const VisitorMapScreen(),
      const VisitorQrScreen(),
      const VisitorProfileScreen(),
      if (hasOwnership) const LotOwnerHomeScreen(embedded: true),
    ];
    final selectedIndex = index < screens.length ? index : 0;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final colors = Theme.of(context).colorScheme;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(selectedIndex),
        child: RepaintBoundary(child: screens[selectedIndex]),
      ),
    );
    return Scaffold(
      // Reserve the navigation area so it cannot cover profile actions.
      body: wide
          ? Row(
              children: [
                Container(
                  width: 224,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      right: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: NavigationRail(
                          extended: true,
                          minExtendedWidth: 224,
                          backgroundColor: Colors.transparent,
                          selectedIndex: selectedIndex,
                          onDestinationSelected: select,
                          useIndicator: true,
                          groupAlignment: -0.82,
                          indicatorColor: colors.primary.withValues(
                            alpha: 0.12,
                          ),
                          indicatorShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          selectedIconTheme: IconThemeData(
                            color: colors.primary,
                          ),
                          unselectedIconTheme: IconThemeData(
                            color: colors.onSurfaceVariant,
                          ),
                          selectedLabelTextStyle: TextStyle(
                            fontFamily: '.SF Pro Text',
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelTextStyle: TextStyle(
                            fontFamily: '.SF Pro Text',
                            color: colors.onSurfaceVariant,
                          ),
                          leading: const Padding(
                            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
                            child: BrandLogo(height: 88),
                          ),
                          destinations: [
                            NavigationRailDestination(
                              icon: Icon(CupertinoIcons.house),
                              selectedIcon: Icon(CupertinoIcons.house_fill),
                              label: Text('Home'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(CupertinoIcons.map),
                              selectedIcon: Icon(CupertinoIcons.map_fill),
                              label: Text('Cemetery map'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(CupertinoIcons.qrcode),
                              label: Text('My QR code'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(CupertinoIcons.person),
                              selectedIcon: Icon(CupertinoIcons.person_fill),
                              label: Text('Profile'),
                            ),
                            if (hasOwnership)
                              const NavigationRailDestination(
                                icon: Icon(CupertinoIcons.square_grid_2x2),
                                selectedIcon: Icon(
                                  CupertinoIcons.square_grid_2x2_fill,
                                ),
                                label: Text('My lots'),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isLotOwner) ...[
                              OutlinedButton.icon(
                                onPressed: () => context.go('/lot-owner'),
                                icon: const Icon(Icons.home_work_outlined),
                                label: const Text('Lot Owner Dashboard'),
                              ),
                              const SizedBox(height: 10),
                            ],
                            FilledButton.icon(
                              onPressed: () => showLogoutDialog(context),
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Logout'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.errorContainer,
                                foregroundColor: colors.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: selectedIndex,
                onTap: select,
                backgroundColor: colors.surface,
                selectedItemColor: colors.primary,
                unselectedItemColor: colors.onSurfaceVariant,
                showUnselectedLabels: true,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                elevation: 0,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.house),
                    activeIcon: Icon(CupertinoIcons.house_fill),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.map),
                    activeIcon: Icon(CupertinoIcons.map_fill),
                    label: 'Map',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.qrcode),
                    label: 'QR',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.person),
                    activeIcon: Icon(CupertinoIcons.person_fill),
                    label: 'Profile',
                  ),
                  if (hasOwnership)
                    const BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.square_grid_2x2),
                      activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
                      label: 'My Lots',
                    ),
                ],
              ),
            ),
    );
  }
}
