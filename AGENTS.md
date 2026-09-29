# Project instructions

## Scope and project layout

These instructions apply to `cemetery_app` and its subdirectories.
Run project commands from this directory; the parent directory is not this Git repository.

This is a Flutter cemetery management and grave finder application using
Riverpod, GoRouter, Supabase, and flutter_map. Screens are organized by role:
admin, guard, lot owner, visitor, and authentication.

- `lib/main.dart`: application startup and Supabase initialization.
- `lib/core/`: app configuration, routing, and theme.
- `lib/screens/`: role-specific screens.
- `lib/providers/`, `lib/services/`, and `lib/models/`: state, service logic, and data models.
- `lib/widgets/` and `lib/utils/`: reusable UI and utilities.
- `supabase/`: SQL scripts, schema documentation, and backend functions.
- `test/`: Flutter tests.
- Platform folders contain native configuration for supported Flutter targets.

## Historical context and branch awareness

The following references come from local Git history reviewed on 2026-09-29.
Verify current branch contents before relying on them; commit subjects alone
do not reliably describe the changes.

- May 2026 (`1885623` through `5c1313a`): grave destination QR codes, visitor search/history, gate officer scanning, reports, and CRUD audit logging.
- June 2026 (`fa5b581`, `81af277`): expanded burial and ownership management, QGIS import scripts and geometry helpers, schema documentation, and map behavior.
- July 2026 (`9ed72be` through `75e9ae7`): mapping and record-management refinements, pagination, shared lot pricing, realtime monitoring, and removal of standalone admin transaction and lot-owner payment screens.
- `f935cbf`: polygon simplification and geometry caching, despite its subject mentioning summaries.
- At this review, `development` points to `f935cbf`; local `main` has an additional commit, `e04f05f`, with GPS tracking, analytics, payment requests, audit triggers, and related tests/docs. These are not present on this development baseline. Do not assume they exist or restore them without task scope requiring it.

Use `git log --all --oneline --decorate` and targeted `git show` or branch diffs
when a requested feature appears missing. Do not merge or cherry-pick unrelated
features merely to make branches match.

## Domain behavior to preserve

- The current hierarchy is blocks, lots, and graves. Blocks use `cemetery_lot.block_number`; avoid reintroducing legacy branch/section models into the Flutter workflow.
- Preserve burial-to-grave/lot links and resulting lot status updates. Consult `lib/services/admin_grave_service.dart`, `admin_lot_owner_service.dart`, and `admin_delete_service.dart` before duplicating mutations.
- Reuse `lib/utils/lot_pricing.dart` for the price catalog and interment fee. Coordinate intentional pricing changes with the corresponding SQL instead of scattering constants across screens.
- Keep visitor QR generation, the gate officer scanner, `supabase/functions/visitor-checkin`, visitor history, and audit records compatible when changing check-in behavior.
- Inspect the relevant audit call sites before changing CRUD operations; do not assume every branch has database audit triggers.
- The UI calls the guard role a gate officer and uses `/gate-officer`; preserve compatibility with stored role values and login routing.

## Mapping and data loading

- Reuse `lib/utils/map_feature_geometry.dart` and `lib/services/map_feature_service.dart` for shared geometry and feature handling.
- Preserve polygon caching and low-detail simplification. Check both map accuracy and rendering cost when changing large lot layers.
- Keep coordinate order explicit: GeoJSON/WKT use longitude then latitude, while `LatLng` takes latitude then longitude.
- Inspect `tools/qgis_geojson_to_supabase_csv.py` and the matching staging/import SQL together when changing QGIS fields or imports.
- Public map previews intentionally filter feature types. Hidden pathway/node layers are not evidence that routing data is unused; retain `path_nodes` and `path_edges` where routing depends on them.
- For queries that must load all rows, account for Supabase response limits and inspect `lib/services/supabase_pagination_service.dart`; do not assume a single select returns the entire cemetery.
- Preserve realtime refresh behavior and review `supabase/enable_objective_monitoring_realtime.sql` when changing monitored tables.

## Working practices

- Check `git status` and the current branch before editing. Preserve unrelated local changes.
- Use `development` or a task-specific branch for modifications; keep `main` as the original baseline unless the user requests otherwise.
- Do not discard changes, reset history, or switch branches with unsaved work as a shortcut.
- Keep changes focused on the requested task and follow nearby code conventions.
- Reuse existing providers, services, widgets, routing, and theme patterns before adding alternatives or dependencies.
- Preserve role-based access behavior when changing navigation, screens, or backend queries.
- Do not manually edit generated plugin registrants or build outputs. Review generated changes from Flutter commands and report unrelated changes without discarding the user's work.
- Never add service-role keys, private credentials, or access tokens to source code or logs.

## Database changes

- Git branches isolate source code, not the Supabase database configured by the app.
- Editing SQL does not authorize executing it against a remote database. Apply database changes only within the user's explicitly authorized scope and target environment.
- Before changing schema-dependent code, inspect the relevant SQL, schema documentation, and existing queries. Treat local schema documents as references that may differ from the deployed database.
- For schema changes, explain prerequisites, affected data, and how to validate the result. Prefer repeatable scripts where practical.
- For destructive SQL, make the impact explicit and provide a preview query or recovery guidance appropriate to the change.
- Preserve authentication and row-level security protections.
- Legacy cleanup scripts refer to the older React/Express/Prisma app in the parent workspace. Confirm actual consumers before classifying tables as unused; retain QGIS staging tables needed by imports.
- Check both `supabase/current_schema_data_dictionary.md` and `supabase/current_schema_dbdiagram.dbml` when updating schema documentation.

## Validation

- Use the Flutter and Dart SDK constraints in `pubspec.yaml`.
- Run `flutter pub get` when dependencies change or package resolution is needed.
- Format changed Dart files with `dart format <changed-files>`.
- For code changes, run `flutter analyze` and relevant tests, such as `flutter test test/<file>_test.dart`.
- Run `flutter test` when changes affect shared application behavior; build a platform target when platform-specific changes warrant it.
- Add meaningful tests for new logic and bug fixes when practical. Documentation-only changes do not require Flutter tests.
- Tests involving app startup may need Riverpod and Supabase setup or mocked dependencies; inspect the test harness rather than assuming startup is self-contained.
- Report commands run, failures, and checks that could not be completed. Distinguish pre-existing failures from regressions.
- Choose checks based on the affected workflow: grave/lot status propagation, QR generation and check-in, map selection and rendering, complete paginated results, or report refresh. Do not write tests that merely repeat implementation details.

## Communication

Summarize what changed, why it changed, and how it was verified. Mention any
required database or configuration steps. Do not claim a deployment, database
update, commit, or push occurred unless it actually did.
