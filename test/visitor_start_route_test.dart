import 'dart:async';
import 'dart:convert';

import 'package:cemetery_app/screens/visitor/visitor_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gps_tracker_test.dart' show FakeGps;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGps gps;
  late GeolocatorPlatform previousGps;
  var mappedPath = true;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3ioAAAAASUVORK5CYII=',
  );
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
  });
  setUp(() async {
    mappedPath = true;
    previousGps = GeolocatorPlatform.instance;
    gps = FakeGps();
    GeolocatorPlatform.instance = gps;
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        final data = switch (table) {
          'cemetery_map' => [
            {
              'center_lat': 10.0,
              'center_lng': 123.0,
              'lat_span': 0.0036,
              'lng_span': 0.0046,
              'entrance_x_percent': 40,
              'entrance_y_percent': 50,
            },
          ],
          'cemetery_map_features' =>
            mappedPath
                ? [
                    {
                      'feature_id': 1,
                      'feature_type': 'pathway',
                      'geometry_wkt':
                          'LINESTRING (122.99954 10, 123 10, 123.00046 10)',
                      'is_visible': true,
                      'sort_order': 0,
                    },
                  ]
                : [],
          'lot_markers' => [
            {
              'marker_id': 1,
              'lot_id': 1,
              'x_percent': 60,
              'y_percent': 50,
              'cemetery_lot': {
                'lot_id': 1,
                'lot_number': '001',
                'block_number': '36',
                'status': 'Occupied',
              },
            },
          ],
          _ => [],
        };
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDown(() async {
    await Supabase.instance.dispose();
    GeolocatorPlatform.instance = previousGps;
    await gps.fixes.close();
  });

  Future<void> withMap(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: VisitorMapScreen(initialLotId: 1)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Start Route'), findsWidgets);
        try {
          await body();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
      () => MockClient(
        (request) async => http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
          request: request,
        ),
      ),
    );
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Start Route').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Stop'), findsOneWidget);
  }

  List<LatLng> route(WidgetTester tester) => tester
      .widgetList<PolylineLayer>(find.byType(PolylineLayer))
      .expand((layer) => layer.polylines)
      .where((line) => line.strokeWidth == 5)
      .single
      .points;

  Position fix({
    double lat = 10,
    double lng = 123,
    double accuracy = 8,
    bool stale = false,
  }) => Position(
    latitude: lat,
    longitude: lng,
    accuracy: accuracy,
    timestamp: DateTime.now().subtract(Duration(minutes: stale ? 2 : 0)),
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  testWidgets(
    'Start Route requests GPS, updates the route origin, and Stop cancels tracking',
    (tester) async {
      await withMap(tester, () async {
        expect(gps.streams, 0);
        await start(tester);
        expect(gps.streams, 1);
        expect(route(tester).first, const LatLng(10, 122.99954));
        expect(find.textContaining('From the entrance'), findsOneWidget);
        gps.fixes.add(fix());
        await tester.pumpAndSettle();
        expect(route(tester).first, const LatLng(10, 123));
        expect(find.textContaining('From your location'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
        await tester.pumpAndSettle();
        expect(gps.fixes.hasListener, isFalse);
        expect(find.widgetWithText(FilledButton, 'Stop'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets('denied GPS retains entrance preview and can be retried', (
    tester,
  ) async {
    gps.permission = LocationPermission.deniedForever;
    await withMap(tester, () async {
      await start(tester);
      expect(gps.streams, 0);
      expect(find.textContaining('Location access denied'), findsWidgets);
      expect(route(tester).first, const LatLng(10, 122.99954));
      gps.permission = LocationPermission.whileInUse;
      await tester.tap(find.byTooltip('Start GPS tracking'));
      await tester.pumpAndSettle();
      gps.fixes.add(fix());
      await tester.pumpAndSettle();
      expect(gps.streams, 1);
      expect(route(tester).first, const LatLng(10, 123));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('outside, stale and inaccurate fixes retain the cemetery route', (
    tester,
  ) async {
    await withMap(tester, () async {
      await start(tester);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final cameraCenter = map.mapController!.camera.center;
      gps.fixes.add(fix(lat: 11, lng: 124));
      await tester.pumpAndSettle();
      expect(find.textContaining('Go to the cemetery'), findsOneWidget);
      expect(map.mapController!.camera.center, cameraCenter);
      expect(route(tester).first, const LatLng(10, 122.99954));
      gps.fixes.add(fix(accuracy: 100));
      await tester.pumpAndSettle();
      expect(find.textContaining('more accurate GPS'), findsOneWidget);
      expect(route(tester).first, const LatLng(10, 122.99954));
      // Stop/restart clears the timestamp guard before sending an old first fix.
      await tester.tap(find.byTooltip('Stop GPS tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Start GPS tracking'));
      await tester.pumpAndSettle();
      gps.fixes.add(fix(stale: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPS signal lost'), findsOneWidget);
      expect(route(tester).first, const LatLng(10, 122.99954));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'Stop during permission prompt prevents a late navigation start',
    (tester) async {
      gps.pendingPermission = Completer<LocationPermission>();
      await withMap(tester, () async {
        await start(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
        await tester.pumpAndSettle();
        gps.pendingPermission!.complete(LocationPermission.whileInUse);
        await tester.pumpAndSettle();
        expect(gps.streams, 0);
        expect(find.widgetWithText(FilledButton, 'Stop'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'missing paths show an explicit message without inventing a route',
    (tester) async {
      mappedPath = false;
      await withMap(tester, () async {
        await start(tester);
        expect(
          find.textContaining('No walking route is mapped'),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<PolylineLayer>(find.byType(PolylineLayer))
              .expand((layer) => layer.polylines)
              .where((line) => line.strokeWidth == 5),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
