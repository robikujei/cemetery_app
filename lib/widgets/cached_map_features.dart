import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../utils/map_feature_geometry.dart';

/// Retains layer widgets (and flutter_map's projected geometry) between camera
/// updates. Screens replace the feature snapshot when loading new map data.
class CachedMapFeatures {
  List<Map<String, dynamic>>? _source;
  bool? _publicPreview;
  bool? _showPathNetwork;
  late MapFeatureLayers _layers;

  MapFeatureLayers resolve(
    List<Map<String, dynamic>> source, {
    required bool publicPreview,
    bool showPathNetwork = true,
  }) {
    if (identical(source, _source) &&
        publicPreview == _publicPreview &&
        showPathNetwork == _showPathNetwork) {
      return _layers;
    }
    _source = source;
    _publicPreview = publicPreview;
    _showPathNetwork = showPathNetwork;
    final previewVisible = publicPreview
        ? source.where(isPublicPreviewMapFeature)
        : source;
    final visible = showPathNetwork
        ? previewVisible
        : previewVisible.where((feature) => !isPathNetworkFeature(feature));
    final base = visible.where(isMapLayerFeature).toList();
    final overlay = visible.where((f) => !isMapLayerFeature(f)).toList();
    return _layers = MapFeatureLayers(
      basePolygons: IgnorePointer(
        child: PolygonLayer(polygons: mapFeaturePolygons(base)),
      ),
      basePolylines: IgnorePointer(
        child: PolylineLayer(polylines: mapFeaturePolylines(base)),
      ),
      overlayPolygons: IgnorePointer(
        child: PolygonLayer(polygons: mapFeaturePolygons(overlay)),
      ),
      overlayPolylines: IgnorePointer(
        child: PolylineLayer(polylines: mapFeaturePolylines(overlay)),
      ),
      points: IgnorePointer(
        child: MarkerLayer(
          markers: mapFeaturePointMarkers(
            overlay.where((f) => mapFeatureType(f) != 'entrance').toList(),
          ),
        ),
      ),
    );
  }
}

class MapFeatureLayers {
  const MapFeatureLayers({
    required this.basePolygons,
    required this.basePolylines,
    required this.overlayPolygons,
    required this.overlayPolylines,
    required this.points,
  });

  final Widget basePolygons;
  final Widget basePolylines;
  final Widget overlayPolygons;
  final Widget overlayPolylines;
  final Widget points;
}
