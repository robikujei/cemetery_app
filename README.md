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
reviewed. A `Demo data` badge is shown in the admin screen, and the default
build leaves the flag disabled and continues to load production data from
Supabase.
