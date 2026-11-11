import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/visitor_nav_providers.dart';
import '../../widgets/brand_logo.dart';
import 'visitor_home_screen.dart';
import 'visitor_map_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_profile_screen.dart';

class VisitorShellScreen extends ConsumerWidget {
  const VisitorShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(visitorNavIndexProvider);
    void select(int value) =>
        ref.read(visitorNavIndexProvider.notifier).state = value;
    const screens = [
      VisitorHomeScreen(),
      VisitorMapScreen(),
      VisitorQrScreen(),
      VisitorProfileScreen(),
    ];
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
        key: ValueKey(index),
        child: RepaintBoundary(child: screens[index]),
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
                  child: NavigationRail(
                    extended: true,
                    minExtendedWidth: 224,
                    backgroundColor: Colors.transparent,
                    selectedIndex: index,
                    onDestinationSelected: select,
                    useIndicator: true,
                    groupAlignment: -0.82,
                    indicatorColor: colors.primary.withValues(alpha: 0.12),
                    indicatorShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    selectedIconTheme: IconThemeData(color: colors.primary),
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
                    destinations: const [
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
                currentIndex: index,
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
                items: const [
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
                ],
              ),
            ),
    );
  }
}
