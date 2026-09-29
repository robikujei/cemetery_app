# Visitor GPS tracking

Open the visitor Map and tap the location crosshair on the right. Allow the device/browser location prompt. The blue dot updates as the device reports its position; the translucent circle shows the reported accuracy radius. Tap the crosshair again to recenter, or the crossed-out location button to stop. The home button returns to the cemetery entrance view.

Tracking is opt-in and runs only for the lifetime of the map screen. It stops when the app becomes hidden/backgrounded or the map is disposed. Resume explicitly with the GPS button. Coordinates are held in memory; the app does not upload them to Supabase or keep a tracking history.

The map can display a position outside the cemetery. Low-accuracy fixes are labeled approximate. Fixes older than 60 seconds are gray and labeled last known position. A first fix that takes longer than 30 seconds ends the stream and offers a retry. Permission denial, disabled location services and stream errors are displayed on the map.

The existing walking route is entrance-based; this addition tracks the device position and does not add turn-by-turn routing from GPS.

Web location requires HTTPS (or localhost) and browser permission, as described in the [Geolocator documentation](https://pub.dev/packages/geolocator). The temporary HTTPS link is suitable. Laptop locations may be approximate; verify walking behavior on a phone outdoors. Android fine/coarse location and iOS when-in-use permission declarations are included. No background location permission is requested.

Validation: `flutter test test/gps_tracker_test.dart` covers location updates, stop/cancellation, denied permission, disabled services, late permission results, stream errors, invalid/stale fixes, and browsers without the Permissions API. Targeted static analysis and a release web build are also run. Physical GPS accuracy and platform permission dialogs require testing on real devices; native builds have not been validated here.
