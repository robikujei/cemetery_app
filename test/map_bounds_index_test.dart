import 'package:cemetery_app/utils/map_bounds_index.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test(
    'grid query matches full scan and preserves order across a large cemetery',
    () {
      final bounds = [
        for (var row = 0; row < 100; row++)
          for (var col = 0; col < 200; col++)
            LatLngBounds(
              LatLng(10 + row * 0.00003, 123 + col * 0.00003),
              LatLng(10.00002 + row * 0.00003, 123.00002 + col * 0.00003),
            ),
      ];
      final index = MapBoundsIndex(bounds, (b) => b);
      final queries = [
        for (var i = 0; i < 100; i++)
          LatLngBounds(
            LatLng(10.001, 123 + i * 0.00004),
            LatLng(10.0015, 123.0005 + i * 0.00004),
          ),
      ];
      bool intersects(LatLngBounds a, LatLngBounds b) =>
          a.south <= b.north &&
          a.north >= b.south &&
          a.west <= b.east &&
          a.east >= b.west;
      for (final query in queries) {
        expect(
          index.query(query),
          bounds.where((b) => intersects(b, query)).toList(),
        );
      }
      final scanWatch = Stopwatch()..start();
      for (final query in queries) {
        bounds.where((b) => intersects(b, query)).toList();
      }
      scanWatch.stop();
      final gridWatch = Stopwatch()..start();
      for (final query in queries) {
        index.query(query);
      }
      gridWatch.stop();
      // Diagnostic only: runtime speed is not a deterministic test assertion.
      // ignore: avoid_print
      print(
        '20,000 lots / 100 viewport queries: scan=${scanWatch.elapsedMicroseconds}us grid=${gridWatch.elapsedMicroseconds}us',
      );
    },
  );

  test(
    'large shapes, touching edges, empty queries and world bounds are bounded',
    () {
      final large = LatLngBounds(const LatLng(9, 122), const LatLng(11, 124));
      final small = LatLngBounds(
        const LatLng(10, 123),
        const LatLng(10.00001, 123.00001),
      );
      final index = MapBoundsIndex([large, small], (b) => b);
      expect(index.query(small), [large, small]);
      expect(
        index.query(
          LatLngBounds(
            const LatLng(10, 123.00001),
            const LatLng(10.00001, 123.00002),
          ),
        ),
        [large, small],
      );
      expect(
        index.query(
          LatLngBounds(const LatLng(0, 0), const LatLng(0.001, 0.001)),
        ),
        isEmpty,
      );
      expect(
        index.query(
          LatLngBounds(const LatLng(-90, -180), const LatLng(90, 180)),
        ),
        [large, small],
      );
      expect(
        paddedMapBounds(
          LatLngBounds(const LatLng(89, 179), const LatLng(90, 180)),
          0.35,
        ).north,
        90,
      );
    },
  );
}
