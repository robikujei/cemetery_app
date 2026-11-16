import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'visitor_search_screen.dart';
import 'visitor_qr_screen.dart';
import 'visitor_history_screen.dart';
import 'visitor_map_screen.dart';
import '../../providers/visitor_nav_providers.dart';
import '../../widgets/brand_logo.dart';
import '../../services/visitor_relative_groups_service.dart';
import '../../services/visitor_recent_search_service.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class VisitorHomeScreen extends ConsumerStatefulWidget {
  const VisitorHomeScreen({super.key});

  @override
  ConsumerState<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends ConsumerState<VisitorHomeScreen> {
  String _userName = 'Visitor';
  List<Map<String, dynamic>> _recentSearches = [];
  List<String> _relativeGroups = [];
  Map<String, Map<String, dynamic>> _relativeAssignments = {};
  String _selectedRecentGroup = 'All';

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadRecentSearches();
    _loadRelativeGroups();
  }

  Future<void> _loadRelativeGroups() async {
    final groups = await VisitorRelativeGroupsService.loadGroups();
    final assignments = await VisitorRelativeGroupsService.loadAssignments();
    if (!mounted) return;
    setState(() {
      _relativeGroups = groups;
      _relativeAssignments = assignments;
    });
  }

  Future<void> _createRelativeGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a relatives group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'e.g. My relatives',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await VisitorRelativeGroupsService.createGroup(name);
    await _loadRelativeGroups();
  }

  Future<void> _toggleRecentFavorite(String name) async {
    final current = _relativeAssignments[name]?['favorite'] == true;
    await VisitorRelativeGroupsService.setAssignment(name, favorite: !current);
    await _loadRelativeGroups();
  }

  Future<void> _assignRecentGroup(String name, String group) async {
    await VisitorRelativeGroupsService.setAssignment(name, group: group);
    await _loadRelativeGroups();
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
      final searches = await VisitorRecentSearchService.load();
      if (!mounted) return;
      setState(() => _recentSearches = searches);
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    }
  }

  Future<void> _addRecentSearch(Map<String, dynamic> searchData) async {
    try {
      final newSearch = {
        'name': searchData['name'] ?? searchData['deceased_name'] ?? 'Unknown',
        'details': _generateSearchDetails(searchData),
        'lotNumber': searchData['lot_number'],
        'lotId': searchData['lot_id'],
        'timestamp': DateTime.now().toIso8601String(),
        'type': searchData['type'] ?? 'deceased',
        'burialId': searchData['burial_id'] ?? searchData['burialId'],
      };
      await VisitorRecentSearchService.save(newSearch);
      await _loadRecentSearches();
    } catch (e) {
      debugPrint('Error saving recent search: $e');
    }
  }

  String _generateSearchDetails(Map<String, dynamic> d) {
    if (d['block_name'] != null && d['block_name'].toString().isNotEmpty) {
      return '${d['block_name']} - Lot ${d['lot_number']}';
    }
    if (d['section_name'] != null) {
      return '${d['section_name']} - Lot ${d['lot_number']}';
    }
    if (d['details'] != null) return d['details'];
    return 'Lot ${d['lot_number']}';
  }

  Future<void> _clearRecentSearches() async {
    final colors = Theme.of(context).colorScheme;
    try {
      await VisitorRecentSearchService.clear();
      if (!mounted) return;
      setState(() => _recentSearches = []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recent searches cleared'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.primaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
    }
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(
      context,
    ).push(_visitorRoute(builder: (_) => const VisitorSearchScreen()));
    if (result != null && result is Map<String, dynamic>) {
      await _addRecentSearch(result);
    }
  }

  void _openQrScreen() => Navigator.of(
    context,
  ).push(_visitorRoute(builder: (_) => const VisitorQrScreen()));

  void _openHistoryScreen() => Navigator.of(
    context,
  ).push(_visitorRoute(builder: (_) => const VisitorHistoryScreen()));

  void _goToMapTab() => ref.read(visitorNavIndexProvider.notifier).state = 1;

  void _navigateToGrave(Map<String, dynamic> search) {
    final burialId = search['burialId'] ?? search['burial_id'];
    Navigator.of(context).push(
      _visitorRoute(
        builder: (_) => VisitorMapScreen(
          initialLotId: search['lotId'] ?? search['lot_id'],
          initialLotNumber: search['lotNumber'] ?? search['lot_number'],
          initialBurialId: burialId,
          initialBurial: burialId == null
              ? null
              : {
                  'burial_id': burialId,
                  'name_of_deceased': search['name'] ?? search['deceased_name'],
                  'lot_id': search['lotId'] ?? search['lot_id'],
                },
        ),
      ),
    );
  }

  PageRoute<T> _visitorRoute<T>({required WidgetBuilder builder}) =>
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    ref.listen<int>(recentSearchRevisionProvider, (previous, next) {
      _loadRecentSearches();
    });
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainer,
      // Top App Bar
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        titleSpacing: 24,
        title: const BrandLogo(height: 48),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // ── Welcome Hero ──────────────────────────────────────────
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 480),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: 1),
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary,
                          colors.primary.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, $_userName',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: colors.onPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Find a loved one, explore the grounds, or revisit a saved search.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: colors.onPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Search Bar ────────────────────────────────────────────
                const SizedBox(height: 24),

                // ── Quick Actions Bento Grid ───────────────────────────────
                _buildBentoGrid(),
                const SizedBox(height: 28),

                // ── Recent Searches ───────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Searches',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Create relatives group',
                      onPressed: _createRelativeGroup,
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                    if (_recentSearches.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear recent searches',
                        onPressed: _clearRecentSearches,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ...['All', 'Favorites', ..._relativeGroups].map(
                        (group) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(group),
                            selected: _selectedRecentGroup == group,
                            onSelected: (_) =>
                                setState(() => _selectedRecentGroup = group),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_recentSearches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 44,
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No recent searches',
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...(_recentSearches
                      .where((search) {
                        final assignment =
                            _relativeAssignments[search['name']] ?? {};
                        if (_selectedRecentGroup == 'All') return true;
                        if (_selectedRecentGroup == 'Favorites') {
                          return assignment['favorite'] == true;
                        }
                        return assignment['group'] == _selectedRecentGroup;
                      })
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildRecentItem(
                            search: s,
                            onTap: () => _navigateToGrave(s),
                          ),
                        ),
                      )),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bento Grid (mirrors the 2×2 HTML template exactly) ──────────────────
  Widget _buildBentoGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = Theme.of(context).colorScheme;
        return GridView.count(
          crossAxisCount: constraints.maxWidth >= 720 ? 4 : 2,
          mainAxisExtent: 112 + MediaQuery.textScalerOf(context).scale(48),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildBentoCard(
              label: 'Find Grave',
              icon: Icons.person_search_rounded,
              bgColor: colors.primary,
              iconBgColor: colors.onPrimary.withValues(alpha: 0.2),
              iconColor: colors.onPrimary,
              labelColor: colors.onPrimary,
              onTap: _openSearch,
            ),
            _buildBentoCard(
              label: 'View Map',
              icon: Icons.map_outlined,
              bgColor: colors.surface,
              iconBgColor: colors.primary.withValues(alpha: 0.1),
              iconColor: colors.onSurfaceVariant,
              labelColor: colors.onSurface,
              onTap: _goToMapTab,
            ),
            _buildBentoCard(
              label: 'My Visits',
              icon: Icons.event_note_outlined,
              bgColor: colors.surface,
              iconBgColor: colors.primary.withValues(alpha: 0.1),
              iconColor: colors.primary,
              labelColor: colors.onSurface,
              onTap: _openHistoryScreen,
            ),
            _buildBentoCard(
              label: 'My QR',
              icon: Icons.qr_code_rounded,
              bgColor: colors.surface,
              iconBgColor: colors.primary.withValues(alpha: 0.1),
              iconColor: colors.primary,
              labelColor: colors.onSurface,
              onTap: _openQrScreen,
            ),
          ],
        );
      },
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
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: 0.96 + (0.04 * value), child: child),
      ),
      child: Material(
        color: bgColor,
        elevation: 0,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: bgColor.withValues(alpha: 0.14)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 25),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Recent Search Item ───────────────────────────────────────────────────
  Widget _buildRecentItem({
    required Map<String, dynamic> search,
    required VoidCallback onTap,
  }) {
    final name = search['name']?.toString() ?? 'Unknown';
    final details = search['details']?.toString() ?? '';
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // Thumbnail placeholder (matches template card layout)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: colors.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.15,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.25,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _toggleRecentFavorite(name),
                icon: Icon(
                  _relativeAssignments[name]?['favorite'] == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _relativeAssignments[name]?['favorite'] == true
                      ? colors.error
                      : colors.onSurfaceVariant,
                  size: 20,
                ),
                tooltip: 'Favorite',
              ),
              PopupMenuButton<String>(
                tooltip: 'Assign to group',
                onSelected: (group) => _assignRecentGroup(name, group),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: '', child: Text('No group')),
                  ..._relativeGroups.map(
                    (group) => PopupMenuItem(value: group, child: Text(group)),
                  ),
                ],
                icon: Icon(
                  Icons.folder_outlined,
                  color: colors.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
