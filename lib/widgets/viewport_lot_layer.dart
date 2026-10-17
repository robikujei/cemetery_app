import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/map_bounds_index.dart';
import '../utils/map_feature_geometry.dart';

/// Owns camera-dependent lot rendering so pans never rebuild the map screen.
class ViewportLotLayer extends StatefulWidget {
  const ViewportLotLayer({
    super.key,
    required this.markers,
    required this.hitNotifier,
    this.selectedLotId,
    this.detailZoom = 18.75,
  });

  final List<Map<String, dynamic>> markers;
  final LayerHitNotifier<String> hitNotifier;
  final Object? selectedLotId;
  final double detailZoom;

  @override
  State<ViewportLotLayer> createState() => _ViewportLotLayerState();
}

class _ViewportLotLayerState extends State<ViewportLotLayer> {
  late List<_LotSnapshot> _snapshot;
  late MapBoundsIndex<_LotRing> _index;
  LatLngBounds? _loadedBounds;
  double? _queryZoom;
  List<_LotRing>? _visible;
  int? _detail;
  Widget? _layer;

  @override
  void initState() {
    super.initState();
    _readSnapshot();
  }

  @override
  void didUpdateWidget(covariant ViewportLotLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Realtime handlers may replace items in the same list or update status in
    // the same lot map. Compare captured values, not just collection identity.
    if (_snapshot.length != widget.markers.length || !_matchesSnapshot()) {
      _readSnapshot();
    }
    if (widget.selectedLotId?.toString() !=
            oldWidget.selectedLotId?.toString() ||
        widget.hitNotifier != oldWidget.hitNotifier) {
      _layer = null;
    }
  }

  bool _matchesSnapshot() {
    for (var i = 0; i < _snapshot.length; i++) {
      if (!_snapshot[i].matches(widget.markers[i])) return false;
    }
    return true;
  }

  void _readSnapshot() {
    _snapshot = widget.markers.map(_LotSnapshot.new).toList();
    _index = MapBoundsIndex([
      for (final lot in _snapshot)
        for (final ring in geoJsonPolygonRings(lot.geometry))
          _LotRing(lot, ring),
    ], (entry) => entry.bounds);
    _loadedBounds = null;
    _visible = null;
    _layer = null;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final detail = camera.zoom < widget.detailZoom
        ? 0
        : camera.zoom < 20
        ? 1
        : 2;
    if (_detail != detail) {
      _detail = detail;
      _layer = null;
    }
    if (detail == 0) return const SizedBox.shrink();

    final viewport = camera.visibleBounds;
    if (_loadedBounds == null ||
        (camera.zoom - (_queryZoom ?? camera.zoom)).abs() > 0.5 ||
        !_loadedBounds!.containsBounds(viewport)) {
      _queryZoom = camera.zoom;
      _loadedBounds = paddedMapBounds(viewport, 0.35);
      final visible = _index.query(_loadedBounds!);
      if (!listEquals(visible, _visible)) {
        _visible = visible;
        _layer = null;
      }
    }
    // Keep this exact widget while panning within the buffer. flutter_map clears
    // its projected geometry cache whenever PolygonLayer receives a new widget.
    return _layer ??= PolygonLayer<String>(
      hitNotifier: widget.hitNotifier,
      polygons: [
        for (final entry in _visible ?? <_LotRing>[])
          ...lotPolygonsFromRings(
            [entry.ring],
            lotId: entry.lot.id,
            status: entry.lot.status,
            selectedLotId: widget.selectedLotId,
            includeHitValues: true,
            lowDetail: detail == 1,
          ),
      ],
    );
  }
}

class _LotSnapshot {
  _LotSnapshot(Map<String, dynamic> marker) {
    final lot = marker['cemetery_lot'];
    geometry = lot is Map ? lot['polygon_geo'] : null;
    id = lot is Map ? lot['lot_id']?.toString() : null;
    status = lot is Map
        ? lot['status']?.toString() ?? 'Available'
        : 'Available';
  }
  late final Object? geometry;
  late final String? id;
  late final String status;

  bool matches(Map<String, dynamic> marker) {
    final lot = marker['cemetery_lot'];
    final otherGeometry = lot is Map ? lot['polygon_geo'] : null;
    final otherId = lot is Map ? lot['lot_id']?.toString() : null;
    final otherStatus = lot is Map
        ? lot['status']?.toString() ?? 'Available'
        : 'Available';
    // Geometry values are immutable snapshots from Supabase; edits replace them.
    return identical(geometry, otherGeometry) &&
        id == otherId &&
        status == otherStatus;
  }
}

class _LotRing {
  _LotRing(this.lot, this.ring) : bounds = LatLngBounds.fromPoints(ring);
  final _LotSnapshot lot;
  final List<LatLng> ring;
  final LatLngBounds bounds;
}
