import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cemetery_app/services/gps_tracker.dart';

class FakeGps extends GeolocatorPlatform {
  final fixes = StreamController<Position>.broadcast();
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Completer<LocationPermission>? pendingPermission;
  int streams = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async =>
      pendingPermission == null ? permission : await pendingPermission!.future;
  @override
  Future<LocationPermission> requestPermission() async => permission;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streams++;
    return fixes.stream;
  }
}

Position fix({double latitude = 7.3, DateTime? timestamp}) => Position(
  longitude: 125.6,
  latitude: latitude,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late FakeGps source;
  late GpsTracker tracker;
  setUp(() {
    source = FakeGps();
    tracker = GpsTracker(platform: source);
  });
  tearDown(() async {
    tracker.dispose();
    await source.fixes.close();
  });

  test(
    'Starts only on request, updates position, and cancels on stop',
    () async {
      expect(source.streams, 0);
      await tracker.start();
      source.fixes.add(fix());
      await Future<void>.delayed(Duration.zero);
      expect(tracker.position!.latitude, 7.3);
      expect(tracker.active, isTrue);
      tracker.stop();
      source.fixes.add(fix(latitude: 8));
      await Future<void>.delayed(Duration.zero);
      expect(tracker.position, isNull);
      expect(source.fixes.hasListener, isFalse);
    },
  );
  test('Denied permission never starts a position stream', () async {
    source.permission = LocationPermission.deniedForever;
    await tracker.start();
    expect(source.streams, 0);
    expect(tracker.active, isFalse);
    expect(tracker.message, contains('denied'));
  });
  test('Disabled location service offers an actionable message', () async {
    source.enabled = false;
    await tracker.start();
    expect(source.streams, 0);
    expect(tracker.message, contains('switched off'));
  });
  test('Stopping during permission check ignores late completion', () async {
    source.pendingPermission = Completer<LocationPermission>();
    final start = tracker.start();
    await Future<void>.delayed(Duration.zero);
    tracker.stop();
    source.pendingPermission!.complete(LocationPermission.whileInUse);
    await start;
    expect(source.streams, 0);
    expect(tracker.active, isFalse);
  });
  test('Stream errors clear location and stop tracking', () async {
    await tracker.start();
    source.fixes.add(fix());
    await Future<void>.delayed(Duration.zero);
    source.fixes.addError(Exception('GPS unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(tracker.position, isNull);
    expect(tracker.active, isFalse);
    expect(tracker.message, contains('unavailable'));
  });
  test(
    'Old fixes are labeled stale and invalid coordinates are ignored',
    () async {
      await tracker.start();
      source.fixes.add(
        fix(timestamp: DateTime.now().subtract(const Duration(minutes: 2))),
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracker.stale, isTrue);
      source.fixes.add(fix(latitude: double.nan));
      await Future<void>.delayed(Duration.zero);
      expect(tracker.position!.latitude, 7.3);
      source.fixes.add(fix());
      await Future<void>.delayed(Duration.zero);
      expect(tracker.stale, isFalse);
    },
  );
  test(
    'Browsers without the Permissions API can request a location stream',
    () async {
      source.permission = LocationPermission.unableToDetermine;
      await tracker.start();
      expect(source.streams, 1);
    },
  );
}
