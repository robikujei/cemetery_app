import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/map_feature_geometry.dart';
import 'cemetery_analytics.dart';
import 'supabase_pagination_service.dart';

class AnalyticsData {
  /// Mapped lot footprint per block, excluding walkways and unmapped land.
  Map<String, double> mappedLotAreas() {
    final areas = <String, double>{};
    for (final lot in lots) {
      var area = 0.0;
      for (final ring in geoJsonPolygonRings(lot['polygon_geo'])) {
        if (ring.length < 3) continue;
        final origin = ring.first;
        final xScale =
            111195.0802335329 * math.cos(origin.latitude * math.pi / 180);
        var twiceArea = 0.0;
        for (var i = 0; i < ring.length; i++) {
          final a = ring[i], b = ring[(i + 1) % ring.length];
          twiceArea +=
              (a.longitude - origin.longitude) *
                  xScale *
                  (b.latitude - origin.latitude) *
                  111195.0802335329 -
              (b.longitude - origin.longitude) *
                  xScale *
                  (a.latitude - origin.latitude) *
                  111195.0802335329;
        }
        area += twiceArea.abs() / 2;
      }
      if (area.isFinite && area > 0) {
        areas[blockOf(lot)] = (areas[blockOf(lot)] ?? 0) + area;
      }
    }
    return areas;
  }

  final rows = <String, List<Map<String, dynamic>>>{};
  final errors = <String, String>{};
  DateTime? loadedAt;
  List<Map<String, dynamic>> get lots => rows['cemetery_lot'] ?? [];
  List<Map<String, dynamic>> get burials => rows['burial_record'] ?? [];
  List<Map<String, dynamic>> get sales => rows['lot_ownership'] ?? [];
  List<Map<String, dynamic>> get payments => rows['transaction_history'] ?? [];
  List<Map<String, dynamic>> get visitors => rows['visitor_log'] ?? [];
  List<Map<String, dynamic>> get features =>
      rows['cemetery_map_features'] ?? [];

  static Future<AnalyticsData> load(SupabaseClient client) async {
    final data = AnalyticsData();
    const sources = {
      'cemetery_lot': (
        'lot_id',
        'lot_id,lot_number,lot_label,block_number,status,price,x_coord,y_coord,qgis_feature_id,polygon_geo',
      ),
      'burial_record': (
        'burial_id',
        'burial_id,name_of_deceased,lot_id,birth_date,death_date,burial_date,interment_date',
      ),
      'lot_ownership': (
        'ownership_id',
        'ownership_id,lot_id,user_id,start_date,status,total_months,months_paid',
      ),
      'transaction_history': (
        'transaction_id',
        'transaction_id,ownership_id,amount,payment_date,notes',
      ),
      'visitor_log': (
        'log_id',
        'log_id,user_id,burial_id,time_in,time_out,method',
      ),
      'cemetery_map_features': (
        'feature_id',
        'feature_id,feature_type,feature_name,geometry_wkt,is_visible',
      ),
    };
    await Future.wait(
      sources.entries.map((source) async {
        try {
          data.rows[source.key] = await SupabasePaginationService.selectAll(
            supabase: client,
            table: source.key,
            columns: source.value.$2,
            orderColumn: source.value.$1,
          );
        } catch (e) {
          data.errors[source.key] = e.toString();
        }
      }),
    );
    data.loadedAt = DateTime.now();
    return data;
  }

  /// Manual percentage markers are excluded unless a geographic polygon exists.
  LatLng? position(Map<String, dynamic> lot) {
    final rings = geoJsonPolygonRings(lot['polygon_geo']);
    if (rings.isNotEmpty && rings.first.isNotEmpty) {
      final ring = rings.first;
      final vertices = ring.length > 1 && ring.first == ring.last
          ? ring.take(ring.length - 1).toList()
          : ring;
      final lat =
          vertices.fold<double>(0, (s, p) => s + p.latitude) / vertices.length;
      final lng =
          vertices.fold<double>(0, (s, p) => s + p.longitude) / vertices.length;
      if (lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180) {
        return LatLng(lat, lng);
      }
    }
    if (lot['qgis_feature_id'] == null) return null;
    final lat = double.tryParse(lot['y_coord']?.toString() ?? '');
    final lng = double.tryParse(lot['x_coord']?.toString() ?? '');
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        (lat == 0 && lng == 0)) {
      return null;
    }
    return LatLng(lat, lng);
  }

  SpatialResult spatial({
    DateTime? start,
    DateTime? end,
    double epsilon = 15,
    int minPoints = 5,
  }) {
    final byId = {for (final lot in lots) lot['lot_id'].toString(): lot};
    final points = <BurialPoint>[];
    var excluded = 0;
    for (final burial in burials) {
      if (!inPeriod(
        burial['interment_date'] ?? burial['burial_date'],
        start,
        end,
      )) {
        continue;
      }
      final lot = byId[burial['lot_id'].toString()];
      final location = lot == null ? null : position(lot);
      if (location == null) {
        excluded++;
        continue;
      }
      points.add(
        BurialPoint(
          burial['burial_id'].toString(),
          lot!['lot_id'].toString(),
          blockOf(lot),
          location.latitude,
          location.longitude,
        ),
      );
    }
    return dbscan(
      points,
      epsilon: epsilon,
      minPoints: minPoints,
      excluded: excluded,
    );
  }
}
