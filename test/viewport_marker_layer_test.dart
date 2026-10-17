import 'package:cemetery_app/widgets/viewport_marker_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets(
    'point pins are buffered, tappable and refreshed after moving or editing',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      var taps = 0;
      final markers = [
        for (var i = 0; i < 20; i++)
          Marker(
            point: LatLng(10, 123 + i * 0.001),
            width: 60,
            height: 80,
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(color: Colors.green),
            ),
          ),
      ];
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
                children: [ViewportMarkerLayer(markers: markers)],
              );
            },
          ),
        ),
      );
      await tester.pump();
      MarkerLayer layer() => tester.widget(find.byType(MarkerLayer));
      final initial = layer();
      expect(initial.markers, contains(markers.first));
      expect(initial.markers.length, lessThan(markers.length));
      await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
      await tester.pump(const Duration(milliseconds: 350));
      expect(taps, 1);
      controller.move(const LatLng(10, 123.00001), 19);
      await tester.pump();
      expect(layer(), same(initial));
      controller.move(const LatLng(10, 123.01), 20);
      controller.rotate(45);
      await tester.pump();
      expect(layer().markers, contains(markers[10]));
      final removed = markers[10];
      refresh(() => markers.removeAt(10));
      await tester.pump();
      expect(layer().markers, isNot(contains(removed)));
      controller.move(const LatLng(10, 123), 3);
      await tester.pump();
      expect(layer().markers, hasLength(markers.length));
    },
  );
}
