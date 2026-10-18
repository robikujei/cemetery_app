import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_pagination_service.dart';
import '../../utils/lot_formatters.dart';
import 'visitor_qr_with_grave_screen.dart';
import 'visitor_map_screen.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class VisitorSearchScreen extends ConsumerStatefulWidget {
  const VisitorSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<VisitorSearchScreen> createState() =>
      _VisitorSearchScreenState();
}

class _VisitorSearchScreenState extends ConsumerState<VisitorSearchScreen> {
  ColorScheme _colors(BuildContext context) => Theme.of(context).colorScheme;
  late final TextEditingController _queryCtrl;
  String _query = '';
  List<Map<String, dynamic>> _allGraves = [];
  List<Map<String, dynamic>> _filteredGraves = [];
  bool _isLoading = true;
  String _searchType = 'name';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _queryCtrl = TextEditingController(text: initial);
    _query = initial;
    _loadAllGraves();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllGraves() async {
    setState(() => _isLoading = true);
    try {
      final allBurials = await SupabasePaginationService.selectAll(
        supabase: Supabase.instance.client,
        table: 'burial_record',
        orderColumn: 'burial_id',
        columns: '''
            burial_id,
            name_of_deceased,
            birth_date,
            death_date,
            burial_date,
            lot_id,
            cemetery_lot!inner (
              lot_id,
              lot_number,
              lot_label,
              block_number,
              lot_class_type,
              x_coord,
              y_coord,
              status
            )
          ''',
      );
      allBurials.sort(
        (a, b) => (a['name_of_deceased'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name_of_deceased'] ?? '').toString().toLowerCase()),
      );

      setState(() {
        _allGraves = List<Map<String, dynamic>>.from(allBurials);
        _filteredGraves = List<Map<String, dynamic>>.from(allBurials);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading graves: $e'),
            backgroundColor: _colors(context).error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _filterGraves(String query) {
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _filteredGraves = List.from(_allGraves);
      } else {
        _filteredGraves = _allGraves.where((grave) {
          final name = grave['name_of_deceased']?.toLowerCase() ?? '';
          if (_searchType == 'name') return name.contains(query.toLowerCase());
          return lotSearchText(
            grave['cemetery_lot'],
          ).contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Map<String, dynamic> _createSearchResultData(Map<String, dynamic> burial) {
    final lot = burial['cemetery_lot'] ?? {};
    return {
      'name': burial['name_of_deceased'] ?? 'Unknown',
      'deceased_name': burial['name_of_deceased'] ?? 'Unknown',
      'lot_number': lotReference(lot, fallback: ''),
      'block_name': lotBlockLabel(lot, fallback: ''),
      'lot_id': lot['lot_id'],
      'type': 'deceased',
      'burial_id': burial['burial_id'],
      'death_date': burial['death_date'],
      'burial_date': burial['burial_date'],
    };
  }

  void _saveSearchAndReturn(Map<String, dynamic> burial) {
    Navigator.pop(context, _createSearchResultData(burial));
  }

  void _generateQRForGrave(Map<String, dynamic> burial) {
    final lot = burial['cemetery_lot'] ?? {};
    _saveSearchAndReturn(burial);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitorQrWithGraveScreen(
          burialId: burial['burial_id'],
          deceasedName: burial['name_of_deceased'],
          lotNumber: lotReference(lot, fallback: ''),
          blockName: lotBlockLabel(lot, fallback: 'Unknown'),
        ),
      ),
    );
  }

  void _getDirections(Map<String, dynamic> burial) {
    final lot = burial['cemetery_lot'] ?? {};
    _saveSearchAndReturn(burial);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitorMapScreenWithDestination(
          destinationLotId: lot['lot_id'],
          destinationLotNumber: lotReference(lot, fallback: ''),
        ),
      ),
    );
  }

  // ── Avatar color cycling ─────────────────────────────────────────────────
  Color _avatarBg(int index) {
    final colors = [
      _colors(context).primaryContainer,
      _colors(context).secondaryContainer,
      _colors(context).tertiaryContainer,
    ];
    return colors[index % colors.length];
  }

  Color _avatarFg(int index) {
    final colors = [
      _colors(context).primary,
      _colors(context).secondary,
      _colors(context).tertiary,
    ];
    return colors[index % colors.length];
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colors(context).surfaceContainer,
      appBar: AppBar(
        backgroundColor: _colors(context).surface.withOpacity(0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _colors(context).onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 4,
        title: Row(
          children: [
            Icon(Icons.church, color: _colors(context).primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Eternal Garden',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _colors(context).primary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: _colors(context).primary,
              size: 22,
            ),
            onPressed: _loadAllGraves,
          ),
          IconButton(
            icon: Icon(
              Icons.notifications_outlined,
              color: _colors(context).primary,
              size: 22,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: _colors(context).outlineVariant,
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: _colors(context).primary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search Results',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w400,
                          color: _colors(context).onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _query.isEmpty
                            ? 'Showing all ${_filteredGraves.length} records'
                            : 'Showing ${_filteredGraves.length} match${_filteredGraves.length == 1 ? '' : 'es'} for "$_query"',
                        style: TextStyle(
                          fontSize: 14,
                          color: _colors(context).onSurfaceVariant,
                          letterSpacing: 0.25,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Search bar ──────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _colors(context).surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _colors(
                              context,
                            ).outlineVariant.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              color: _colors(context).outline,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _queryCtrl,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _colors(context).onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: _searchType == 'name'
                                      ? 'Search deceased name...'
                                      : 'Search lot or block...',
                                  hintStyle: TextStyle(
                                    color: _colors(context).outline,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: _filterGraves,
                              ),
                            ),
                            if (_query.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _queryCtrl.clear();
                                  _filterGraves('');
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  color: _colors(context).outline,
                                  size: 18,
                                ),
                              ),
                            const SizedBox(width: 8),

                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _colors(context).surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: DropdownButton<String>(
                                  value: _searchType,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'name',
                                      child: Text(
                                        'Name',
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'lot',
                                      child: Text(
                                        'Lot #',
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _searchType = v!;
                                    _filterGraves(_query);
                                  }),
                                  underline: const SizedBox(),
                                  isDense: true,
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: _colors(context).primary,
                                    size: 18,
                                  ),
                                  style: TextStyle(
                                    color: _colors(context).onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Results list ──────────────────────────────────
                Expanded(
                  child: _filteredGraves.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 56,
                                color: _colors(
                                  context,
                                ).outline.withOpacity(0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No graves found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _colors(context).outline,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                          itemCount: _filteredGraves.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final grave = _filteredGraves[index];
                            final lot = grave['cemetery_lot'] ?? {};
                            final deathDate = grave['death_date'] != null
                                ? DateFormat(
                                    'MMM d, y',
                                  ).format(DateTime.parse(grave['death_date']))
                                : null;

                            return _buildResultCard(
                              grave: grave,
                              lot: lot,
                              deathDate: deathDate,
                              index: index,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ── Result card ──────────────────────────────────────────────────────────
  Widget _buildResultCard({
    required Map<String, dynamic> grave,
    required Map<String, dynamic> lot,
    required String? deathDate,
    required int index,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 430;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _colors(context).surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _colors(context).surfaceContainerLow),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A3B82F6),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: isSmallScreen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _avatarBg(index),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: _avatarFg(index),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                grave['name_of_deceased'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: _colors(context).onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),

                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.tag_rounded,
                                        size: 16,
                                        color: _colors(
                                          context,
                                        ).onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Lot ${lotReference(lot)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _colors(
                                            context,
                                          ).onSurfaceVariant,
                                          letterSpacing: 0.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              if (deathDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  deathDate,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _colors(context).outline,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              onPressed: () => _getDirections(grave),
                              style: FilledButton.styleFrom(
                                backgroundColor: _colors(context).primary,
                                foregroundColor: _colors(context).onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                textStyle: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              icon: Icon(Icons.near_me_rounded, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('View Location'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              onPressed: () => _generateQRForGrave(grave),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _colors(context).primary,
                                side: BorderSide(
                                  color: _colors(context).outlineVariant,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                textStyle: TextStyle(
                                  fontFamily: '.SF Pro Text',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              icon: Icon(Icons.qr_code_rounded, size: 14),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('QR Code'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _avatarBg(index),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        color: _avatarFg(index),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grave['name_of_deceased'] ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: _colors(context).onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.tag_rounded,
                                    size: 16,
                                    color: _colors(context).onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Lot ${lotReference(lot)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _colors(context).onSurfaceVariant,
                                      letterSpacing: 0.25,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.tag_rounded,
                                    size: 16,
                                    color: _colors(context).onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Lot ${lotReference(lot)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _colors(context).onSurfaceVariant,
                                      letterSpacing: 0.25,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (deathDate != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              deathDate,
                              style: TextStyle(
                                fontSize: 11,
                                color: _colors(context).outline,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    Column(
                      children: [
                        SizedBox(
                          height: 42,
                          child: FilledButton.icon(
                            onPressed: () => _getDirections(grave),
                            style: FilledButton.styleFrom(
                              backgroundColor: _colors(context).primary,
                              foregroundColor: _colors(context).onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              textStyle: TextStyle(
                                fontFamily: '.SF Pro Text',
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: Icon(Icons.near_me_rounded, size: 16),
                            label: Text('View Location'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: OutlinedButton.icon(
                            onPressed: () => _generateQRForGrave(grave),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _colors(context).primary,
                              side: BorderSide(
                                color: _colors(context).outlineVariant,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              textStyle: TextStyle(
                                fontFamily: '.SF Pro Text',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: Icon(Icons.qr_code_rounded, size: 14),
                            label: Text('QR Code'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  // ── Bottom sheet ─────────────────────────────────────────────────────────
  void _showGraveDetails(
    Map<String, dynamic> burial,
    Map<String, dynamic> lot,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _colors(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _colors(context).outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              burial['name_of_deceased'] ?? 'Unknown',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: _colors(context).onSurface,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              Icons.location_on_outlined,
              'Lot ${lotReference(lot)}',
            ),
            if (burial['death_date'] != null)
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'Died: ${DateFormat('MMM d, y').format(DateTime.parse(burial['death_date']))}',
              ),
            if (burial['burial_date'] != null)
              _buildInfoRow(
                Icons.calendar_today_outlined,
                'Buried: ${DateFormat('MMM d, y').format(DateTime.parse(burial['burial_date']))}',
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _getDirections(burial);
                      },
                      icon: Icon(Icons.near_me_rounded, size: 18),
                      label: Text('Directions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _colors(context).primary,
                        side: BorderSide(color: _colors(context).primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _generateQRForGrave(burial);
                      },
                      icon: Icon(Icons.qr_code_rounded, size: 18),
                      label: Text('QR Code'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _colors(context).primary,
                        foregroundColor: _colors(context).onPrimaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _colors(context).outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: _colors(context).onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
