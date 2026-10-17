import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../utils/map_feature_geometry.dart';

/// Retains layer widgets (and flutter_map's projected geometry) between camera
/// updates. Screens replace the feature snapshot when loading new map data.
class CachedMapFeatures {
  List<Map<String, dynamic>>? _source;
  bool? _publicPreview;
  late MapFeatureLayers _layers;

  MapFeatureLayers resolve(
    List<Map<String, dynamic>> source, {
    required bool publicPreview,
  }) {
    if (identical(source, _source) && publicPreview == _publicPreview) {
      return _layers;
    }
    _source = source;
    _publicPreview = publicPreview;
    final visible = publicPreview
        ? source.where(isPublicPreviewMapFeature)
        : source;
    final base = visible.where(isMapLayerFeature).toList();
    final overlay = visible.where((f) => !isMapLayerFeature(f)).toList();
    return _layers = MapFeatureLayers(
      basePolygons: PolygonLayer(polygons: mapFeaturePolygons(base)),
      basePolylines: PolylineLayer(polylines: mapFeaturePolylines(base)),
      overlayPolygons: PolygonLayer(polygons: mapFeaturePolygons(overlay)),
      overlayPolylines: PolylineLayer(polylines: mapFeaturePolylines(overlay)),
      points: MarkerLayer(
        markers: mapFeaturePointMarkers(
          overlay.where((f) => mapFeatureType(f) != 'entrance').toList(),
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
