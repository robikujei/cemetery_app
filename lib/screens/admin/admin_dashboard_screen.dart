import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _metrics = {
    'total_burials': 0,
    'available_lots': 0,
    'visitor_count': 0,
    'transactions': 0,
    'recent_activities': [],
  };

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      // Get total burials - FIXED: removed count parameter
      final burialsResult = await supabase
          .from('burial_record')
          .select('burial_id');
      final totalBurials = burialsResult.length;

      // Get available lots - FIXED: removed count parameter
      final lotsResult = await supabase
          .from('cemetery_lot')
          .select('lot_id')
          .eq('status', 'Available');
      final availableLots = lotsResult.length;

      // Get visitor count (today) - FIXED: removed count parameter
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final visitorsResult = await supabase
          .from('visitor_log')
          .select('log_id')
          .gte('time_in', '$today 00:00:00');
      final visitorCount = visitorsResult.length;

      // Get transaction count - FIXED: removed count parameter
      final transactionsResult = await supabase
          .from('transaction_history')
          .select('transaction_id');
      final transactions = transactionsResult.length;

      // Get recent activities (last 5 visitor logs)
      final recentActivities = await supabase
          .from('visitor_log')
          .select('''
            log_id,
            time_in,
            user:user_id (name),
            burial:burial_id (name_of_deceased)
          ''')
          .order('time_in', ascending: false)
          .limit(5);

      setState(() {
        _metrics = {
          'total_burials': totalBurials,
          'available_lots': availableLots,
          'visitor_count': visitorCount,
          'transactions': transactions,
          'recent_activities': recentActivities,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading metrics: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDate(String? dateTimeString) {
    if (dateTimeString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateTimeString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadMetrics,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Overview',
              subtitle: 'Key metrics from your cemetery database',
            ),
            const SizedBox(height: 12),
            
            // Metrics Grid
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width < 420 ? 2 : 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _MetricCard(
                  label: 'Total Burials',
                  value: _metrics['total_burials'].toString(),
                  icon: Icons.people_outline,
                  color: cs.primary,
                ),
                _MetricCard(
                  label: 'Available Lots',
                  value: _metrics['available_lots'].toString(),
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
                _MetricCard(
                  label: "Today's Visitors",
                  value: _metrics['visitor_count'].toString(),
                  icon: Icons.groups_outlined,
                  color: Colors.blue,
                ),
                _MetricCard(
                  label: 'Transactions',
                  value: _metrics['transactions'].toString(),
                  icon: Icons.receipt_long_outlined,
                  color: Colors.orange,
                ),
              ],
            ),
            // Add this button after the metrics grid
ElevatedButton.icon(
  onPressed: () async {
    print('🔘 TEST BUTTON CLICKED');
    
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      
      print('👤 Current user: ${user?.email}');
      
      final result = await supabase.from('audit_log').insert({
        'user_email': user?.email ?? 'test@test.com',
        'user_role': 'admin',
        'action': 'TEST_FROM_BUTTON',
        'details': 'This is a test from the dashboard button',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      print('✅ Audit insert successful!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test audit entry created!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('❌ Audit error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  },
  icon: const Icon(Icons.science),
  label: const Text('TEST AUDIT'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.purple,
    foregroundColor: Colors.white,
  ),
),
            const SizedBox(height: 16),
            
            // Recent Activity
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent Activity', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      TextButton(
                        onPressed: () {},
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((_metrics['recent_activities'] as List).isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No recent activity',
                        style: t.bodyMedium?.copyWith(color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...(_metrics['recent_activities'] as List).map((activity) {
                      final user = activity['user'] ?? {};
                      final burial = activity['burial'] ?? {};
                      final timeIn = _formatDate(activity['time_in']);
                      final visitorName = user['name'] ?? 'Unknown Visitor';
                      final graveName = burial['name_of_deceased'];
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: const Icon(Icons.person, size: 20),
                        ),
                        title: Text(visitorName),
                        subtitle: Text(
                          graveName != null 
                              ? 'Visited: $graveName • $timeIn'
                              : 'Visit recorded • $timeIn',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: t.bodySmall?.copyWith(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}