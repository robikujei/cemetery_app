import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/surface_style.dart';
import '../../utils/lot_formatters.dart';

class VisitorHistoryScreen extends ConsumerStatefulWidget {
  const VisitorHistoryScreen({super.key});

  @override
  ConsumerState<VisitorHistoryScreen> createState() =>
      _VisitorHistoryScreenState();
}

class _VisitorHistoryScreenState extends ConsumerState<VisitorHistoryScreen> {
  ColorScheme _colors(BuildContext context) => Theme.of(context).colorScheme;
  List<Map<String, dynamic>> _visitHistory = [];
  List<Map<String, dynamic>> _filteredHistory = [];

  bool _isLoading = true;
  String? _errorMessage;

  String _selectedFilter = 'Recent';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadVisitHistory();
  }

  Future<void> _loadVisitHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          _errorMessage = 'Please log in to view your history';
          _isLoading = false;
        });
        return;
      }

      final result = await supabase
          .from('visitor_log')
          .select('''
            log_id,
            time_in,
            method,
            burial:burial_id (
              burial_id,
              name_of_deceased,
              death_date,
              cemetery_lot (
                lot_number,
                lot_label,
                block_number,
                lot_class_type
              )
            )
          ''')
          .eq('user_id', user.id)
          .order('time_in', ascending: false);

      final history = List<Map<String, dynamic>>.from(result);

      setState(() {
        _visitHistory = history;
        _filteredHistory = history;
        _isLoading = false;
      });

      _applyFilters();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading history: $e';
        _isLoading = false;
      });
    }
  }

  /// ✅ NEW: unified filter + sort logic
  void _applyFilters() {
    List<Map<String, dynamic>> data = List.from(_visitHistory);

    // SEARCH
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      data = data.where((visit) {
        final burial = visit['burial'] ?? {};
        final name = burial['name_of_deceased']?.toString().toLowerCase() ?? '';
        return name.contains(query);
      }).toList();
    }

    // SORTING
    if (_selectedFilter == 'Recent') {
      data.sort(
        (a, b) => DateTime.parse(
          b['time_in'],
        ).compareTo(DateTime.parse(a['time_in'])),
      );
    } else if (_selectedFilter == 'By Date') {
      data.sort(
        (a, b) => DateTime.parse(
          a['time_in'],
        ).compareTo(DateTime.parse(b['time_in'])),
      );
    } else if (_selectedFilter == 'By Name') {
      data.sort((a, b) {
        final nameA = (a['burial']?['name_of_deceased'] ?? '')
            .toString()
            .toLowerCase();
        final nameB = (b['burial']?['name_of_deceased'] ?? '')
            .toString()
            .toLowerCase();
        return nameA.compareTo(nameB);
      });
    }

    setState(() {
      _filteredHistory = data;
    });
  }

  String _formatDate(String? dateTimeString) {
    if (dateTimeString == null) return 'Unknown date';

    try {
      final date = DateTime.parse(dateTimeString);
      return DateFormat('MMM d, y').format(date);
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _formatTime(String? dateTimeString) {
    if (dateTimeString == null) return '--:--';

    try {
      final date = DateTime.parse(dateTimeString);
      return DateFormat('hh:mm a').format(date);
    } catch (e) {
      return '--:--';
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByMonth() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final visit in _filteredHistory) {
      final timeIn = visit['time_in'];
      if (timeIn == null) continue;

      final date = DateTime.parse(timeIn);
      final monthKey = DateFormat('MMMM y').format(date);

      grouped.putIfAbsent(monthKey, () => []);
      grouped[monthKey]!.add(visit);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colors(context).surfaceContainer,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
        elevation: 0,
        backgroundColor: _colors(context).surfaceContainer,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visit history',
              style: TextStyle(
                color: _colors(context).onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'Your quiet moments of remembrance',
              style: TextStyle(
                color: _colors(context).onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadVisitHistory,
            icon: Icon(Icons.refresh_rounded, color: _colors(context).primary),
            tooltip: 'Refresh history',
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildErrorWidget()
          : Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                _buildFilterChips(),
                Expanded(
                  child: _filteredHistory.isEmpty
                      ? _buildEmptyWidget()
                      : _buildHistoryList(),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: SurfaceStyle.panel(
          color: _colors(context).primary,
          radius: 26,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(Icons.history_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_visitHistory.length} ${_visitHistory.length == 1 ? 'visit' : 'visits'} recorded',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A gentle record of the people and places you have honored.',
                    style: TextStyle(
                      color: _colors(context).onPrimary.withValues(alpha: 0.78),
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _applyFilters(),
        decoration: InputDecoration(
          hintText: 'Search by deceased name...',
          hintStyle: TextStyle(
            color: _colors(context).onSurfaceVariant,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _colors(context).onSurfaceVariant,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _applyFilters();
                  },
                  icon: Icon(Icons.close_rounded),
                  color: _colors(context).onSurfaceVariant,
                  tooltip: 'Clear search',
                ),
          filled: true,
          fillColor: _colors(context).surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _colors(context).outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _colors(context).primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Recent', 'By Date', 'By Name'];

    return SizedBox(
      height: 68,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedFilter = filter);
                _applyFilters();
              },
              avatar: Icon(
                filter == 'Recent'
                    ? Icons.history_rounded
                    : filter == 'By Date'
                    ? Icons.calendar_today_rounded
                    : Icons.person_outline_rounded,
                size: 17,
                color: selected ? Colors.white : _colors(context).primary,
              ),
              label: Text(filter),
              labelStyle: TextStyle(
                color: selected ? Colors.white : _colors(context).onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: _colors(context).surface,
              selectedColor: _colors(context).primary,
              side: BorderSide(
                color: selected
                    ? _colors(context).primary
                    : _colors(context).outlineVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList() {
    final groupedHistory = _groupByMonth();

    return RefreshIndicator(
      onRefresh: _loadVisitHistory,
      color: _colors(context).primary,
      backgroundColor: _colors(context).surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: groupedHistory.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 12),
                child: Text(
                  entry.key.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: _colors(context).onSurfaceVariant,
                  ),
                ),
              ),

              ...entry.value.map((visit) {
                final burial = visit['burial'] ?? {};
                final lot = burial['cemetery_lot'] ?? {};

                final deceasedName =
                    burial['name_of_deceased'] ?? 'Unknown Grave';

                final lotNumber = lotReference(lot);
                final blockLabel = lotBlockLabel(lot);

                final timeIn = visit['time_in'];
                final formattedDate = _formatDate(timeIn);
                final formattedTime = _formatTime(timeIn);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _colors(context).surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _colors(context).outlineVariant),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D0066CC),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _colors(context).secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.church_rounded,
                          color: _colors(context).primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    deceasedName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _colors(context).onSurface,
                                      fontSize: 16,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formattedTime,
                                  style: TextStyle(
                                    color: _colors(context).onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 15,
                                  color: _colors(context).onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    '$blockLabel · Lot $lotNumber',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _colors(context).onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _colors(context).primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    formattedDate,
                                    style: TextStyle(
                                      color: _colors(context).primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (visit['method'] != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    visit['method'].toString(),
                                    style: TextStyle(
                                      color: _colors(context).onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _colors(context).primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                color: _colors(context).primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No visits yet',
              style: TextStyle(
                color: _colors(context).onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your completed cemetery visits will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _colors(context).onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: _colors(context).onSurfaceVariant,
              size: 42,
            ),
            const SizedBox(height: 14),
            Text(
              'We could not load your visits',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _colors(context).onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _colors(context).onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadVisitHistory,
              icon: Icon(Icons.refresh_rounded),
              label: Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
