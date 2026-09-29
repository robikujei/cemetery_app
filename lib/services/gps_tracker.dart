import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Foreground, device-only location tracking. No location is persisted or sent
/// to the application's database. A generation token ignores late permissions
/// and fixes after stop/dispose.
class GpsTracker extends ChangeNotifier {
  GpsTracker({GeolocatorPlatform? platform})
    : _platform = platform ?? GeolocatorPlatform.instance;

  final GeolocatorPlatform _platform;
  StreamSubscription<Position>? _subscription;
  Timer? _firstFixTimer, _freshnessTimer;
  int _generation = 0;
  bool _disposed = false;
  bool active = false;
  Position? position;
  String? message;
  bool get stale =>
      position != null &&
      DateTime.now().difference(position!.timestamp).inSeconds > 60;

  Future<void> start() async {
    if (_disposed || active) return;
    final generation = ++_generation;
    active = true;
    position = null;
    message = 'Allow location access to show your position.';
    notifyListeners();
    bool current() => !_disposed && generation == _generation;
    try {
      final enabled = await _platform.isLocationServiceEnabled();
      if (!current()) return;
      if (!enabled) {
        stop(
          message:
              'Location is switched off. Enable device location and try again.',
        );
        return;
      }
      var permission = await _platform.checkPermission();
      if (!current()) return;
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
        if (!current()) return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        stop(
          message:
              'Location access denied. Allow location in your browser or app settings, then try again.',
        );
        return;
      }
      // Browsers without the Permissions API report unableToDetermine; the
      // position stream itself prompts for consent in those browsers.
      message = 'Finding your location…';
      notifyListeners();
      final LocationSettings settings =
          !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS)
          ? AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              allowBackgroundLocationUpdates: false,
              pauseLocationUpdatesAutomatically: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            );
      _subscription = _platform
          .getPositionStream(locationSettings: settings)
          .listen(
            (fix) {
              if (!current()) return;
              if (!fix.latitude.isFinite ||
                  !fix.longitude.isFinite ||
                  fix.latitude.abs() > 90 ||
                  fix.longitude.abs() > 180 ||
                  !fix.accuracy.isFinite ||
                  fix.accuracy < 0) {
                return;
              }
              if (position != null &&
                  fix.timestamp.isBefore(position!.timestamp)) {
                return;
              }
              _firstFixTimer?.cancel();
              position = fix;
              message = null;
              notifyListeners();
            },
            onError: (Object error) {
              if (current()) {
                stop(
                  message:
                      'Location unavailable. Check location permission, device location, and your connection, then try again.',
                );
              }
            },
            onDone: () {
              if (current()) {
                stop(message: 'Location tracking ended. Tap GPS to try again.');
              }
            },
          );
      _firstFixTimer = Timer(const Duration(seconds: 30), () {
        if (current() && position == null) {
          stop(
            message:
                'No location fix yet. Try outdoors or check device location, then tap GPS again.',
          );
        }
      });
      _freshnessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (current() && position != null) notifyListeners();
      });
    } catch (_) {
      if (current()) {
        stop(
          message:
              'Could not start GPS. Use the HTTPS link and allow location in your browser or app settings.',
        );
      }
    }
  }

  void stop({String? message}) {
    _generation++;
    _firstFixTimer?.cancel();
    _freshnessTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    active = false;
    position = null;
    this.message = message;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
