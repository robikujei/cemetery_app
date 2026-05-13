import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'visitor_home_screen.dart';
import 'visitor_map_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_profile_screen.dart';
import '../../providers/visitor_nav_providers.dart';

class VisitorShellScreen extends ConsumerWidget {
  const VisitorShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(visitorNavIndexProvider);
    
    final screens = [
      const VisitorHomeScreen(),
      const VisitorMapScreen(),
      const VisitorQrScreen(),
      const VisitorProfileScreen(),
    ];
    
    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          // Update the provider with new index
          ref.read(visitorNavIndexProvider.notifier).state = value;
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_rounded), label: 'QR'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}