import '../../core/app_colors.dart';
import '../../widgets/logout_dialog.dart';
import '../../core/surface_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_audit_trail_screen.dart';
import 'admin_burial_records_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_lots_screen.dart';
import 'admin_map_manager_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_profile_screen.dart';
import '../payment_requests_screen.dart';
import 'admin_visitor_logs_screen.dart';
import 'admin_user_management_screen.dart';

class AdminShellScreen extends ConsumerStatefulWidget {
  const AdminShellScreen({super.key});

  @override
  ConsumerState<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends ConsumerState<AdminShellScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selected = 0;
  int _mapRefreshToken = 0;

  Future<void> _logout() => showLogoutDialog(context);

  bool _navigationExpanded = true;

  void _toggleNavigation() {
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() => _navigationExpanded = !_navigationExpanded);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Toggle navigation',
          icon: const Icon(Icons.menu_rounded),
          onPressed: _toggleNavigation,
        ),
        titleSpacing: 0,
        title: Text(_screenTitle()),
      ),
      drawer: wide ? null : Drawer(child: _buildNavigation()),
      body: Row(
        children: [
          if (wide && _navigationExpanded) ...[
            SizedBox(
              width: 260,
              child: Material(
                color: AppColors.surfaceLow,
                child: _buildNavigation(),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildNavigation() => SafeArea(
    child: Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          padding: const EdgeInsets.all(20),
          decoration: SurfaceStyle.panel(color: Colors.white, radius: 8),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.brandLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppColors.brandDark,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Panel',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage cemetery data',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              _NavTile(
                selected: _selected == 0,
                icon: Icons.dashboard_outlined,
                label: 'Overview',
                onTap: () => _go(0),
              ),
              _NavTile(
                selected: _selected == 7,
                icon: Icons.group_outlined,
                label: 'User Management',
                onTap: () => _go(7),
              ),
              _NavTile(
                selected: _selected == 1,
                icon: Icons.map,
                label: 'Cemetery Map',
                onTap: () => _go(1),
              ),
              _NavTile(
                selected: _selected == 2,
                icon: Icons.people_outline,
                label: 'Burial Records',
                onTap: () => _go(2),
              ),
              _NavTile(
                selected: _selected == 3,
                icon: Icons.grid_view_rounded,
                label: 'Lots',
                onTap: () => _go(3),
              ),
              _NavTile(
                selected: _selected == 4,
                icon: Icons.qr_code_scanner_rounded,
                label: 'Visitor Logs',
                onTap: () => _go(4),
              ),
              _NavTile(
                selected: _selected == 5,
                icon: Icons.analytics_outlined,
                label: 'Reports',
                onTap: () => _go(5),
              ),
              _NavTile(
                selected: _selected == 6,
                icon: Icons.history,
                label: 'Audit Trail',
                onTap: () => _go(6),
              ),
              _NavTile(
                selected: _selected == 8,
                icon: Icons.payments_outlined,
                label: 'Payment Review',
                onTap: () => _go(8),
              ),
              _NavTile(
                selected: _selected == 9,
                icon: Icons.manage_accounts_outlined,
                label: 'Profile Settings',
                onTap: () => _go(9),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAD6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFF93000A),
              ),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFF93000A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: _logout,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() => IndexedStack(
    index: _selected,
    children: [
      AdminDashboardScreen(
        onMenuPressed: _toggleNavigation,
        onOpenBurialRecords: () => _go(2),
        onOpenMapManager: () => _go(1),
        onOpenReports: () => _go(5),
      ),
      AdminMapManagerScreen(
        onMenuPressed: _toggleNavigation,
        refreshToken: _mapRefreshToken,
      ),
      AdminBurialRecordsScreen(
        onMenuPressed: _toggleNavigation,
        onLogoutPressed: _logout,
      ),
      AdminLotsScreen(
        onMenuPressed: _toggleNavigation,
        onLogoutPressed: _logout,
      ),
      const AdminVisitorLogsScreen(),
      const AdminReportsScreen(),
      const AdminAuditTrailScreen(),
      AdminUserManagementScreen(onMenuPressed: _toggleNavigation),
      const PaymentRequestsScreen(admin: true),
      if (_selected == 9)
        const AdminProfileScreen()
      else
        const SizedBox.shrink(),
    ],
  );

  void _go(int idx) {
    setState(() {
      _selected = idx;
      if (idx == 1) _mapRefreshToken++;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  String _screenTitle() {
    return switch (_selected) {
      0 => 'Admin Dashboard',
      1 => 'Mapping Tool',
      2 => 'Burial Records',
      3 => 'Lots',
      4 => 'Visitor Logs',
      5 => 'Reports & Analytics',
      6 => 'Audit Trail',
      7 => 'User Management',
      8 => 'Payment Review',
      9 => 'Profile Settings',
      _ => 'Cemetery Admin',
    };
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: [
          ListTile(
            selected: selected,
            leading: Icon(
              icon,
              color: selected ? AppColors.brandDark : AppColors.textSecondary,
            ),
            title: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.text : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            onTap: onTap,
            tileColor: selected ? AppColors.brandLight : null,
            selectedTileColor: AppColors.brandLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 14,
              bottom: 14,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
