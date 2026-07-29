import 'dart:convert';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

final HashMap<Object, List<List<LatLng>>> _lotGeometryCache =
    HashMap<Object, List<List<LatLng>>>.identity();
const int _lotGeometryCacheLimit = 10000;

String mapFeatureType(Map<String, dynamic> feature) {
  final normalized =
      (feature['feature_type']?.toString().trim().toLowerCase() ?? '')
          .replaceAll(RegExp(r'[\s-]+'), '_');
  return normalized == 'maplayer' ? 'map_layer' : normalized;
}

bool isMapLayerFeature(Map<String, dynamic> feature) {
  return mapFeatureType(feature) == 'map_layer';
}

bool isPublicPreviewMapFeature(Map<String, dynamic> feature) {
  const visiblePreviewTypes = {'map_layer', 'boundary', 'block', 'entrance'};
  const hiddenPreviewTypes = {
    'pathway',
    'path_node',
    'path_nodes',
    'pathway_node',
    'pathway_nodes',
  };

  final type = mapFeatureType(feature);
  return visiblePreviewTypes.contains(type) &&
      !hiddenPreviewTypes.contains(type);
}

Widget minimalistEntranceMarker({Color color = const Color(0xFF335538)}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.94),
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 1.25),
    ),
    child: Center(
      child: Icon(Icons.sensor_door_outlined, color: color, size: 15),
    ),
  );
}

List<Polygon> mapFeaturePolygons(List<Map<String, dynamic>> features) {
  final polygons = <Polygon>[];
  for (final feature in features) {
    final rings = wktPolygonRings(feature['geometry_wkt']?.toString() ?? '');
    if (rings.isEmpty) continue;

    final type = _featureType(feature);
    final stroke = _featureStrokeColor(feature, type);
    final fill = _featureFillColor(feature, type, stroke);
    final strokeWidth = _featureStrokeWidth(feature, type);

    for (final ring in rings) {
      if (ring.length < 3) continue;
      polygons.add(
        Polygon(
          points: ring,
          color: fill,
          borderColor: stroke,
          borderStrokeWidth: strokeWidth,
        ),
      );
    }
  }
  return polygons;
}

List<Polyline> mapFeaturePolylines(List<Map<String, dynamic>> features) {
  final polylines = <Polyline>[];
  for (final feature in features) {
    final lines = wktLineStrings(feature['geometry_wkt']?.toString() ?? '');
    if (lines.isEmpty) continue;

    final type = _featureType(feature);
    final stroke = _featureStrokeColor(feature, type);
    final strokeWidth = _featureStrokeWidth(feature, type);

    for (final line in lines) {
      if (line.length < 2) continue;
      polylines.add(
        Polyline(points: line, color: stroke, strokeWidth: strokeWidth),
      );
    }
  }
  return polylines;
}

List<List<LatLng>> mapFeaturePathwayLines(List<Map<String, dynamic>> features) {
  return features
      .where((feature) => _featureType(feature) == 'pathway')
      .expand(
        (feature) => wktLineStrings(feature['geometry_wkt']?.toString() ?? ''),
      )
      .where((line) => line.length >= 2)
      .toList();
}

List<LatLng> shortestRouteThroughPathways({
  required List<List<LatLng>> pathwayLines,
  required LatLng start,
  required LatLng end,
  int connectorCandidates = 4,
  double snapToleranceMeters = 0.85,
}) {
  if (pathwayLines.isEmpty) return [];

  final points = <LatLng>[];
  final edges = <List<_RouteEdge>>[];
  final indexByKey = <String, int>{};

  int addNetworkPoint(LatLng point) {
    final key = _routePointKey(point);
    final existing = indexByKey[key];
    if (existing != null) return existing;
    final index = points.length;
    indexByKey[key] = index;
    points.add(point);
    edges.add([]);
    return index;
  }

  int addLoosePoint(LatLng point) {
    final index = points.length;
    points.add(point);
    edges.add([]);
    return index;
  }

  void connect(int from, int to) {
    if (from == to) return;
    final distance = _routeDistanceMeters(points[from], points[to]);
    if (distance <= 0) return;
    edges[from].add(_RouteEdge(to, distance));
    edges[to].add(_RouteEdge(from, distance));
  }

  for (final line in pathwayLines) {
    int? previousIndex;
    for (final point in line) {
      final index = addNetworkPoint(point);
      if (previousIndex != null) connect(previousIndex, index);
      previousIndex = index;
    }
  }

  final networkNodeCount = points.length;
  if (networkNodeCount == 0) return [];

  for (var i = 0; i < networkNodeCount; i++) {
    for (var j = i + 1; j < networkNodeCount; j++) {
      if (_routeDistanceMeters(points[i], points[j]) <= snapToleranceMeters) {
        connect(i, j);
      }
    }
  }

  final startIndex = addLoosePoint(start);
  final endIndex = addLoosePoint(end);

  void connectToNearestNetworkNodes(int index, LatLng point) {
    final nearest = <({int index, double distance})>[];
    for (var i = 0; i < networkNodeCount; i++) {
      nearest.add((index: i, distance: _routeDistanceMeters(point, points[i])));
    }
    nearest.sort((a, b) => a.distance.compareTo(b.distance));
    for (final candidate in nearest.take(connectorCandidates)) {
      connect(index, candidate.index);
    }
  }

  connectToNearestNetworkNodes(startIndex, start);
  connectToNearestNetworkNodes(endIndex, end);

  final pathIndexes = _shortestRouteIndexes(
    edges: edges,
    startIndex: startIndex,
    endIndex: endIndex,
  );
  if (pathIndexes.isEmpty) return [];
  return pathIndexes.map((index) => points[index]).toList();
}

List<Marker> mapFeaturePointMarkers(List<Map<String, dynamic>> features) {
  final markers = <Marker>[];
  for (final feature in features) {
    final points = wktPoints(feature['geometry_wkt']?.toString() ?? '');
    if (points.isEmpty) continue;

    final type = _featureType(feature);
    final stroke = _featureStrokeColor(feature, type);
    final icon = type == 'entrance'
        ? Icons.login_rounded
        : Icons.place_outlined;

    for (final point in points) {
      markers.add(
        Marker(
          point: point,
          width: 34,
          height: 34,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: stroke, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: stroke, size: 18),
            ),
          ),
        ),
      );
    }
  }
  return markers;
}

List<Polygon<String>> lotPolygonsFromMarkers(
  List<Map<String, dynamic>> markers, {
  dynamic selectedLotId,
  bool includeHitValues = false,
  bool lowDetail = false,
}) {
  final polygons = <Polygon<String>>[];
  for (final marker in markers) {
    final lot = marker['cemetery_lot'];
    if (lot is! Map) continue;

    final rings = geoJsonPolygonRings(lot['polygon_geo']);
    if (rings.isEmpty) continue;

    final lotId = lot['lot_id'];
    final selected =
        selectedLotId != null && lotId?.toString() == selectedLotId.toString();
    final status = lot['status']?.toString() ?? 'Available';
    final stroke = lotStatusStrokeColor(status);
    final fill = lotStatusFillColor(status).withValues(
      alpha: _isAvailableStatus(status)
          ? (selected ? 0.90 : 0.72)
          : (selected ? 0.54 : 0.36),
    );
    final hitValue = includeHitValues ? lotId?.toString() : null;

    for (final ring in rings) {
      if (ring.length < 3) continue;
      polygons.add(
        Polygon<String>(
          points: ring,
          color: fill,
          borderColor: stroke.withValues(alpha: selected ? 0.96 : 0.78),
          borderStrokeWidth: selected ? 2.5 : (lowDetail ? 0.35 : 1.1),
          hitValue: hitValue,
        ),
      );
    }
  }
  return polygons;
}

List<Map<String, dynamic>> lotMarkersWithinBounds(
  List<Map<String, dynamic>> markers,
  LatLngBounds bounds, {
  double paddingFactor = 0.08,
}) {
  final latPadding = (bounds.north - bounds.south) * paddingFactor;
  final lngPadding = (bounds.east - bounds.west) * paddingFactor;
  final north = bounds.north + latPadding;
  final south = bounds.south - latPadding;
  final east = bounds.east + lngPadding;
  final west = bounds.west - lngPadding;

  return markers.where((marker) {
    final lot = marker['cemetery_lot'];
    if (lot is! Map) return false;
    final rings = geoJsonPolygonRings(lot['polygon_geo']);
    for (final ring in rings) {
      if (ring.isEmpty) continue;
      var ringNorth = ring.first.latitude;
      var ringSouth = ring.first.latitude;
      var ringEast = ring.first.longitude;
      var ringWest = ring.first.longitude;
      for (final point in ring.skip(1)) {
        ringNorth = max(ringNorth, point.latitude);
        ringSouth = min(ringSouth, point.latitude);
        ringEast = max(ringEast, point.longitude);
        ringWest = min(ringWest, point.longitude);
      }
      if (ringSouth <= north &&
          ringNorth >= south &&
          ringWest <= east &&
          ringEast >= west) {
        return true;
      }
    }
    return false;
  }).toList();
}

bool markerHasLotPolygon(Map<String, dynamic> marker) {
  final lot = marker['cemetery_lot'];
  return lot is Map && geoJsonPolygonRings(lot['polygon_geo']).isNotEmpty;
}

List<List<LatLng>> geoJsonPolygonRings(Object? geometry) {
  if (geometry == null) return [];
  final cached = _lotGeometryCache[geometry];
  if (cached != null) return cached;

  final value = _decodeGeometry(geometry);
  if (value is! Map) return _cacheLotGeometry(geometry, const []);

  final type = value['type']?.toString();
  final coordinates = value['coordinates'];
  if (type == 'Polygon') {
    final ring = _geoJsonRing(
      coordinates is List && coordinates.isNotEmpty ? coordinates.first : null,
    );
    return _cacheLotGeometry(geometry, ring.length < 3 ? const [] : [ring]);
  }

  if (type == 'MultiPolygon' && coordinates is List) {
    final rings = <List<LatLng>>[];
    for (final polygon in coordinates) {
      if (polygon is! List || polygon.isEmpty) continue;
      final ring = _geoJsonRing(polygon.first);
      if (ring.length >= 3) rings.add(ring);
    }
    return _cacheLotGeometry(geometry, rings);
  }

  return _cacheLotGeometry(geometry, const []);
}

List<List<LatLng>> _cacheLotGeometry(
  Object geometry,
  List<List<LatLng>> rings,
) {
  if (_lotGeometryCache.length >= _lotGeometryCacheLimit) {
    _lotGeometryCache.clear();
  }
  _lotGeometryCache[geometry] = rings;
  return rings;
}

List<List<LatLng>> wktPolygonRings(String wkt) {
  final normalized = wkt.trim();
  final type = _wktType(normalized);
  final body = _outerBody(normalized);
  if (body.isEmpty) return [];

  if (type == 'POLYGON') {
    final rings = _parenthesizedGroups(body);
    if (rings.isEmpty) return [_parseCoordinateList(body)];
    return [_parseCoordinateList(rings.first)];
  }

  if (type == 'MULTIPOLYGON') {
    final polygons = <List<LatLng>>[];
    for (final polygonBody in _parenthesizedGroups(body)) {
      final rings = _parenthesizedGroups(polygonBody);
      if (rings.isEmpty) continue;
      polygons.add(_parseCoordinateList(rings.first));
    }
    return polygons;
  }

  return [];
}

List<List<LatLng>> wktLineStrings(String wkt) {
  final normalized = wkt.trim();
  final type = _wktType(normalized);
  final body = _outerBody(normalized);
  if (body.isEmpty) return [];

  if (type == 'LINESTRING') return [_parseCoordinateList(body)];
  if (type == 'MULTILINESTRING') {
    return _parenthesizedGroups(body).map(_parseCoordinateList).toList();
  }
  return [];
}

List<LatLng> wktPoints(String wkt) {
  final normalized = wkt.trim();
  final type = _wktType(normalized);
  final body = _outerBody(normalized);
  if (body.isEmpty) return [];

  if (type == 'POINT') {
    final point = _parseCoordinate(body);
    return point == null ? [] : [point];
  }

  if (type == 'MULTIPOINT') {
    final groups = _parenthesizedGroups(body);
    if (groups.isNotEmpty) {
      return groups.map(_parseCoordinate).whereType<LatLng>().toList();
    }
    return body.split(',').map(_parseCoordinate).whereType<LatLng>().toList();
  }

  return [];
}

String _featureType(Map<String, dynamic> feature) {
  return mapFeatureType(feature);
}

Color _featureStrokeColor(Map<String, dynamic> feature, String type) {
  final fallback = switch (type) {
    'map_layer' => const Color(0xFF26342B),
    'boundary' => const Color(0xFF244B2C),
    'block' => const Color(0xFF3F7C52),
    'pathway' => const Color(0xFF7B6856),
    'entrance' => const Color(0xFFA64DB3),
    _ => const Color(0xFF47626F),
  };
  return _colorFromHex(feature['stroke_color'], fallback);
}

const lotStatusAvailableFill = Color(0xFFFFFFFF);
const lotStatusAvailableStroke = Color(0xFF7C8A7D);
const lotStatusReservedFill = Color(0xFFFFD54F);
const lotStatusReservedStroke = Color(0xFF9B6A00);
const lotStatusOccupiedFill = Color(0xFF4D9A63);
const lotStatusOccupiedStroke = Color(0xFF2F6F43);
const lotStatusUnknownFill = Color(0xFFEAE8E5);
const lotStatusUnknownStroke = Color(0xFF727971);

Color lotStatusFillColor(String? status) {
  return switch (status?.trim().toLowerCase()) {
    'occupied' => lotStatusOccupiedFill,
    'reserved' => lotStatusReservedFill,
    'available' => lotStatusAvailableFill,
    _ => lotStatusUnknownFill,
  };
}

Color lotStatusStrokeColor(String? status) {
  return switch (status?.trim().toLowerCase()) {
    'occupied' => lotStatusOccupiedStroke,
    'reserved' => lotStatusReservedStroke,
    'available' => lotStatusAvailableStroke,
    _ => lotStatusUnknownStroke,
  };
}

Color lotStatusForegroundColor(String? status) {
  return switch (status?.trim().toLowerCase()) {
    'reserved' => const Color(0xFF3F2F00),
    'available' => lotStatusAvailableStroke,
    'occupied' => Colors.white,
    _ => const Color(0xFF424841),
  };
}

bool _isAvailableStatus(String? status) {
  return status?.trim().toLowerCase() == 'available';
}

Color _featureFillColor(
  Map<String, dynamic> feature,
  String type,
  Color stroke,
) {
  final fallback = switch (type) {
    'map_layer' => Colors.transparent,
    'boundary' => stroke.withValues(alpha: 0.04),
    'block' => stroke.withValues(alpha: 0.12),
    _ => Colors.transparent,
  };
  return _colorFromHex(feature['fill_color'], fallback);
}

double _featureStrokeWidth(Map<String, dynamic> feature, String type) {
  final value = feature['stroke_width'];
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed != null) return parsed;

  return switch (type) {
    'map_layer' => 2.0,
    'boundary' => 3.0,
    'pathway' => 4.0,
    'block' => 1.4,
    _ => 2.0,
  };
}

Color _colorFromHex(Object? value, Color fallback) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;

  final hex = raw.replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{8}$').hasMatch(hex)) {
    return fallback;
  }

  final argb = hex.length == 6 ? 'FF$hex' : hex;
  return Color(int.parse(argb, radix: 16));
}

String _wktType(String wkt) {
  final match = RegExp(
    r'^\s*([A-Za-z]+)(?:\s+(?:ZM|Z|M))?\s*\(',
  ).firstMatch(wkt);
  return match?.group(1)?.toUpperCase() ?? '';
}

String _outerBody(String wkt) {
  final start = wkt.indexOf('(');
  final end = wkt.lastIndexOf(')');
  if (start == -1 || end == -1 || end <= start) return '';
  return wkt.substring(start + 1, end).trim();
}

List<String> _parenthesizedGroups(String value) {
  final groups = <String>[];
  var depth = 0;
  int? start;

  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '(') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0 && start != null) {
        groups.add(value.substring(start, i).trim());
        start = null;
      }
    }
  }

  return groups;
}

List<LatLng> _parseCoordinateList(String value) {
  return value.split(',').map(_parseCoordinate).whereType<LatLng>().toList();
}

LatLng? _parseCoordinate(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;

  final lon = double.tryParse(parts[0]);
  final lat = double.tryParse(parts[1]);
  if (lat == null || lon == null) return null;
  return LatLng(lat, lon);
}

Object? _decodeGeometry(Object? geometry) {
  if (geometry is Map) return geometry;
  if (geometry is String && geometry.trim().isNotEmpty) {
    try {
      return jsonDecode(geometry);
    } catch (_) {
      return null;
    }
  }
  return null;
}

List<LatLng> _geoJsonRing(Object? ring) {
  if (ring is! List) return [];
  final points = ring.map(_geoJsonPoint).whereType<LatLng>().toList();
  if (points.length > 3) {
    final first = points.first;
    final last = points.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      points.removeLast();
    }
  }
  return points;
}

LatLng? _geoJsonPoint(Object? point) {
  if (point is! List || point.length < 2) return null;
  final lon = _asDouble(point[0]);
  final lat = _asDouble(point[1]);
  if (lat == null || lon == null) return null;
  return LatLng(lat, lon);
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _routePointKey(LatLng point) {
  final lat = (point.latitude * 1000000).round();
  final lng = (point.longitude * 1000000).round();
  return '$lat:$lng';
}

List<int> _shortestRouteIndexes({
  required List<List<_RouteEdge>> edges,
  required int startIndex,
  required int endIndex,
}) {
  if (startIndex == endIndex) return [startIndex];

  final distances = List<double>.filled(edges.length, double.infinity);
  final previous = List<int?>.filled(edges.length, null);
  final visited = List<bool>.filled(edges.length, false);
  distances[startIndex] = 0;

  while (true) {
    int? current;
    var best = double.infinity;
    for (var i = 0; i < distances.length; i++) {
      if (!visited[i] && distances[i] < best) {
        current = i;
        best = distances[i];
      }
    }

    if (current == null || current == endIndex) break;
    visited[current] = true;

    for (final edge in edges[current]) {
      final nextDistance = distances[current] + edge.distanceMeters;
      if (nextDistance < distances[edge.to]) {
        distances[edge.to] = nextDistance;
        previous[edge.to] = current;
      }
    }
  }

  if (distances[endIndex] == double.infinity) return [];

  final path = <int>[endIndex];
  while (path.first != startIndex) {
    final previousIndex = previous[path.first];
    if (previousIndex == null) return [];
    path.insert(0, previousIndex);
  }
  return path;
}

double _routeDistanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371000.0;
  final lat1 = _degreesToRadians(a.latitude);
  final lat2 = _degreesToRadians(b.latitude);
  final deltaLat = _degreesToRadians(b.latitude - a.latitude);
  final deltaLng = _degreesToRadians(b.longitude - a.longitude);
  final h =
      sin(deltaLat / 2) * sin(deltaLat / 2) +
      cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
  return earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(1 - h));
}

double _degreesToRadians(double degrees) => degrees * pi / 180;

class _RouteEdge {
  const _RouteEdge(this.to, this.distanceMeters);

  final int to;
  final double distanceMeters;
}
