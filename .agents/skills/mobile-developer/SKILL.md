---
name: mobile-developer
description: Implement, debug, and review Flutter mobile features, native integrations, lifecycle behavior, and performance in this Riverpod, GoRouter, Supabase, and flutter_map project. Use for mobile application work, not unrelated documentation or backend-only tasks.
metadata:
  source: sickn33/mobile-developer
---

# Mobile development for Codex

Adapted for this repository from the installed mobile-developer skill. Follow AGENTS.md and the current checkout. Use the tools and permissions available in the session; this skill does not select a model, grant access, or install integrations.

## Establish the change

- Identify the affected role, user workflow, and platform from the request and existing code. Ask only when missing information materially changes implementation; proceed with routine choices already supported by the task.
- Check the branch and working tree. Preserve unrelated changes and follow the project's branch rules.
- Inspect pubspec.yaml, the lockfile, relevant platform configuration, and nearby implementations before choosing APIs. Match installed SDK and package versions rather than assuming the latest release.
- Trace the screen through its provider, service, model, and backend contract. Reuse existing routing, themes, widgets, and service logic before adding alternatives.
- Keep the existing Flutter architecture. Do not introduce React Native, another state-management framework, a new persistence layer, analytics, or a deployment pipeline unless required by the request.

## Flutter state and lifecycle

- Keep side effects out of widget build methods. Use the established Riverpod lifecycle and state patterns; avoid duplicate fetches and competing sources of truth.
- Represent loading, empty, error, and success states clearly. Guard against repeated submissions where duplicate writes would matter.
- After asynchronous work, verify that the relevant widget or context is still mounted before updating UI or navigating. Handle stale results when inputs or authenticated users change during a request.
- Dispose controllers, timers, subscriptions, and listeners according to their owner. Do not keep camera or realtime resources active after their owning workflow ends.
- Preserve GoRouter role checks and deep-link behavior. UI navigation restrictions do not replace backend authorization.
- Follow existing immutable state-update conventions. Keep nullability and error handling explicit rather than masking missing data with arbitrary defaults.

## Device features and usability

- For camera, location, media, and sharing changes, inspect the plugin and supported targets. Update native configuration only for the affected capabilities and platforms.
- Request permissions when the feature needs them and handle denial, permanent denial, cancellation, and unavailable hardware as applicable. Do not assume permission or plugin behavior is identical across targets.
- Account for pause/resume and navigation when using scanners, sensors, or streams. Preserve the project's visitor QR and gate-officer check-in contracts.
- Follow existing design and theme conventions. Check small screens, keyboard overlap, text scaling, readable labels, and accessible interactions for changed UI.
- Add native code or platform channels only when existing plugins and Flutter APIs cannot meet the requirement.

## Supabase and connectivity

- Reuse service mutations and inspect their status updates and audit behavior. Preserve authentication and row-level security; never expose service-role credentials in the app or logs.
- Handle network failure without implying a write succeeded. Retry writes only when duplicate effects are prevented or the operation is known to be idempotent.
- Use the shared pagination approach when complete result sets are required. Preserve realtime refresh and subscription cleanup.
- Do not assume offline sync exists. If offline support is requested, define pending-write visibility, retry behavior, ownership, and conflict handling before introducing a queue or local store.
- Inspect relevant SQL and schema documents alongside client queries. Local documents do not establish deployed state. Editing SQL does not authorize applying it remotely.

## Maps and performance

- Reuse map_feature_service.dart and map_feature_geometry.dart and preserve their caching and simplification behavior.
- Keep coordinate ordering explicit: GeoJSON/WKT use longitude then latitude; LatLng takes latitude then longitude.
- For a performance issue, identify a reproducible workflow and measure when tooling is available. Inspect unnecessary rebuilds, repeated requests, large layers, and resource lifetimes before adding caches or isolates.
- Avoid caching that leaks data across users or retains stale permissions and statuses. Tie invalidation to the owning data and session lifecycle.
- Distinguish observed improvements from expected ones. Without a suitable device or profiler, report the validation limit instead of claiming frame-rate or battery gains.

## Verification and completion

- Follow AGENTS.md: format changed Dart files, run flutter analyze and relevant tests, and run the broader suite for shared behavior changes. Resolve dependencies when necessary.
- Use existing test harnesses and appropriate provider overrides or mocks. Test observable behavior, including relevant error and lifecycle cases, rather than duplicating the implementation.
- Build affected platform targets when warranted and supported by the host. On Windows, do not claim an iOS build or device test without access to the required environment.
- Review generated files and diffs; do not manually edit generated plugin registrants or discard unrelated user changes.
- Summarize the changed behavior, checks performed, and remaining configuration or device validation. A successful static analysis does not prove hardware behavior.
- Keep signing, publishing, remote database changes, and releases within explicitly authorized scope. Do not treat a mobile feature request as deployment authorization.

This skill is self-contained. Consult current official framework or plugin documentation when version-specific behavior is uncertain; no external implementation playbook is required.
