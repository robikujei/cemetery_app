import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class VisitorHistoryScreen extends ConsumerStatefulWidget {
  const VisitorHistoryScreen({super.key});

  @override
  ConsumerState<VisitorHistoryScreen> createState() =>
      _VisitorHistoryScreenState();
}

class _VisitorHistoryScreenState
    extends ConsumerState<VisitorHistoryScreen> {
  List<Map<String, dynamic>> _visitHistory = [];
  List<Map<String, dynamic>> _filteredHistory = [];

  bool _isLoading = true;
  String? _errorMessage;

  String _selectedFilter = 'Recent';
  final TextEditingController _searchController = TextEditingController();

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
                section:section_id (
                  name
                )
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
        final name =
            burial['name_of_deceased']?.toString().toLowerCase() ?? '';
        return name.contains(query);
      }).toList();
    }

    // SORTING
    if (_selectedFilter == 'Recent') {
      data.sort((a, b) => DateTime.parse(b['time_in'])
          .compareTo(DateTime.parse(a['time_in'])));
    } else if (_selectedFilter == 'By Date') {
      data.sort((a, b) => DateTime.parse(a['time_in'])
          .compareTo(DateTime.parse(b['time_in'])));
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
      backgroundColor: const Color(0xFFFBF9F6),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white.withOpacity(0.92),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Visit History',
          style: TextStyle(
            color: Color(0xFF335538),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadVisitHistory,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF335538),
            ),
          ),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 10),
      child: Text(
        "A quiet record of the paths you've walked and the memories you've honored.",
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: Color(0xFF727971),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => _applyFilters(),
        decoration: InputDecoration(
          hintText: 'Search by deceased name...',
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Recent', 'By Date', 'By Name'];

    return SizedBox(
      height: 70,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = _selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedFilter = filter;
              });
              _applyFilters();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF4B6E4F)
                    : const Color(0xFFEAE8E5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    filter == 'Recent'
                        ? Icons.history
                        : filter == 'By Date'
                            ? Icons.calendar_month
                            : Icons.person,
                    size: 18,
                    color: selected ? Colors.white : const Color(0xFF424841),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    filter,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          selected ? Colors.white : const Color(0xFF424841),
                    ),
                  ),
                ],
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: groupedHistory.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 12),
                child: Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF727971),
                  ),
                ),
              ),

              ...entry.value.map((visit) {
                final burial = visit['burial'] ?? {};
                final lot = burial['cemetery_lot'] ?? {};
                final section = lot['section'] ?? {};

                final deceasedName =
                    burial['name_of_deceased'] ?? 'Unknown Grave';

                final lotNumber = lot['lot_number'] ?? 'N/A';
                final sectionName = section['name'] ?? 'N/A';

                final timeIn = visit['time_in'];
                final formattedDate = _formatDate(timeIn);
                final formattedTime = _formatTime(timeIn);

                return Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC7E4F3),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.church_rounded),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    deceasedName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  formattedTime,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Text(
                              'Section $sectionName • Plot $lotNumber',
                              style: const TextStyle(fontSize: 14),
                            ),

                            const SizedBox(height: 10),

                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF335538),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return const Center(
      child: Text('No visit history yet'),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Text(_errorMessage ?? 'Error'),
    );
  }
}