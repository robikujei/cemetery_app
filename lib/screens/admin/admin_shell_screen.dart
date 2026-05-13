import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audit_service.dart';
import '../../widgets/section_header.dart';
import '../../providers/session_providers.dart';
import 'admin_dashboard_screen.dart';
import 'admin_burial_records_screen.dart';
import 'admin_lots_screen.dart';
import 'admin_visitor_logs_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_audit_trail_screen.dart';  // ← ADD THIS IMPORT

class AdminShellScreen extends ConsumerStatefulWidget {
  const AdminShellScreen({super.key});

  @override
  ConsumerState<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends ConsumerState<AdminShellScreen> {
  int _selected = 0;

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
    final user = Supabase.instance.client.auth.currentUser;
    
    // ✅ ADD AUDIT LOG FOR LOGOUT
    await AuditService.log(
      action: 'LOGOUT',
      entityType: 'user',
      entityId: user?.id,
      details: 'User logged out',
    );
    
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
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: SectionHeader(
                  title: 'Admin Panel',
                  subtitle: 'Manage cemetery data',
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _NavTile(
                      selected: _selected == 0,
                      icon: Icons.dashboard_outlined,
                      label: 'Overview',
                      onTap: () => _go(0),
                    ),
                    _NavTile(
                      selected: _selected == 1,
                      icon: Icons.layers_outlined,
                      label: 'Cemetery Mapping',
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
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selected,
        children: const [
          AdminDashboardScreen(),
          _Placeholder(title: 'Cemetery Mapping', subtitle: 'Upload PNG + plot sections/lots'),
          AdminBurialRecordsScreen(),
          AdminLotsScreen(),
          AdminVisitorLogsScreen(),
          AdminReportsScreen(),
          AdminAuditTrailScreen(),  // ← ADD THIS
        ],
      ),
    );
  }

  void _go(int idx) {
    setState(() => _selected = idx);
    Navigator.of(context).pop(); // Close drawer
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
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      tileColor: selected ? Colors.green.withOpacity(0.1) : null,
      selectedTileColor: Colors.green.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B6E4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Coming Soon'),
            ),
          ],
        ),
      ),
    );
  }
}