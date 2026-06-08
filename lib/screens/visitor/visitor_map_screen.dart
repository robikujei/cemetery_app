import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/map_feature_service.dart';
import '../../providers/visitor_nav_providers.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/map_feature_geometry.dart';
import 'visitor_qr_with_grave_screen.dart';

class _C {
  static const background = Color(0xFFFBF9F6);
  static const primary = Color(0xFF335538);
  static const primaryContainer = Color(0xFF4B6E4F);
  static const primaryFixedDim = Color(0xFFAAD0AB);
  static const surfaceContainerHigh = Color(0xFFEAE8E5);
  static const surfaceContainerHighest = Color(0xFFE4E2DF);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const outline = Color(0xFF727971);
  static const outlineVariant = Color(0xFFC2C8BF);
  static const secondary = Color(0xFF47626F);
  static const tertiary = Color(0xFF5A4B3F);
  static const error = Color(0xFFBA1A1A);
  static const white = Color(0xFFFFFFFF);
}

class VisitorMapScreen extends ConsumerStatefulWidget {
  final int? initialLotId;
  final String? initialLotNumber;

  const VisitorMapScreen({super.key, this.initialLotId, this.initialLotNumber});

  @override
  ConsumerState<VisitorMapScreen> createState() => _VisitorMapScreenState();
}

class _VisitorMapScreenState extends ConsumerState<VisitorMapScreen> {
  static final LatLng _tagumMapCenter = LatLng(7.3793125, 125.753328125);
  static const double _initialZoom = 18;
  static const double _markerLatSpan = 0.0036;
  static const double _markerLngSpan = 0.0046;

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _lotMarkers = [];
  List<Map<String, dynamic>> _pathNodes = [];
  List<Map<String, dynamic>> _pathEdges = [];
  List<Map<String, dynamic>> _mapFeatures = [];
  Map<String, List<Map<String, dynamic>>> _gravesByLotId = {};

  double? _entranceXPercent;
  double? _entranceYPercent;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final LayerHitNotifier<String> _lotPolygonHitNotifier = ValueNotifier(null);
  RealtimeChannel? _lotChangesChannel;
  LatLng _mapCenter = _tagumMapCenter;
  double _activeMarkerLatSpan = _markerLatSpan;
  double _activeMarkerLngSpan = _markerLngSpan;

  int? _selectedLotId;
  String? _selectedLotNumber;
  Map<String, dynamic>? _selectedMarker;
  Map<String, dynamic>? _selectedGrave;
  bool _showNavigationRoute = false;
  double _currentZoom = _initialZoom;

  @override
  void initState() {
    super.initState();
    _loadMapData();
    _subscribeToLotChanges();
  }

  @override
  void dispose() {
    final lotChangesChannel = _lotChangesChannel;
    if (lotChangesChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(lotChangesChannel));
    }
    _searchController.dispose();
    _lotPolygonHitNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final mapConfig = await supabase
          .from('cemetery_map')
          .select('*')
          .order('uploaded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mapConfig != null) {
        final centerLat = (mapConfig['center_lat'] as num?)?.toDouble();
        final centerLng = (mapConfig['center_lng'] as num?)?.toDouble();
        if (centerLat != null && centerLng != null) {
          _mapCenter = LatLng(centerLat, centerLng);
        }
        _activeMarkerLatSpan =
            (mapConfig['lat_span'] as num?)?.toDouble() ?? _markerLatSpan;
        _activeMarkerLngSpan =
            (mapConfig['lng_span'] as num?)?.toDouble() ?? _markerLngSpan;
        _entranceXPercent = (mapConfig['entrance_x_percent'] as num?)
            ?.toDouble();
        _entranceYPercent = (mapConfig['entrance_y_percent'] as num?)
            ?.toDouble();
      }

      final results = await Future.wait([
        supabase
            .from('lot_markers')
            .select('''
              marker_id,
              lot_id,
              x_percent,
              y_percent,
              cemetery_lot (
                lot_id,
                lot_number,
                lot_label,
                block_number,
                lot_class_type,
                polygon_geo,
                price,
                status,
                burial_record (
                  burial_id,
                  name_of_deceased,
                  birth_date,
                  death_date,
                  burial_date,
                  lot_location_no
                )
              )
            ''')
            .order('marker_id'),
        supabase
            .from('burial_record')
            .select(
              'burial_id, name_of_deceased, birth_date, death_date, burial_date, lot_id, lot_location_no',
            )
            .order('name_of_deceased'),
        supabase.from('path_nodes').select('*').order('node_id'),
        supabase.from('path_edges').select('*').order('edge_id'),
      ]);
      final lotMarkers = _markersWithBurials(
        List<Map<String, dynamic>>.from(results[0] as List),
        List<Map<String, dynamic>>.from(results[1] as List),
      );
      final gravesByLotId = await _loadGravesByLotIds(
        supabase,
        lotMarkers.map(_markerLotId),
      );
      final mapFeatures = await MapFeatureService.loadVisible(supabase);

      if (!mounted) return;

      setState(() {
        _lotMarkers = lotMarkers;
        _pathNodes = List<Map<String, dynamic>>.from(results[2] as List);
        _pathEdges = List<Map<String, dynamic>>.from(results[3] as List);
        _mapFeatures = mapFeatures;
        _gravesByLotId = gravesByLotId;
        _isLoading = false;
      });

      if (widget.initialLotId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _selectInitialLot();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _subscribeToLotChanges() {
    _lotChangesChannel = Supabase.instance.client
        .channel('visitor-map-lot-changes-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cemetery_lot',
          callback: _handleLotChange,
        )
        .subscribe();
  }

  void _handleLotChange(PostgresChangePayload payload) {
    if (!mounted) return;

    if (payload.eventType == PostgresChangeEvent.delete) {
      final deletedLotId = payload.oldRecord['lot_id'];
      if (deletedLotId != null) _removeLotMarkerByLotId(deletedLotId);
      return;
    }

    if (payload.newRecord.isEmpty) return;
    _mergeLotIntoMarker(payload.newRecord);
  }

  void _mergeLotIntoMarker(Map<String, dynamic> updatedLot) {
    final lotId = updatedLot['lot_id'];
    if (lotId == null) return;

    final index = _lotMarkers.indexWhere(
      (marker) => _sameRecordId(_markerLotId(marker), lotId),
    );
    if (index == -1) return;

    final currentMarker = Map<String, dynamic>.from(_lotMarkers[index]);
    final currentLot = Map<String, dynamic>.from(
      currentMarker['cemetery_lot'] ?? {},
    );
    currentMarker['cemetery_lot'] = {...currentLot, ...updatedLot};

    setState(() {
      _lotMarkers[index] = currentMarker;
      if (_selectedMarker != null &&
          _sameRecordId(_markerLotId(_selectedMarker!), lotId)) {
        _selectedMarker = currentMarker;
        _selectedLotId = currentMarker['cemetery_lot']?['lot_id'];
        _selectedLotNumber = lotReference(currentMarker['cemetery_lot']);
      }
    });
  }

  void _removeLotMarkerByLotId(dynamic lotId) {
    final index = _lotMarkers.indexWhere(
      (marker) => _sameRecordId(_markerLotId(marker), lotId),
    );
    if (index == -1) return;

    setState(() {
      final removed = _lotMarkers.removeAt(index);
      _gravesByLotId.remove(lotId.toString());
      if (_selectedMarker != null &&
          _sameRecordId(
            _markerLotId(removed),
            _markerLotId(_selectedMarker!),
          )) {
        _selectedMarker = null;
        _selectedGrave = null;
        _selectedLotId = null;
        _selectedLotNumber = null;
        _showNavigationRoute = false;
        _searchController.clear();
      }
    });
  }

  void _selectInitialLot() {
    final marker = _lotMarkers.firstWhere(
      (m) => m['cemetery_lot']?['lot_id'] == widget.initialLotId,
      orElse: () => {},
    );

    if (marker.isNotEmpty) {
      _selectMarker(marker, showSheet: true, showRoute: true);
    } else {
      setState(() {
        _selectedLotId = widget.initialLotId;
        _selectedLotNumber = widget.initialLotNumber;
        _showNavigationRoute = false;
      });
    }
  }

  List<Map<String, dynamic>> _markersWithBurials(
    List<Map<String, dynamic>> markers,
    List<Map<String, dynamic>> burials,
  ) {
    final burialsByLotId = <String, List<Map<String, dynamic>>>{};
    for (final burial in burials) {
      final lotId = burial['lot_id']?.toString();
      if (lotId != null && lotId.isNotEmpty) {
        burialsByLotId.putIfAbsent(lotId, () => []).add(burial);
      }
    }

    return markers.map((marker) {
      final normalizedMarker = Map<String, dynamic>.from(marker);
      final lot = Map<String, dynamic>.from(
        normalizedMarker['cemetery_lot'] ?? {},
      );
      final lotId = lot['lot_id'] ?? normalizedMarker['lot_id'];
      final lotBurials = <Map<String, dynamic>>[
        ..._burialsForLot(lot),
        ...(burialsByLotId[lotId?.toString()] ?? []),
      ];
      final dedupedBurials = <Map<String, dynamic>>[];
      final seenBurialIds = <String>{};
      for (final burial in lotBurials) {
        final burialId = _burialId(burial);
        if (burialId != null && !seenBurialIds.add(burialId)) continue;
        dedupedBurials.add(burial);
      }
      if (dedupedBurials.isNotEmpty) {
        lot['burial_record'] = dedupedBurials;
      }
      normalizedMarker['cemetery_lot'] = lot;
      return normalizedMarker;
    }).toList();
  }

  void _selectMarker(
    Map<String, dynamic> marker, {
    bool showSheet = false,
    bool showRoute = false,
    Map<String, dynamic>? grave,
  }) {
    final lot = marker['cemetery_lot'] ?? {};
    setState(() {
      _selectedMarker = marker;
      _selectedGrave = grave;
      _selectedLotId = lot['lot_id'];
      _selectedLotNumber = lotReference(lot);
      _showNavigationRoute = showRoute;
    });

    if (showSheet) {
      _showLotDetails(marker);
    }
  }

  void _startRouteToMarker(
    Map<String, dynamic> marker, {
    Map<String, dynamic>? grave,
  }) {
    _selectMarker(marker, showRoute: true, grave: grave);
  }

  void _selectMarkerByLotId(String lotId, {bool showSheet = false}) {
    final marker = _lotMarkers.cast<Map<String, dynamic>?>().firstWhere(
      (marker) => marker != null && _markerLotId(marker).toString() == lotId,
      orElse: () => null,
    );
    if (marker != null) _selectMarker(marker, showSheet: showSheet);
  }

  void _clearSelection() {
    setState(() {
      _selectedMarker = null;
      _selectedGrave = null;
      _selectedLotId = null;
      _selectedLotNumber = null;
      _showNavigationRoute = false;
      _searchController.clear();
    });
  }

  void _searchLot(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return;

    final marker = _lotMarkers.cast<Map<String, dynamic>?>().firstWhere((m) {
      final lot = m?['cemetery_lot'] ?? {};
      final status = lot['status']?.toString().toLowerCase() ?? '';
      return lotSearchText(lot).contains(needle) || status.contains(needle);
    }, orElse: () => null);

    if (marker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No lot found for "$query"'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _C.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
      return;
    }

    _selectMarker(marker, showSheet: true, showRoute: true);
  }

  void _zoomBy(double delta) {
    _currentZoom = (_currentZoom + delta).clamp(15.0, 20.0);
    _mapController.move(_mapController.camera.center, _currentZoom);
  }

  void _resetView() {
    _currentZoom = _initialZoom;
    _mapController.move(_routeStart, _currentZoom);
  }

  void _handleBackPressed() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    ref.read(visitorNavIndexProvider.notifier).state = 0;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadGravesByLotIds(
    SupabaseClient supabase,
    Iterable<dynamic> lotIds,
  ) async {
    final normalizedIds = lotIds
        .where((id) => id != null)
        .map((id) => int.tryParse(id.toString()))
        .whereType<int>()
        .toSet()
        .toList();

    if (normalizedIds.isEmpty) return {};

    try {
      final rows = await supabase
          .from('graves')
          .select('''
            grave_id,
            lot_id,
            grave_label,
            status,
            burial_id,
            notes,
            burial:burial_id (
              burial_id,
              name_of_deceased,
              birth_date,
              death_date,
              burial_date,
              interment_date,
              interment_time,
              religion,
              burial_category
            )
          ''')
          .inFilter('lot_id', normalizedIds)
          .order('grave_label');

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows as List) {
        final grave = Map<String, dynamic>.from(row as Map);
        final lotId = grave['lot_id']?.toString();
        if (lotId == null) continue;
        grouped.putIfAbsent(lotId, () => []).add(grave);
      }
      return grouped;
    } catch (_) {
      return {};
    }
  }

  void _showLotDetails(
    Map<String, dynamic> marker, {
    Map<String, dynamic>? grave,
  }) {
    final lot = marker['cemetery_lot'] ?? {};
    final status =
        _graveStatus(grave) ?? lot['status']?.toString() ?? 'Unknown';
    final isAvailable = status.toLowerCase() == 'available';
    final statusColor = _statusColor(status);
    final burial = _burialForGrave(grave) ?? _burialForLot(lot);
    final graveLabel = _graveLabel(grave);
    final lotNumber = lotReference(lot, fallback: _selectedLotNumber ?? '--');
    final meta = lotMeta(lot);
    final title =
        burial?['name_of_deceased']?.toString().trim().isNotEmpty == true
        ? burial!['name_of_deceased'].toString()
        : graveLabel ?? 'Lot $lotNumber';
    final subtitle = graveLabel == null
        ? 'Plot $lotNumber'
        : '$graveLabel - Plot $lotNumber';
    final routePoints = _routeFromEntranceToLot(marker);
    final distanceMeters = _routeDistanceMeters(routePoints);
    final distanceText = distanceMeters == null
        ? '--'
        : distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.round()}m';
    final walkText = distanceMeters == null
        ? '--'
        : '${max(1, (distanceMeters / 75).ceil())} mins';

    showModalBottomSheet(
      context: context,
      backgroundColor: _C.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: _C.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _C.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.location_on_rounded, color: statusColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _C.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _C.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (burial != null) ...[
              _buildDetailRow(
                Icons.cake_outlined,
                'Born',
                _formatDate(burial['birth_date']),
                null,
              ),
              _buildDetailRow(
                Icons.church_outlined,
                'Passed',
                _formatDate(burial['death_date']),
                null,
              ),
            ],
            _buildDetailRow(
              Icons.info_outline_rounded,
              'Status',
              status,
              statusColor,
            ),
            if (meta.isNotEmpty)
              _buildDetailRow(
                Icons.grid_view_rounded,
                'Lot Details',
                meta,
                null,
              ),
            if (graveLabel != null)
              _buildDetailRow(Icons.church_outlined, 'Grave', graveLabel, null),
            if (isAvailable && burial == null)
              _buildDetailRow(
                Icons.payments_outlined,
                'Price',
                'PHP ${lot['price'] ?? '--'}',
                null,
              ),
            _buildDetailRow(
              Icons.route_rounded,
              'Distance',
              distanceText,
              null,
            ),
            _buildDetailRow(
              Icons.directions_walk_rounded,
              'Walk',
              walkText,
              null,
            ),
            const SizedBox(height: 18),
            if (burial != null) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showGenerateQrPrompt(lot: lot, burial: burial);
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Generate Visit QR Code'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _C.secondary,
                    foregroundColor: _C.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _startRouteToMarker(marker, grave: grave);
                },
                icon: const Icon(Icons.near_me_rounded, size: 18),
                label: const Text('Start Route'),
                style: FilledButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: _C.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGenerateQrPrompt({
    required Map<String, dynamic> lot,
    required Map<String, dynamic> burial,
  }) async {
    final lotNumber = lotReference(lot, fallback: '--');
    final deceasedName = burial['name_of_deceased']?.toString() ?? 'Unknown';

    final shouldGenerate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _C.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Generate visit QR?'),
        content: Text(
          'Create a QR code to check in for visiting $deceasedName at Lot $lotNumber.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: const Text('Generate'),
            style: FilledButton.styleFrom(
              backgroundColor: _C.primary,
              foregroundColor: _C.white,
            ),
          ),
        ],
      ),
    );

    if (shouldGenerate != true || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitorQrWithGraveScreen(
          burialId: _asInt(burial['burial_id']),
          deceasedName: deceasedName,
          lotNumber: lotNumber,
          blockName: lotBlockLabel(lot, fallback: 'Unknown'),
        ),
      ),
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic>? _burialForLot(Map<String, dynamic> lot) {
    final burials = _burialsForLot(lot);
    return burials.isEmpty ? null : burials.first;
  }

  List<Map<String, dynamic>> _burialsForLot(Map<String, dynamic> lot) {
    final burialRecord = lot['burial_record'];
    if (burialRecord is List) {
      return burialRecord
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .toList();
    }
    if (burialRecord is Map) {
      return [Map<String, dynamic>.from(burialRecord)];
    }
    return [];
  }

  List<Map<String, dynamic>> _gravesForMarker(Map<String, dynamic> marker) {
    final lotId = _markerLotId(marker)?.toString();
    final graves = lotId == null ? null : _gravesByLotId[lotId];
    final lot = marker['cemetery_lot'];
    final lotMap = lot is Map
        ? Map<String, dynamic>.from(lot)
        : <String, dynamic>{};
    final lotBurials = _burialsForLot(lotMap);

    if (graves != null && graves.isNotEmpty) {
      final mergedGraves = graves
          .map((grave) => Map<String, dynamic>.from(grave))
          .toList();
      final graveBurialIds = mergedGraves
          .map((grave) => _burialId(grave) ?? _burialId(_burialForGrave(grave)))
          .whereType<String>()
          .toSet();

      for (final burial in lotBurials) {
        final burialId = _burialId(burial);
        if (burialId != null && graveBurialIds.contains(burialId)) continue;
        mergedGraves.add({
          'grave_label': _lotBurialGraveLabel(
            burial,
            fallback: 'Grave ${mergedGraves.length + 1}',
          ),
          'status': 'Occupied',
          'burial': burial,
          'burial_id': burial['burial_id'],
        });
        if (burialId != null) graveBurialIds.add(burialId);
      }

      return mergedGraves;
    }

    if (lotBurials.isNotEmpty) {
      return lotBurials.map((burial) {
        return {
          'grave_label': _lotBurialGraveLabel(burial, fallback: 'Grave'),
          'status': 'Occupied',
          'burial': burial,
          'burial_id': burial['burial_id'],
        };
      }).toList();
    }

    final lotNumber = lotReference(lotMap, fallback: 'Selected lot');

    return [
      {
        'grave_label': lotNumber,
        'status': lotMap['status']?.toString() ?? 'Available',
        'burial': null,
        'burial_id': null,
      },
    ];
  }

  Map<String, dynamic>? _burialForGrave(Map<String, dynamic>? grave) {
    if (grave == null) return null;
    final burial = grave['burial'];
    if (burial is List && burial.isNotEmpty) {
      return Map<String, dynamic>.from(burial.first as Map);
    }
    if (burial is Map) return Map<String, dynamic>.from(burial);
    return null;
  }

  String? _burialId(Map<String, dynamic>? burial) {
    final burialId = burial?['burial_id']?.toString().trim();
    return burialId == null || burialId.isEmpty ? null : burialId;
  }

  String _lotBurialGraveLabel(
    Map<String, dynamic> burial, {
    required String fallback,
  }) {
    final lotLocation = burial['lot_location_no']?.toString().trim();
    if (lotLocation != null && lotLocation.isNotEmpty) return lotLocation;
    return fallback;
  }

  String? _graveStatus(Map<String, dynamic>? grave) {
    final status = grave?['status']?.toString().trim();
    return status == null || status.isEmpty ? null : status;
  }

  String? _graveLabel(Map<String, dynamic>? grave) {
    final label = grave?['grave_label']?.toString().trim();
    return label == null || label.isEmpty ? null : label;
  }

  String _graveTitle(Map<String, dynamic> grave) {
    final burial = _burialForGrave(grave);
    final deceasedName = burial?['name_of_deceased']?.toString().trim();
    if (deceasedName != null && deceasedName.isNotEmpty) return deceasedName;
    return _graveLabel(grave) ?? 'Grave';
  }

  String _graveSubtitle(Map<String, dynamic> grave) {
    final label = _graveLabel(grave);
    final status = _graveStatus(grave);
    final burial = _burialForGrave(grave);
    final deathDate = _formatDate(burial?['death_date']);
    final details = <String>[
      if (label != null && label != _graveTitle(grave)) label,
      if (deathDate != '--') 'Died $deathDate',
      if (status != null && deathDate == '--') status,
    ];
    return details.isEmpty ? 'Tap to view grave details' : details.join(' - ');
  }

  String _formatDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '--';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, y').format(parsed);
  }

  double? _routeDistanceMeters(List<LatLng> points) {
    if (points.length < 2) return null;
    var distance = 0.0;
    for (var i = 1; i < points.length; i++) {
      distance += _coordinateDistanceMeters(points[i - 1], points[i]);
    }
    return distance;
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color? valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _C.outline),
          const SizedBox(width: 12),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(color: _C.onSurfaceVariant, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: valueColor ?? _C.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _C.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _errorMessage != null
          ? _buildErrorWidget()
          : Stack(
              children: [
                Positioned.fill(child: _buildMap()),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      Expanded(
                        child: Stack(
                          children: [
                            _buildSearchBar(),
                            _buildLegend(),
                            _buildControls(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedMarker != null && !_showNavigationRoute)
                  _buildGraveChooserCard(),
                if ((_selectedMarker != null && _showNavigationRoute) ||
                    (_selectedMarker == null && _selectedLotNumber != null))
                  _buildRouteCard(),
              ],
            ),
    );
  }

  Widget _buildTopBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: _C.white.withValues(alpha: 0.9),
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _handleBackPressed,
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, color: _C.onSurface),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Eternal Rest',
                  style: TextStyle(
                    color: _C.primaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (_selectedLotId != null)
                IconButton(
                  onPressed: _clearSelection,
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close_rounded, color: _C.onSurface),
                ),
              IconButton(
                onPressed: _loadMapData,
                tooltip: 'Refresh map',
                icon: const Icon(Icons.refresh_rounded, color: _C.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Positioned(
      top: 16,
      left: 24,
      right: 86,
      child: _glass(
        borderRadius: 18,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.search_rounded, color: _C.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _searchLot,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14, color: _C.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Search by name or lot',
                    hintStyle: TextStyle(color: _C.outline),
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _searchLot(_searchController.text),
                icon: const Icon(
                  Icons.mic_none_rounded,
                  color: _C.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      top: 86,
      left: 24,
      child: _glass(
        borderRadius: 18,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendItem(
                color: lotStatusAvailableFill,
                borderColor: lotStatusAvailableStroke,
                label: 'Available',
              ),
              SizedBox(height: 12),
              _LegendItem(
                color: lotStatusReservedFill,
                borderColor: lotStatusReservedStroke,
                label: 'Owner assigned',
              ),
              SizedBox(height: 12),
              _LegendItem(
                color: lotStatusOccupiedFill,
                borderColor: lotStatusOccupiedStroke,
                label: 'Occupied',
              ),
              SizedBox(height: 12),
              _LegendItem(color: _C.tertiary, label: 'Popular'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      top: 16,
      right: 24,
      child: Column(
        children: [
          _glass(
            borderRadius: 18,
            child: Column(
              children: [
                _controlButton(Icons.add_rounded, () => _zoomBy(0.2)),
                Container(height: 1, width: 32, color: _C.surfaceContainerHigh),
                _controlButton(Icons.remove_rounded, () => _zoomBy(-0.2)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _glass(
            borderRadius: 18,
            child: _controlButton(
              Icons.my_location_rounded,
              _resetView,
              color: _C.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onPressed, {Color? color}) {
    return IconButton(
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 50, height: 50),
      icon: Icon(icon, color: color ?? _C.onSurfaceVariant),
    );
  }

  Widget _buildRouteCard() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final selectedGrave = _selectedGrave;
    final chosenGraveText = selectedGrave == null
        ? null
        : _graveTitle(selectedGrave);
    final lotText =
        chosenGraveText ??
        (_selectedLotNumber == null
            ? 'Selected grave marker'
            : 'Plot ${_selectedLotNumber!}');
    final routeTargetText =
        chosenGraveText == null || _selectedLotNumber == null
        ? null
        : 'Plot ${_selectedLotNumber!}';
    final routePoints = _selectedMarker == null
        ? <LatLng>[]
        : _routeFromEntranceToLot(_selectedMarker!);
    final distanceMeters = _routeDistanceMeters(routePoints);
    final routeSummary = distanceMeters == null
        ? 'Route unavailable'
        : distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km • ${max(1, (distanceMeters / 75).ceil())} mins walking'
        : '${distanceMeters.round()}m • ${max(1, (distanceMeters / 75).ceil())} mins walking';

    return Positioned(
      left: 24,
      right: 24,
      bottom: bottomInset + 28,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _C.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _softIcon(Icons.near_me_rounded, _C.primaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lotText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _C.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (routeTargetText != null) ...[
                    Text(
                      routeTargetText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _C.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    routeSummary,
                    style: const TextStyle(
                      color: _C.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _selectedMarker == null
                  ? null
                  : () => _startRouteToMarker(
                      _selectedMarker!,
                      grave: _selectedGrave,
                    ),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.white,
                disabledBackgroundColor: _C.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Start Route'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraveChooserCard() {
    final marker = _selectedMarker;
    if (marker == null) return const SizedBox.shrink();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final lot = marker['cemetery_lot'] ?? {};
    final lotNumber = lotReference(lot, fallback: _selectedLotNumber ?? '--');
    final graves = _gravesForMarker(marker);
    final graveCountText = graves.length == 1
        ? '1 grave'
        : '${graves.length} graves';

    return Positioned(
      left: 18,
      right: 18,
      bottom: bottomInset + 24,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _C.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _softIcon(Icons.church_outlined, _C.primaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Choose a grave to navigate',
                        style: const TextStyle(
                          color: _C.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lot $lotNumber - $graveCountText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _C.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: graves.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: _C.surfaceContainerHigh),
                itemBuilder: (context, index) =>
                    _buildGraveChoiceRow(marker, graves[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraveChoiceRow(
    Map<String, dynamic> marker,
    Map<String, dynamic> grave,
  ) {
    final status = _graveStatus(grave) ?? 'Unknown';
    final statusColor = _statusColor(status);
    final burial = _burialForGrave(grave);
    final lot = marker['cemetery_lot'];
    final lotMap = lot is Map
        ? Map<String, dynamic>.from(lot)
        : <String, dynamic>{};

    return InkWell(
      onTap: () => _startRouteToMarker(marker, grave: grave),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_statusIcon(status), color: statusColor, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _graveTitle(grave),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _C.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_graveSubtitle(grave)} - Tap to navigate',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _C.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (burial != null) ...[
              TextButton.icon(
                onPressed: () =>
                    _showGenerateQrPrompt(lot: lotMap, burial: burial),
                icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                label: const Text('QR'),
                style: TextButton.styleFrom(
                  foregroundColor: _C.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 2),
            ],
            TextButton(
              onPressed: () => _startRouteToMarker(marker, grave: grave),
              style: TextButton.styleFrom(
                foregroundColor: _C.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Route'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final routePoints = !_showNavigationRoute || _selectedMarker == null
        ? <LatLng>[]
        : _routeFromEntranceToLot(_selectedMarker!);
    final visibleMapFeatures = _visitorVisibleMapFeatures;
    final baseMapFeatures = visibleMapFeatures
        .where(isMapLayerFeature)
        .toList();
    final overlayMapFeatures = visibleMapFeatures
        .where((feature) => !isMapLayerFeature(feature))
        .toList();
    final basePolygons = mapFeaturePolygons(baseMapFeatures);
    final basePolylines = mapFeaturePolylines(baseMapFeatures);
    final overlayPolygons = mapFeaturePolygons(overlayMapFeatures);
    final overlayPolylines = mapFeaturePolylines(overlayMapFeatures);
    final overlayPointMarkers = mapFeaturePointMarkers(overlayMapFeatures);
    final lotPolygons = lotPolygonsFromMarkers(
      _lotMarkers,
      selectedLotId: _selectedLotId,
      includeHitValues: true,
    );
    final markers = <Marker>[
      if (_hasRouteStart)
        Marker(
          point: _routeStart,
          width: 46,
          height: 46,
          child: _buildEntranceMarker(),
        ),
      ..._lotMarkers.where((marker) => !markerHasLotPolygon(marker)).map((
        marker,
      ) {
        final lot = marker['cemetery_lot'] ?? {};
        final status = lot['status']?.toString() ?? '';
        final lotId = lot['lot_id'];
        final isSelected = _selectedLotId == lotId;

        return Marker(
          point: _markerToLatLng(marker),
          width: isSelected ? 64 : 44,
          height: isSelected ? 76 : 44,
          child: isSelected
              ? _SelectedLeafletPin(onTap: () => _selectMarker(marker))
              : _MapPin(
                  fillColor: lotStatusFillColor(status),
                  borderColor: lotStatusStrokeColor(status),
                  iconColor: lotStatusForegroundColor(status),
                  icon: _statusIcon(status),
                  selected: false,
                  onTap: () => _selectMarker(marker),
                ),
        );
      }),
    ];

    final selectedPoint = _selectedMarker == null
        ? null
        : _markerToLatLng(_selectedMarker!);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: selectedPoint ?? _routeStart,
        initialZoom: _initialZoom,
        minZoom: 14,
        maxZoom: 20,
        onPositionChanged: (position, hasGesture) {
          _currentZoom = position.zoom;
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.cemetery_app',
          maxZoom: 20,
        ),
        if (basePolygons.isNotEmpty) PolygonLayer(polygons: basePolygons),
        if (basePolylines.isNotEmpty) PolylineLayer(polylines: basePolylines),
        if (overlayPolygons.isNotEmpty) PolygonLayer(polygons: overlayPolygons),
        if (lotPolygons.isNotEmpty)
          GestureDetector(
            onTap: () {
              final hitValues = _lotPolygonHitNotifier.value?.hitValues;
              if (hitValues == null || hitValues.isEmpty) return;
              _selectMarkerByLotId(hitValues.last);
            },
            child: PolygonLayer<String>(
              polygons: lotPolygons,
              hitNotifier: _lotPolygonHitNotifier,
            ),
          ),
        if (overlayPolylines.isNotEmpty)
          PolylineLayer(polylines: overlayPolylines),
        if (routePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(points: routePoints, color: _C.primary, strokeWidth: 5),
            ],
          ),
        if (overlayPointMarkers.isNotEmpty)
          MarkerLayer(markers: overlayPointMarkers),
        MarkerLayer(markers: markers),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _visitorVisibleMapFeatures {
    return _mapFeatures.where(isPublicPreviewMapFeature).toList();
  }

  bool get _hasMappedEntrance =>
      _entranceXPercent != null && _entranceYPercent != null;

  LatLng? _entranceFromMapFeatures() {
    for (final feature in _mapFeatures) {
      final type = mapFeatureType(feature);
      if (type != 'entrance') continue;
      final points = wktPoints(feature['geometry_wkt']?.toString() ?? '');
      if (points.isNotEmpty) return points.first;
    }
    return null;
  }

  bool get _hasRouteStart =>
      _hasMappedEntrance || _entranceFromMapFeatures() != null;

  LatLng get _entranceLatLng {
    if (!_hasMappedEntrance) return _mapCenter;
    return _percentToLatLng(_entranceXPercent!, _entranceYPercent!);
  }

  LatLng get _routeStart {
    if (_hasMappedEntrance) return _entranceLatLng;
    return _entranceFromMapFeatures() ?? _mapCenter;
  }

  List<LatLng> _routeFromEntranceToLot(Map<String, dynamic> marker) {
    if (!_hasRouteStart) return [];
    final start = _routeStart;
    final end = _markerToLatLng(marker);

    final qgisRoute = shortestRouteThroughPathways(
      pathwayLines: mapFeaturePathwayLines(_mapFeatures),
      start: start,
      end: end,
    );
    if (qgisRoute.isNotEmpty) return qgisRoute;

    if (_pathNodes.isEmpty) return [start, end];

    final startNode = _nearestNodeTo(start);
    final endNode = _nearestNodeTo(end);
    if (startNode == null || endNode == null) return [start, end];

    final startId = _asNodeId(startNode['node_id']);
    final endId = _asNodeId(endNode['node_id']);
    if (startId == null || endId == null) return [start, end];

    final nodePath = _shortestNodePath(startId, endId);
    if (nodePath.isEmpty) {
      return [start, _nodeToLatLng(startNode), _nodeToLatLng(endNode), end];
    }

    return [
      start,
      ...nodePath.map((nodeId) => _nodeToLatLng(_nodeById(nodeId)!)),
      end,
    ];
  }

  List<int> _shortestNodePath(int startId, int endId) {
    if (startId == endId) return [startId];
    final graph = <int, List<({int nodeId, double distance})>>{};
    for (final edge in _pathEdges) {
      final from = _asNodeId(edge['from_node_id']);
      final to = _asNodeId(edge['to_node_id']);
      if (from == null || to == null) continue;
      final fromNode = _nodeById(from);
      final toNode = _nodeById(to);
      if (fromNode == null || toNode == null) continue;
      final distance = _coordinateDistanceMeters(
        _nodeToLatLng(fromNode),
        _nodeToLatLng(toNode),
      );
      graph.putIfAbsent(from, () => []).add((nodeId: to, distance: distance));
      graph.putIfAbsent(to, () => []).add((nodeId: from, distance: distance));
    }

    final distances = <int, double>{startId: 0};
    final previous = <int, int>{};
    final visited = <int>{};

    while (true) {
      int? current;
      double best = double.infinity;
      for (final entry in distances.entries) {
        if (!visited.contains(entry.key) && entry.value < best) {
          current = entry.key;
          best = entry.value;
        }
      }
      if (current == null || current == endId) break;
      visited.add(current);
      for (final neighbor in graph[current] ?? []) {
        final nextDistance = best + neighbor.distance;
        if (nextDistance < (distances[neighbor.nodeId] ?? double.infinity)) {
          distances[neighbor.nodeId] = nextDistance;
          previous[neighbor.nodeId] = current;
        }
      }
    }

    if (!distances.containsKey(endId)) return [];
    final path = <int>[endId];
    while (path.first != startId) {
      if (!previous.containsKey(path.first)) return [];
      path.insert(0, previous[path.first]!);
    }
    return path;
  }

  int? _asNodeId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic>? _nodeById(dynamic id) {
    final nodeId = _asNodeId(id);
    if (nodeId == null) return null;
    for (final node in _pathNodes) {
      if (_asNodeId(node['node_id']) == nodeId) return node;
    }
    return null;
  }

  Map<String, dynamic>? _nearestNodeTo(LatLng point) {
    if (_pathNodes.isEmpty) return null;
    Map<String, dynamic>? nearest;
    double nearestDistance = double.infinity;
    for (final node in _pathNodes) {
      final distance = _coordinateDistanceMeters(point, _nodeToLatLng(node));
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = node;
      }
    }
    return nearest;
  }

  LatLng _markerToLatLng(Map<String, dynamic> marker) {
    final xPercent = (marker['x_percent'] as num).toDouble();
    final yPercent = (marker['y_percent'] as num).toDouble();
    return _percentToLatLng(xPercent, yPercent);
  }

  dynamic _markerLotId(Map<String, dynamic> marker) {
    final lot = marker['cemetery_lot'];
    if (lot is Map) return lot['lot_id'];
    return marker['lot_id'];
  }

  bool _sameRecordId(dynamic left, dynamic right) {
    if (left == null || right == null) return false;
    return left.toString() == right.toString();
  }

  LatLng _nodeToLatLng(Map<String, dynamic> node) {
    return _percentToLatLng(_nodeXPercent(node), _nodeYPercent(node));
  }

  double _nodeXPercent(Map<String, dynamic> node) {
    return (node['x_percent'] as num).toDouble();
  }

  double _nodeYPercent(Map<String, dynamic> node) {
    return (node['y_percent'] as num).toDouble();
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _activeMarkerLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _activeMarkerLngSpan;
    return LatLng(
      _mapCenter.latitude + latOffset,
      _mapCenter.longitude + lngOffset,
    );
  }

  (double, double) _latLngToLocalMeters(LatLng point) {
    const earthRadiusMeters = 6371000.0;
    final centerLatRadians = _degreesToRadians(_mapCenter.latitude);
    final x =
        _degreesToRadians(point.longitude - _mapCenter.longitude) *
        earthRadiusMeters *
        cos(centerLatRadians);
    final y =
        _degreesToRadians(point.latitude - _mapCenter.latitude) *
        earthRadiusMeters;
    return (x, y);
  }

  double _coordinateDistanceMeters(LatLng a, LatLng b) {
    final (ax, ay) = _latLngToLocalMeters(a);
    final (bx, by) = _latLngToLocalMeters(b);
    final dx = bx - ax;
    final dy = by - ay;
    return sqrt(dx * dx + dy * dy);
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  Widget _buildEntranceMarker() {
    return Container(
      decoration: BoxDecoration(
        color: _C.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: _C.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.door_front_door_rounded, color: _C.white, size: 22),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: _C.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _C.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadMapData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(backgroundColor: _C.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child, required double borderRadius}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: _C.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _softIcon(IconData icon, Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _C.primaryFixedDim.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Color _statusColor(String? status) {
    return lotStatusStrokeColor(status);
  }

  IconData _statusIcon(String? status) {
    final normalizedStatus = status?.toLowerCase();
    if (normalizedStatus == 'occupied') return Icons.person_rounded;
    if (normalizedStatus == 'available') return Icons.nature_people_rounded;
    return Icons.star_rounded;
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor ?? color),
          ),
        ),
        const SizedBox(width: 11),
        Text(
          label,
          style: const TextStyle(
            color: _C.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.fillColor,
    required this.borderColor,
    required this.iconColor,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Color fillColor;
  final Color borderColor;
  final Color iconColor;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: selected ? 1.16 : 1,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: fillColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
      ),
    );
  }
}

class _SelectedLeafletPin extends StatelessWidget {
  const _SelectedLeafletPin({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 3,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _C.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 8,
            child: Transform.rotate(
              angle: -0.78,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _C.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                    bottomLeft: Radius.circular(4),
                  ),
                  border: Border.all(color: _C.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: 0.78,
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: _C.white,
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VisitorMapScreenWithDestination extends StatelessWidget {
  final int? destinationLotId;
  final String? destinationLotNumber;

  const VisitorMapScreenWithDestination({
    super.key,
    this.destinationLotId,
    this.destinationLotNumber,
  });

  @override
  Widget build(BuildContext context) {
    return VisitorMapScreen(
      initialLotId: destinationLotId,
      initialLotNumber: destinationLotNumber,
    );
  }
}
