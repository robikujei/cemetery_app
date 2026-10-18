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

  /// Returns deterministic sample data for reviewing reports and analytics.
  ///
  /// This factory never touches Supabase. It is used only when the app is
  /// started with `--dart-define=MOCK_ANALYTICS=true`, so demo rows cannot be
  /// mistaken for production records or written back to the database.
  static AnalyticsData mock() {
    final data = AnalyticsData()..loadedAt = DateTime.now();
    const baseLat = 7.073;
    const baseLng = 125.612;
    const rowStep = 0.0001;
    const blockStep = 0.0012;
    const halfLat = 0.000037;
    const halfLng = 0.000037;
    final lots = <Map<String, dynamic>>[];

    for (var block = 1; block <= 3; block++) {
      for (var index = 1; index <= 16; index++) {
        final row = (index - 1) ~/ 4;
        final column = (index - 1) % 4;
        final lotId = (block - 1) * 16 + index;
        final lat = baseLat + (block - 1) * blockStep + row * rowStep;
        final lng = baseLng + column * rowStep;
        final status = row < 2
            ? 'Occupied'
            : index % 5 == 0
            ? 'Reserved'
            : 'Available';
        lots.add({
          'lot_id': lotId,
          'lot_number': index.toString().padLeft(3, '0'),
          'lot_label': 'B$block-$index',
          'block_number': block.toString(),
          'status': status,
          'price': 85000 + block * 5000 + index * 750,
          'x_coord': lng,
          'y_coord': lat,
          'qgis_feature_id': 'demo-lot-$lotId',
          'polygon_geo': _mockPolygon(lat, lng, halfLat, halfLng),
        });
      }
    }

    final burials = <Map<String, dynamic>>[];
    var burialId = 1;
    for (final lot in lots.where((lot) => lot['status'] == 'Occupied')) {
      final copies = (lot['lot_id'] as int) % 3 == 0 ? 2 : 1;
      for (var copy = 0; copy < copies; copy++) {
        final interment = DateTime(
          2026,
          1,
          5,
        ).add(Duration(days: burialId * 3 + copy));
        final death = interment.subtract(Duration(days: 30 + burialId));
        burials.add({
          'burial_id': burialId,
          'name_of_deceased': 'Demo Resident $burialId',
          'lot_id': lot['lot_id'],
          'birth_date':
              '1950-01-${(burialId % 27 + 1).toString().padLeft(2, '0')}',
          'death_date': death.toIso8601String().split('T').first,
          'burial_date': interment.toIso8601String().split('T').first,
          'interment_date': interment.toIso8601String().split('T').first,
        });
        burialId++;
      }
    }

    final sellable = lots.where((lot) => lot['status'] != 'Available').toList();
    final ownerships = <Map<String, dynamic>>[];
    final payments = <Map<String, dynamic>>[];
    for (var i = 0; i < sellable.length; i++) {
      final ownershipId = i + 1;
      final start = DateTime(2025, 8, 1).add(Duration(days: i * 7));
      final status = i % 9 == 0 ? 'Cancelled' : 'Active';
      ownerships.add({
        'ownership_id': ownershipId,
        'lot_id': sellable[i]['lot_id'],
        'user_id': 'demo-user-${(i % 8) + 1}',
        'start_date': start.toIso8601String().split('T').first,
        'status': status,
        'total_months': 120,
        'months_paid': status == 'Cancelled' ? 0 : 12 + i % 24,
      });
      if (status != 'Cancelled') {
        payments.add({
          'transaction_id': ownershipId,
          'ownership_id': ownershipId,
          'amount': 85000 + i * 1250,
          'payment_date': start
              .add(const Duration(days: 14))
              .toIso8601String()
              .split('T')
              .first,
          'notes': 'Demo payment',
        });
      }
    }

    final visitors = <Map<String, dynamic>>[];
    for (var i = 0; i < 120; i++) {
      final timeIn = DateTime(
        2026,
        6,
        1,
      ).add(Duration(days: i % 90, hours: 7 + i % 10, minutes: i % 4 * 15));
      visitors.add({
        'log_id': i + 1,
        'user_id': 'demo-visitor-${(i % 18) + 1}',
        'burial_id': burials[i % burials.length]['burial_id'],
        'time_in': timeIn.toIso8601String(),
        'time_out': timeIn.add(const Duration(minutes: 35)).toIso8601String(),
        'method': i % 3 == 0 ? 'QR scan' : 'Manual entry',
      });
    }

    data.rows.addAll({
      'cemetery_lot': lots,
      'burial_record': burials,
      'lot_ownership': ownerships,
      'transaction_history': payments,
      'visitor_log': visitors,
      // The hotspot report intentionally renders lots only. Keeping this
      // source empty also demonstrates that unrelated map features are not
      // required for the report to work.
      'cemetery_map_features': <Map<String, dynamic>>[],
    });
    return data;
  }

  static Map<String, dynamic> _mockPolygon(
    double lat,
    double lng,
    double halfLat,
    double halfLng,
  ) => {
    'type': 'Polygon',
    'coordinates': [
      [
        [lng - halfLng, lat - halfLat],
        [lng + halfLng, lat - halfLat],
        [lng + halfLng, lat + halfLat],
        [lng - halfLng, lat + halfLat],
        [lng - halfLng, lat - halfLat],
      ],
    ],
  };

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
