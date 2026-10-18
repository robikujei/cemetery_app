# cemetery_app

Flutter cemetery management and grave-finder application.

## Reports and analytics demo data

The admin reports screen can be previewed without a Supabase dataset. Start or
build the app with the opt-in compile-time flag:

```bash
flutter run -d chrome --dart-define=MOCK_ANALYTICS=true
flutter build web --dart-define=MOCK_ANALYTICS=true
```

The demo dataset includes lots with polygons, burial records, visitor logs,
ownerships, and payments so every report and the lot-only hotspot map can be
reviewed. The mock admin build opens directly to Reports & Analytics and shows
a `Demo data` badge. The default build leaves the flag disabled and continues
to require the normal admin login and load production data from Supabase.
