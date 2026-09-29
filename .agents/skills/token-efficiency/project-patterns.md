# Cemetery app exploration

Treat this as a starting map; AGENTS.md and the current checkout are authoritative. Verify paths before relying on them.

## Flutter

Inspect pubspec.yaml for dependencies and SDK constraints. Follow lib/main.dart into lib/core/ for startup and routing. Trace a role-specific screen through its provider, service, and model. Reuse lib/widgets/ and lib/utils/ conventions where relevant.

## Maps and data

- Map behavior: lib/services/map_feature_service.dart and lib/utils/map_feature_geometry.dart.
- Complete data loading: lib/services/supabase_pagination_service.dart and its callers.
- Pricing: lib/utils/lot_pricing.dart before looking for duplicate constants.

## Supabase

Search relevant SQL and Flutter queries together. Local schema documents may differ from deployed state. When editing schema documentation, check both supabase/current_schema_data_dictionary.md and supabase/current_schema_dbdiagram.dbml.

Few textual matches do not prove a table is unused. Consider functions, triggers, policies, imports, and external consumers when relevant. Editing SQL does not authorize executing it against a remote database.

## Validation

Follow AGENTS.md for formatting, analysis, tests, and platform checks. Match checks to affected workflows and distinguish existing failures from regressions. Documentation-only skill edits do not require Flutter tests.
