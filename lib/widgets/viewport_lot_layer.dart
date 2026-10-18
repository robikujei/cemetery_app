import 'dart:ui' as ui;

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
    this.enableHitTesting = true,
    this.viewportPaddingFactor = 0.35,
  });

  final List<Map<String, dynamic>> markers;
  final LayerHitNotifier<String> hitNotifier;
  final Object? selectedLotId;
  final double detailZoom;

  /// Keep flutter_map's per-pointer polygon hit testing enabled for callers
  /// that use the layer notifier. Map screens can disable it and call
  /// [ViewportLotLayerState.lotIdAt] from `MapOptions.onTap` instead.
  final bool enableHitTesting;
  final double viewportPaddingFactor;

  @override
  ViewportLotLayerState createState() => ViewportLotLayerState();
}

class ViewportLotLayerState extends State<ViewportLotLayer> {
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
    // Realtime handlers can mutate a marker map in place. Compare the captured
    // geometry/status values even when the list object itself is reused.
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

  /// Returns the lot under a geographic point without asking flutter_map to
  /// hit-test every rendered polygon during map gestures.
  String? lotIdAt(LatLng point) {
    if (_snapshot.isEmpty) return null;
    final candidates = _index.query(LatLngBounds(point, point));
    String? hit;
    // Preserve PolygonLayer's source ordering: the last matching polygon in
    // the rendered order wins when lots overlap.
    for (final entry in candidates) {
      if (_containsPoint(entry.ring, point)) hit = entry.lot.id;
    }
    return hit;
  }

  bool _containsPoint(List<LatLng> ring, LatLng point) {
    var inside = false;
    final x = point.longitude;
    final y = point.latitude;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].longitude;
      final yi = ring[i].latitude;
      final xj = ring[j].longitude;
      final yj = ring[j].latitude;
      final crosses = (yi > y) != (yj > y);
      if (crosses && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
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
      // A small screen-space cache is enough to avoid rebuilding during a
      // normal drag while preventing the initial view from retaining the
      // entire cemetery's polygon set.
      _loadedBounds = paddedMapBounds(viewport, widget.viewportPaddingFactor);
      final visible = _index.query(_loadedBounds!);
      if (!listEquals(visible, _visible)) {
        _visible = visible;
        _layer = null;
      }
    }
    // Keep this exact widget while panning within the buffer. flutter_map clears
    // its projected geometry cache whenever PolygonLayer receives a new widget.
    if (!widget.enableHitTesting) {
      // Unlike PolygonLayer, this painter receives the camera directly, so it
      // must be refreshed for every camera update inside the viewport buffer.
      return CustomPaint(
        painter: _BatchedLotPainter(
          camera: camera,
          entries: _visible ?? const <_LotRing>[],
          selectedLotId: widget.selectedLotId,
          lowDetail: detail == 1,
        ),
        size: camera.size,
      );
    }
    return _layer ??= PolygonLayer<String>(
      drawInSingleWorld: true,
      polygonLabels: false,
      hitNotifier: widget.enableHitTesting ? widget.hitNotifier : null,
      polygons: [
        for (final entry in _visible ?? <_LotRing>[])
          ...lotPolygonsFromRings(
            [entry.ring],
            lotId: entry.lot.id,
            status: entry.lot.status,
            selectedLotId: widget.selectedLotId,
            includeHitValues: widget.enableHitTesting,
            lowDetail: detail == 1,
          ),
      ],
    );
  }
}

/// Draws visual-only lots in a handful of canvas operations. PolygonLayer's
/// default painter flushes once per translucent polygon, which is expensive
/// when a cemetery view contains thousands of adjacent lots.
class _BatchedLotPainter extends CustomPainter {
  _BatchedLotPainter({
    required this.camera,
    required this.entries,
    required this.selectedLotId,
    required this.lowDetail,
  });

  final MapCamera camera;
  final List<_LotRing> entries;
  final Object? selectedLotId;
  final bool lowDetail;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final groups = <_LotPaintKey, _LotPathGroup>{};
    final viewport = camera.visibleBounds;
    for (final entry in entries) {
      if (!entry.bounds.isOverlapping(viewport)) continue;
      final selected =
          selectedLotId != null && entry.lot.id == selectedLotId.toString();
      final status = entry.lot.status;
      final fill = lotStatusFillColor(status).withValues(
        alpha: _isAvailableStatusForPaint(status)
            ? (selected ? 0.90 : 0.72)
            : (selected ? 0.54 : 0.36),
      );
      final stroke = lotStatusStrokeColor(
        status,
      ).withValues(alpha: selected ? 0.96 : 0.78);
      final width = selected ? 2.5 : (lowDetail ? 0.35 : 1.1);
      final key = _LotPaintKey(fill, stroke, width);
      final group = groups.putIfAbsent(key, _LotPathGroup.new);
      final points = [
        for (final point in entry.ring) camera.latLngToScreenOffset(point),
      ];
      if (points.length >= 3) {
        group.fill.addPolygon(points, true);
        if (width > 0) group.border.addPolygon(points, true);
      }
    }

    for (final entry in groups.entries) {
      final key = entry.key;
      final group = entry.value;
      canvas.drawPath(
        group.fill,
        ui.Paint()
          ..style = ui.PaintingStyle.fill
          ..color = key.fill,
      );
      if (key.borderWidth > 0) {
        canvas.drawPath(
          group.border,
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = key.borderWidth
            ..color = key.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BatchedLotPainter oldDelegate) =>
      camera != oldDelegate.camera ||
      !identical(entries, oldDelegate.entries) ||
      selectedLotId?.toString() != oldDelegate.selectedLotId?.toString() ||
      lowDetail != oldDelegate.lowDetail;
}

class _LotPaintKey {
  const _LotPaintKey(this.fill, this.stroke, this.borderWidth);
  final Color fill;
  final Color stroke;
  final double borderWidth;

  @override
  bool operator ==(Object other) =>
      other is _LotPaintKey &&
      fill == other.fill &&
      stroke == other.stroke &&
      borderWidth == other.borderWidth;

  @override
  int get hashCode => Object.hash(fill, stroke, borderWidth);
}

class _LotPathGroup {
  final fill = ui.Path();
  final border = ui.Path();
}

bool _isAvailableStatusForPaint(String status) =>
    status.trim().toLowerCase() == 'available';

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
