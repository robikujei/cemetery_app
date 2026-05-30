import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'visitor_search_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_history_screen.dart';
import 'visitor_map_screen.dart';
import '../../providers/visitor_nav_providers.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _C {
  static const background             = Color(0xFFFBF9F6);
  static const primary                = Color(0xFF335538);
  static const primaryContainer       = Color(0xFF4B6E4F);
  static const onPrimaryContainer     = Color(0xFFC7EFC8);
  static const primaryFixed           = Color(0xFFC5EDC6);
  static const surfaceContainerLow    = Color(0xFFF5F3F0);
  static const surfaceContainerHigh   = Color(0xFFEAE8E5);
  static const surfaceContainerHighest= Color(0xFFE4E2DF);
  static const surfaceContainer       = Color(0xFFEFEEEB);
  static const secondaryContainer     = Color(0xFFC7E4F3);
  static const onSecondaryContainer   = Color(0xFF4B6673);
  static const tertiaryContainer      = Color(0xFF746356);
  static const onTertiaryContainer    = Color(0xFFF7E1D0);
  static const onSurface              = Color(0xFF1B1C1A);
  static const onSurfaceVariant       = Color(0xFF424841);
  static const outline                = Color(0xFF727971);
  static const outlineVariant         = Color(0xFFC2C8BF);
  static const white                  = Color(0xFFFFFFFF);
}

class VisitorHomeScreen extends ConsumerStatefulWidget {
  const VisitorHomeScreen({super.key});

  @override
  ConsumerState<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends ConsumerState<VisitorHomeScreen> {
  String _userName = 'Visitor';
  List<Map<String, dynamic>> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadRecentSearches();
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
          setState(() => _userName = userData['name'] ?? 'Visitor');
        }
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final json = prefs.getString('recent_searches_$userId');
        if (json != null) {
          final List<dynamic> decoded = jsonDecode(json);
          setState(() {
            _recentSearches =
                decoded.map((i) => Map<String, dynamic>.from(i)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    }
  }

  Future<void> _addRecentSearch(Map<String, dynamic> searchData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final newSearch = {
        'name': searchData['name'] ?? searchData['deceased_name'] ?? 'Unknown',
        'details': _generateSearchDetails(searchData),
        'lotNumber': searchData['lot_number'],
        'lotId': searchData['lot_id'],
        'timestamp': DateTime.now().toIso8601String(),
        'type': searchData['type'] ?? 'deceased',
      };

      _recentSearches.removeWhere((i) =>
          i['lotNumber'] == newSearch['lotNumber'] ||
          (i['name'] == newSearch['name'] && i['type'] == newSearch['type']));
      _recentSearches.insert(0, newSearch);
      if (_recentSearches.length > 10) {
        _recentSearches = _recentSearches.take(10).toList();
      }
      setState(() {});
      await prefs.setString('recent_searches_$userId', jsonEncode(_recentSearches));
    } catch (e) {
      debugPrint('Error saving recent search: $e');
    }
  }

  String _generateSearchDetails(Map<String, dynamic> d) {
    if (d['section_name'] != null) return '${d['section_name']} • Lot ${d['lot_number']}';
    if (d['details'] != null) return d['details'];
    return 'Lot ${d['lot_number']}';
  }

  Future<void> _clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await prefs.remove('recent_searches_$userId');
        setState(() => _recentSearches = []);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Recent searches cleared'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: _C.primaryContainer,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
    }
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisitorSearchScreen()),
    );
    if (result != null && result is Map<String, dynamic>) {
      await _addRecentSearch(result);
    }
  }

  void _openQrScreen() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisitorQrScreen()));

  void _openHistoryScreen() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisitorHistoryScreen()));

  void _goToMapTab() =>
      ref.read(visitorNavIndexProvider.notifier).state = 1;

  void _navigateToGrave(Map<String, dynamic> search) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VisitorMapScreen(
          initialLotId: search['lotId'],
          initialLotNumber: search['lotNumber'],
        ),
      ));

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      // Top App Bar
      appBar: AppBar(
        backgroundColor: _C.white.withOpacity(0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        titleSpacing: 24,
        title: Row(
          children: [
            const Icon(Icons.church, color: _C.primaryContainer, size: 22),
            const SizedBox(width: 10),
            Text(
              'Eternal Rest',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _C.primaryContainer,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: _C.primaryContainer, size: 22),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1, thickness: 1, color: Colors.grey.shade100),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            // ── Welcome Hero ──────────────────────────────────────────
            Text(
              'WELCOME BACK',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: _C.primary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Find a peaceful\nplace of rest.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                height: 1.25,
                color: _C.onSurface,
              ),
            ),
            const SizedBox(height: 20),

            // ── Search Bar ────────────────────────────────────────────
            GestureDetector(
              onTap: _openSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: _C.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                      color: _C.outlineVariant.withOpacity(0.3)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.search_rounded, color: _C.outline, size: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Search deceased name, lot number, or section',
                        style: TextStyle(
                          fontSize: 14,
                          color: _C.outline,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Quick Actions Bento Grid ───────────────────────────────
            _buildBentoGrid(),
            const SizedBox(height: 28),

            // ── Recent Searches ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _C.onSurface,
                  ),
                ),
                if (_recentSearches.isNotEmpty)
                  TextButton(
                    onPressed: _clearRecentSearches,
                    style: TextButton.styleFrom(
                      foregroundColor: _C.primary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_recentSearches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 44,
                          color: _C.outline.withOpacity(0.4)),
                      const SizedBox(height: 10),
                      const Text(
                        'No recent searches',
                        style: TextStyle(
                            fontSize: 14, color: _C.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_recentSearches.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildRecentItem(
                      name: s['name'],
                      details: s['details'],
                      onTap: () => _navigateToGrave(s),
                    ),
                  ))),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Bento Grid (mirrors the 2×2 HTML template exactly) ──────────────────
  Widget _buildBentoGrid() {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildBentoCard(
            label: 'Find Grave',
            icon: Icons.person_search_rounded,
            bgColor: _C.primary,
            iconBgColor: Colors.white.withOpacity(0.2),
            iconColor: Colors.white,
            labelColor: Colors.white,
            onTap: _openSearch,
          ),
          _buildBentoCard(
            label: 'View Map',
            icon: Icons.map_outlined,
            bgColor: _C.secondaryContainer,
            iconBgColor: _C.primary.withOpacity(0.1),
            iconColor: _C.onSecondaryContainer,
            labelColor: _C.onSecondaryContainer,
            onTap: _goToMapTab,
          ),
          _buildBentoCard(
            label: 'My Visits',
            icon: Icons.event_note_outlined,
            bgColor: _C.tertiaryContainer,
            iconBgColor: Colors.white.withOpacity(0.1),
            iconColor: _C.onTertiaryContainer,
            labelColor: _C.onTertiaryContainer,
            onTap: _openHistoryScreen,
          ),
          _buildBentoCard(
            label: 'My QR',
            icon: Icons.qr_code_rounded,
            bgColor: _C.surfaceContainerHighest,
            iconBgColor: _C.primary.withOpacity(0.1),
            iconColor: _C.primary,
            labelColor: _C.onSurface,
            onTap: _openQrScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildBentoCard({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color iconBgColor,
    required Color iconColor,
    required Color labelColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon badge (top-left, matching template)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              // Label (bottom-left, matching template)
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recent Search Item ───────────────────────────────────────────────────
  Widget _buildRecentItem({
    required String name,
    required String details,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _C.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _C.surfaceContainer),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Thumbnail placeholder (matches template card layout)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _C.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline_rounded,
                    color: _C.outline, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.15,
                        color: _C.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: const TextStyle(
                          fontSize: 13,
                          letterSpacing: 0.25,
                          color: _C.outline),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.history_rounded,
                  color: _C.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}