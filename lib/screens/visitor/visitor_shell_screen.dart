import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../providers/visitor_nav_providers.dart';
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
    final body = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      child: screens[index],
    );
    return Scaffold(
      // Reserve the navigation area so it cannot cover profile actions.
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 208,
                  backgroundColor: AppColors.surfaceLow,
                  selectedIndex: index,
                  onDestinationSelected: select,
                  useIndicator: true,
                  indicatorColor: AppColors.brandLight,
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  selectedIconTheme: const IconThemeData(
                    color: AppColors.brand,
                  ),
                  unselectedIconTheme: const IconThemeData(
                    color: AppColors.textSecondary,
                  ),
                  selectedLabelTextStyle: const TextStyle(
                    fontFamily: 'Segoe UI',
                    color: AppColors.brandDark,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    fontFamily: 'Segoe UI',
                    color: AppColors.textSecondary,
                  ),
                  leading: const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.church_outlined, color: AppColors.brand),
                        SizedBox(width: 12),
                        Text(
                          'Visitor services',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map_rounded),
                      label: Text('Cemetery map'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.qr_code_2),
                      label: Text('My QR code'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: Text('Profile'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: index,
                onTap: select,
                backgroundColor: AppColors.surface,
                selectedItemColor: AppColors.brand,
                unselectedItemColor: AppColors.textSecondary,
                showUnselectedLabels: true,
                elevation: 0,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.map_outlined),
                    activeIcon: Icon(Icons.map_rounded),
                    label: 'Map',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.qr_code_2),
                    label: 'QR',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
    );
  }
}
