import 'package:flutter/material.dart';

import '../../widgets/section_header.dart';
import 'admin_dashboard_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: SectionHeader(
                  title: 'Admin Dashboard',
                  subtitle: 'Manage mapping, burials, lots, logs & analytics.',
                ),
              ),
              const Divider(),
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
                label: 'Analytics',
                onTap: () => _go(5),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selected,
          children: const [
            AdminDashboardScreen(),
            _Placeholder(title: 'Cemetery Mapping', subtitle: 'Upload PNG + plot sections/lots (next).'),
            _Placeholder(title: 'Burial Records', subtitle: 'CRUD burial records (next).'),
            _Placeholder(title: 'Lots', subtitle: 'Set status/prices + ownership records (next).'),
            _Placeholder(title: 'Visitor Logs', subtitle: 'View QR scan logs + search (next).'),
            _Placeholder(title: 'Analytics', subtitle: 'Hotspots + demand counts (next).'),
          ],
        ),
      ),
    );
  }

  void _go(int idx) {
    setState(() => _selected = idx);
    Navigator.of(context).maybePop();
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This module is scaffolded and ready for Stitch UI + backend wiring.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

