import 'package:cemetery_app/utils/map_feature_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> lotGeometry() => {
  'type': 'Polygon',
  'coordinates': [
    [
      [123.0000, 10.0000],
      [123.0001, 10.0000],
      [123.0001, 10.0001],
      [123.0000, 10.0001],
      [123.0000, 10.0000],
    ],
  ],
};

void main() {
  test('lot polygon layer renders lot footprints only', () {
    final polygons = lotPolygonsFromLots([
      {'lot_id': 7, 'status': 'Available', 'polygon_geo': lotGeometry()},
      {'lot_id': 8, 'status': 'Occupied', 'polygon_geo': null},
    ], lowDetail: true);

    expect(polygons, hasLength(1));
    expect(polygons.single.hitValue, isNull);
  });
}
