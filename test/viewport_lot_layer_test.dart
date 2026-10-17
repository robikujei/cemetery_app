import 'package:cemetery_app/utils/map_feature_geometry.dart';
import 'package:cemetery_app/widgets/cached_map_features.dart';
import 'package:cemetery_app/widgets/viewport_lot_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> geometryAt(double longitude) => {
  'type': 'Polygon',
  'coordinates': [
    [
      [longitude - 0.00003, 9.99997],
      [longitude + 0.00003, 9.99997],
      [longitude + 0.00003, 10.00003],
      [longitude - 0.00003, 10.00003],
      [longitude - 0.00003, 9.99997],
    ],
  ],
};

Map<String, dynamic> lotAt(int id, double longitude) => {
  'cemetery_lot': {
    'lot_id': id,
    'status': 'Available',
    'polygon_geo': geometryAt(longitude),
  },
};

void main() {
  testWidgets(
    'pan reuses polygon layer without rebuilding screen; zoom changes detail',
    (tester) async {
      final controller = MapController();
      final LayerHitNotifier<String> hits = ValueNotifier(null);
      addTearDown(controller.dispose);
      addTearDown(hits.dispose);
      var screenBuilds = 0;
      final lots = [for (var i = 0; i <= 10; i++) lotAt(i, 123 + i * 0.001)];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screenBuilds++;
              return FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(10, 123),
                  initialZoom: 19,
                ),
                children: [ViewportLotLayer(markers: lots, hitNotifier: hits)],
              );
            },
          ),
        ),
      );
      await tester.pump();
      PolygonLayer<String> layer() =>
          tester.widget(find.byType(PolygonLayer<String>));
      final initial = layer();
      expect(initial.polygons.map((p) => p.hitValue), contains('0'));
      expect(initial.polygons.length, lessThan(lots.length));
      final baselineBuilds = screenBuilds;
      controller.move(const LatLng(10, 123.00001), 19);
      await tester.pump();
      expect(layer(), same(initial));
      // Continuous movement: no debounce or pause is required for newly visible lots.
      for (var i = 1; i <= 10; i++) {
        controller.move(LatLng(10, 123 + i * 0.001), 19);
        await tester.pump(const Duration(milliseconds: 16));
        expect(layer().polygons.map((p) => p.hitValue), contains('$i'));
      }
      expect(screenBuilds, baselineBuilds);
      controller.move(const LatLng(10, 123.01), 18.5);
      await tester.pump();
      expect(find.byType(PolygonLayer<String>), findsNothing);
      controller.move(const LatLng(10, 123.01), 20);
      controller.rotate(45);
      await tester.pump();
      expect(layer().polygons.map((p) => p.hitValue), contains('10'));
      expect(layer().polygons.first.borderStrokeWidth, 1.1);
      expect(screenBuilds, baselineBuilds);
    },
  );

  testWidgets(
    'in-place list updates, status, geometry, selection and deletion refresh',
    (tester) async {
      final controller = MapController();
      final LayerHitNotifier<String> hits = ValueNotifier(null);
      addTearDown(controller.dispose);
      addTearDown(hits.dispose);
      final lots = [lotAt(1, 123), lotAt(2, 123.005)];
      Object? selected;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return FlutterMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(10, 123),
                  initialZoom: 19,
                ),
                children: [
                  ViewportLotLayer(
                    markers: lots,
                    selectedLotId: selected,
                    hitNotifier: hits,
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      List<Polygon<String>> polygons() => tester
          .widget<PolygonLayer<String>>(find.byType(PolygonLayer<String>))
          .polygons;
      final available = polygons().single.color;
      refresh(() {
        lots.first['cemetery_lot']['status'] = 'Occupied';
        selected = 1;
      });
      await tester.pump();
      expect(polygons().single.color, isNot(available));
      expect(polygons().single.borderStrokeWidth, 2.5);
      refresh(() => lots[1] = lotAt(3, 123.0001));
      await tester.pump();
      expect(polygons().map((p) => p.hitValue), ['1', '3']);
      refresh(
        () => lots.first['cemetery_lot']['polygon_geo'] = geometryAt(123.01),
      );
      await tester.pump();
      expect(polygons().map((p) => p.hitValue), ['3']);
      refresh(() => lots.removeLast());
      await tester.pump();
      expect(polygons(), isEmpty);
    },
  );

  testWidgets(
    'decorative overlays pass lot taps through and edit mode ignores lots',
    (tester) async {
      final controller = MapController();
      final LayerHitNotifier<String> hits = ValueNotifier(null);
      addTearDown(controller.dispose);
      addTearDown(hits.dispose);
      final features = CachedMapFeatures().resolve([
        {
          'feature_type': 'pathway',
          'geometry_wkt': 'LINESTRING (122.999 10, 123.001 10)',
          'stroke_width': 20,
        },
      ], publicPreview: false);
      String? selected;
      var mapTaps = 0;
      var editing = false;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: const LatLng(10, 123),
                  initialZoom: 19,
                  onTap: (_, _) => mapTaps++,
                ),
                children: [
                  IgnorePointer(
                    ignoring: editing,
                    child: GestureDetector(
                      onTap: () => selected = hits.value?.hitValues.last,
                      child: ViewportLotLayer(
                        markers: [lotAt(1, 123), lotAt(2, 123)],
                        hitNotifier: hits,
                      ),
                    ),
                  ),
                  features.overlayPolylines,
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      expect(selected, '1'); // Existing .last hit ordering is preserved.
      refresh(() {
        editing = true;
        selected = null;
      });
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      expect(selected, isNull);
      expect(mapTaps, greaterThan(0));
    },
  );

  test('more than ten thousand live geometries retain parsed rings', () {
    final geometries = [
      for (var i = 0; i < 11000; i++) geometryAt(123 + i * 0.000001),
    ];
    final rings = geometries.map(geoJsonPolygonRings).toList();
    for (var i = 0; i < geometries.length; i++) {
      expect(geoJsonPolygonRings(geometries[i]), same(rings[i]));
    }
    expect(geoJsonPolygonRings('invalid JSON'), isEmpty);
    expect(geoJsonPolygonRings(42), isEmpty);
    expect(
      geoJsonPolygonRings({
        'type': 'MultiPolygon',
        'coordinates': [
          geometries.first['coordinates'],
          geometries.last['coordinates'],
        ],
      }),
      hasLength(2),
    );
  });
}
