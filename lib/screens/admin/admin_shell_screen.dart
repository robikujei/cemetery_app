import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/session_providers.dart';
import 'admin_audit_trail_screen.dart';
import 'admin_burial_records_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_lots_screen.dart';
import 'admin_map_manager_screen.dart';
import 'admin_reports_screen.dart';
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

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      ref.read(sessionProvider.notifier).state = null;
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFFBF9F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x1A000000),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          color: const Color(0xFF1B1C1A),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: Text(
          _screenTitle(),
          style: const TextStyle(
            color: Color(0xFF335538),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFFFBF9F6),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE4E2DF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC5EDC6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.apartment_rounded,
                        color: Color(0xFF335538),
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
                              color: Color(0xFF1B1C1A),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Manage cemetery data',
                            style: TextStyle(
                              color: Color(0xFF424841),
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDAD6),
                    borderRadius: BorderRadius.circular(18),
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
        ),
      ),
      body: IndexedStack(
        index: _selected,
        children: [
          AdminDashboardScreen(
            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            onOpenBurialRecords: () => _go(2),
            onOpenMapManager: () => _go(1),
            onOpenReports: () => _go(5),
          ),
          AdminMapManagerScreen(
            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            refreshToken: _mapRefreshToken,
          ),
          AdminBurialRecordsScreen(
            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            onLogoutPressed: _logout,
          ),
          AdminLotsScreen(
            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            onLogoutPressed: _logout,
          ),
          const AdminVisitorLogsScreen(),
          const AdminReportsScreen(),
          const AdminAuditTrailScreen(),
          AdminUserManagementScreen(
            onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
    );
  }

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
    return ListTile(
      selected: selected,
      leading: Icon(
        icon,
        color: selected ? const Color(0xFF335538) : const Color(0xFF424841),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF1B1C1A) : const Color(0xFF424841),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
      tileColor: selected
          ? const Color(0xFFC5EDC6).withValues(alpha: 0.35)
          : null,
      selectedTileColor: const Color(0xFFC5EDC6).withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
