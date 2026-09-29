# Paper requirements implemented — 13 September 2026

Source: `GIS-Based-Cemetery-Mapping-and-Burial-Information-System-with-Hotspot-Analysis-FINAL-NAJUD-NI-COPY.docx` in the parent workspace. The functional requirements and spatial-analysis methodology were read from the paper, rather than relying on the older requirements assessment.

## Added workflows

| Paper requirement | Where to use it | Implementation |
| --- | --- | --- |
| High/medium/low demand | Admin Overview and Reports | Per-block occupied-or-sold share, deduplicating overlapping ownership and occupancy. Reports allows changing cutoffs. |
| DBSCAN hotspot analysis | Admin Reports → Spatial burial hotspots | Metre-based clustering, configurable radius and MinPts, colored mapped clusters, noise, block membership, date filters, missing-location counts. |
| Density comparison | Below the hotspot map | Per-block burials per hectare of mapped lot footprint, compared with mean plus two population standard deviations. |
| Daily/weekly/monthly visitor trends | Admin Reports | Philippine calendar dates, Monday-based weeks, zero-filled missing periods, full end-day inclusion. |
| Burial, inventory, sales, payment, visitor and demand reports | Admin Reports → Download CSV | Paginated source queries and complete CSV exports; previews are bounded. Payment totals use transactions, not lot list prices. |
| Payment proof submission | Lot owner → payments icon | Private JPG/PNG receipt upload (5 MB maximum), own-lot selection, payment date/amount/notes, request status and review notes. |
| Payment approval | Admin → Payment Review | Admin review, rejection reason, optional explicit installment-month credit, atomic transaction insertion and duplicate-review protection. |
| QR entry and exit | Gate Officer → Entry / Exit | Serialized per-visitor writes, open-entry detection, checkout timestamps, re-entry after checkout, overnight open visits supported. |
| Audit trail | Admin → Audit Trail | Correct actor roles for login/logout and exports; database triggers record core record changes; payment and gate RPCs write audit records in the same transaction. |
| Role-based access | Protected routes and new database workflows | Role-aware route redirects; ownership, payment and visitor row policies; role-change and financial-write protection. |

Existing grave search, burial editing, GIS layout editing, path-node drawing and Dijkstra navigation were retained. This work does not claim to revalidate every pre-existing workflow or the paper's non-functional evaluation criteria.

## Analysis definitions and limits

- DBSCAN follows the density-connectivity method in [Ester et al. (1996)](https://aaai.org/papers/kdd96-037-a-density-based-algorithm-for-discovering-clusters-in-large-spatial-databases-with-noise/). The local planar metre projection is intended for cemetery-sized extents. MinPts includes the point itself. A previously isolated point can become a cluster border point.
- Defaults are 15 metres and 5 burial records. These are adjustable starting values, not values specified or validated by the paper. Multiple records in the same lot share a location. A polygon's mean vertex location is a representative location, not a surveyed individual grave coordinate.
- The live map has lot polygons but no explicit `block` polygon features. Consequently density uses the sum of lot polygon footprints in each block, excluding walkways and unmapped land. This is a stated proxy for block area. It does not reproduce a full block-boundary-area study. Polygon holes are not subtracted by the existing geometry parser.
- The paper describes mean + 2 standard deviations as statistical significance. The app correctly labels this an exploratory threshold: that rule alone is not a significance test. At least three mapped blocks are required for the comparison. DBSCAN cluster membership and above-threshold block density are separate results.
- Default demand cutoffs are Low <30%, Medium 30–<70%, High ≥70%. Score = distinct occupied-or-sold lots / total lots. The paper gives no exact formula or cutoffs; these are disclosed implementation choices. Current uptake is not a forecast. Report settings are local to the screen; the dashboard uses the displayed defaults.
- Inventory/demand are current snapshots. Other reports filter by their stated dates. Missing burial dates are excluded only with date filters. Visitor timestamps without an offset follow the existing Philippine-local convention; offset timestamps are converted to UTC+8.
- Sales rows show ownership records and clearly labeled current list prices. The schema does not store immutable historical sale prices per ownership. These list prices must not be interpreted as collected revenue. Payments use `transaction_history`.
- Real-time channels require their tables to be in the Supabase realtime publication. Refresh remains available. CSV exports fetch all pages; displayed tables show the first 100 rows and visitor charts the latest 24 periods.

## Database deployment

Applied to project `gvvbzkbdqeuyaujqrpcb`:

1. `supabase/add_paper_workflows.sql`
2. `supabase/add_record_audit_triggers.sql`
3. `supabase/enable_paper_reports_realtime.sql`

The changes add `visitor_log.time_out`, `transaction_history.payment_request_id`, a private receipt bucket, RPCs, policies and audit triggers. They do not rewrite historical records. The SQL files can be reapplied.

Payment approval records a submitted payment; it does not transfer money. Administrators explicitly choose the installment months to credit because the existing schema does not define a trustworthy per-ownership installment amount. Use zero for an incomplete installment.

## Validation

- `flutter test test/cemetery_analytics_test.dart`: cluster separation, noise-to-border reassignment, coincident points, empty input, demand deduplication, Philippine midnight/end-day boundaries, weekly/monthly grouping, missing dates, CSV escaping, geographic eligibility.
- `supabase/test_paper_workflows.sql`: transactional integration checks for owned-lot submission, private request access, forbidden owner approval, installment tampering, exactly-once approval, entry/exit, and unauthorized gate access. All fixtures are rolled back.
- Targeted Flutter analysis and a release web build.

At verification the live database had 4,592 lot polygons, two burial records and no visitor logs. Empty default clusters and visitor trends are expected. No demo burials, payments or visitor visits were added. Full camera/receipt interaction and user acceptance testing with actual role accounts remain to be performed.
