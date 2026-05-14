import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'visitor_search_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_history_screen.dart';

class VisitorHomeScreen extends ConsumerStatefulWidget {
  const VisitorHomeScreen({super.key});

  @override
  ConsumerState<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends ConsumerState<VisitorHomeScreen> {
  String _userName = 'Visitor';
  
  @override
  void initState() {
    super.initState();
    _loadUserName();
  }
  
  Future<void> _loadUserName() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select('name')
            .eq('email', user.email!)
            .maybeSingle();
        if (userData != null && mounted) {
          setState(() {
            _userName = userData['name'] ?? 'Visitor';
          });
        }
      }
    } catch (e) {
      print('Error loading user: $e');
    }
  }
  
  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisitorSearchScreen()),
    );
  }
  
  void _openQrScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisitorQrScreen()),
    );
  }
  
 void _openHistoryScreen() {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const VisitorHistoryScreen()),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Eternal Rest'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, $_userName',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Find a peaceful place of rest.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  
                  // Search Bar
                  InkWell(
                    onTap: _openSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey),
                          SizedBox(width: 12),
                          Text('Search deceased name, lot number...'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Quick Actions Grid
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                      _buildQuickAction(
                        icon: Icons.search,
                        label: 'Find Grave',
                        color: Colors.green.shade700,
                        onTap: _openSearch,
                      ),
                      _buildQuickAction(
                        icon: Icons.map,
                        label: 'View Map',
                        color: Colors.blue.shade700,
                        onTap: () {
                          // TODO: Navigate to map screen
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Map feature coming soon!')),
                          );
                        },
                      ),
                      _buildQuickAction(
                        icon: Icons.qr_code,
                        label: 'My QR Code',
                        color: Colors.purple.shade700,
                        onTap: _openQrScreen,  // ← FIXED: Now navigates to QR screen
                      ),
                      _buildQuickAction(
                        icon: Icons.history,
                        label: 'Visit History',
                        color: Colors.orange.shade700,
                        onTap: _openHistoryScreen,  // ← FIXED: Now navigates to history screen
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}