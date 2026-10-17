import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../utils/map_bounds_index.dart';

/// Limits per-frame marker projection to the visible area plus a pan buffer.
class ViewportMarkerLayer extends StatefulWidget {
  const ViewportMarkerLayer({super.key, required this.markers});
  final List<Marker> markers;

  @override
  State<ViewportMarkerLayer> createState() => _ViewportMarkerLayerState();
}

class _ViewportMarkerLayerState extends State<ViewportMarkerLayer> {
  late MapBoundsIndex<Marker> _index;
  late List<Marker> _snapshot;
  double _maxExtent = 0;
  double? _queryZoom;
  LatLngBounds? _loadedBounds;
  List<Marker>? _visible;
  Widget? _layer;

  @override
  void initState() {
    super.initState();
    _readSnapshot();
  }

  @override
  void didUpdateWidget(covariant ViewportMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.markers, _snapshot)) _readSnapshot();
  }

  void _readSnapshot() {
    _snapshot = List.of(widget.markers);
    _index = MapBoundsIndex(_snapshot, (m) => LatLngBounds(m.point, m.point));
    _maxExtent = _snapshot.fold(
      0.0,
      (extent, m) => math.max(extent, math.max(m.width, m.height)),
    );
    _loadedBounds = null;
    _layer = null;
    _visible = null;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // Include pins whose anchor is just off-screen but whose label/icon is
    // visible. Rotated bounds already enclose the rotated viewport.
    final viewport = paddedMapBounds(
      camera.visibleBounds,
      _maxExtent /
          math.max(1.0, math.min(camera.size.width, camera.size.height)),
    );
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
    return _layer ??= MarkerLayer(markers: _visible ?? const []);
  }
}
