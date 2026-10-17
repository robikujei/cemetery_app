import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:cemetery_app/widgets/cached_map_features.dart';
import 'package:cemetery_app/utils/map_feature_geometry.dart';

void main() {
  test(
    'camera rebuilds retain layers; reload and visibility changes refresh',
    () {
      final cache = CachedMapFeatures();
      final source = <Map<String, dynamic>>[
        {'feature_type': 'pathway', 'geometry_wkt': 'LINESTRING (0 0, 1 1)'},
      ];
      final admin = cache.resolve(source, publicPreview: false);
      expect(cache.resolve(source, publicPreview: false), same(admin));
      expect(
        ((admin.overlayPolylines as IgnorePointer).child as PolylineLayer)
            .polylines,
        hasLength(1),
      );
      final visitor = cache.resolve(source, publicPreview: true);
      expect(
        ((visitor.overlayPolylines as IgnorePointer).child as PolylineLayer)
            .polylines,
        isEmpty,
      );
      final reloaded = cache.resolve(List.of(source), publicPreview: true);
      expect(reloaded, isNot(same(visitor)));
    },
  );

  test(
    'cached extents retain intersecting lots and follow replaced geometry',
    () {
      Map<String, dynamic> polygon(double x) => {
        'type': 'Polygon',
        'coordinates': [
          [
            [x, 0],
            [x + 2, 0],
            [x + 2, 2],
            [x, 2],
            [x, 0],
          ],
        ],
      };
      final lot = <String, dynamic>{'polygon_geo': polygon(0)};
      final marker = <String, dynamic>{'cemetery_lot': lot};
      final bounds = LatLngBounds(const LatLng(0.5, 0.5), const LatLng(1, 1));
      for (var i = 0; i < 2; i++) {
        expect(lotMarkersWithinBounds([marker], bounds), [marker]);
      }
      lot['polygon_geo'] = polygon(10);
      expect(lotMarkersWithinBounds([marker], bounds), isEmpty);
    },
  );
}
