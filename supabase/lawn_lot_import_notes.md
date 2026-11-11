# Lawn-lot relational import

The consolidated lawn-lot workbook is processed by
`tools/prepare_lawn_lot_import.py`. Generated CSV and SQL files contain personal
data and must remain outside the repository.

The tool segregates the register into the application's current tables:

- existing `cemetery_lot` matches;
- imported non-login `users` with the `lot_owner` role;
- `lot_ownership` rows;
- `burial_record` rows; and
- occupied `graves` linked to the imported burials.

It also produces review exceptions plus read-only preview, transactional import,
validation, and guarded rollback SQL. It does not invent missing dates, login
credentials, installment terms, or payment transactions. Unparseable source
dates remain in admin-only lot register metadata.

## Full segregation

The November 9, 2026 review excluded Block 36 because it had already been
imported. The remaining source contains 4,102 unique lot records across Blocks
13, 15, 17, 19, 19-2 (normalized match key `192`), 30, 32, and 34. The review
package identified 3,570 owner profiles, 3,990 ownership rows, 3,587 burial
records, and 3,587 grave links. Ambiguous `Prime C` source types are not mapped
to a catalog type; the existing database type is preserved.

## Block 13 import

Block 13 was previewed and imported on November 9, 2026. The read-only preview
matched all 406 source lots to exactly one existing mapped lot and returned zero
missing lots, ambiguous lots, unknown catalog types, owner-name collisions, and
existing ownership conflicts.

Import backup run (UTC): `2026-11-09 15:36:50.725512+00`

- 378 owner profiles;
- 385 ownerships;
- 159 burial records;
- 159 linked graves;
- 115 occupied lots and 270 reserved lots; and
- zero broken burial-to-grave links after validation.

The Block 13 review contains 81 unparseable combined/annotated date cells and 9
unassigned source rows. Those values were not fabricated into relational dates
or records; they remain available in the private review package for manual
resolution.

## Remaining mapped blocks

The same preview/import/validation sequence was completed for the other mapped
lawn blocks on November 9, 2026:

| Block | Matched lots | Burials/graves | Backup run (UTC) |
| --- | ---: | ---: | --- |
| 15 | 309 | 99 | `2026-11-09 15:38:55.931861+00` |
| 17 | 667 | 423 | `2026-11-09 15:41:42.351573+00` |
| 19 | 305 | 314 | `2026-11-09 15:43:17.719408+00` |
| 30 | 655 | 759 | `2026-11-09 15:44:33.213152+00` |
| 32 | 835 | 833 | `2026-11-09 15:46:03.875828+00` |
| 34 | 620 | 699 | `2026-11-09 15:47:35.647533+00` |

All imported burial records have exactly one grave link in the same lot. Final
validation found 3,286 lawn burial records, 3,286 lawn graves, and zero broken
links across Blocks 13, 15, 17, 19, 30, 32, and 34.

The global review found 37 same-name owner groups with conflicting contact
numbers. A guarded reconciliation removed 66 uncertain ownership links and 33
merged profiles rather than guessing identity. Backup run:
`2026-11-09 15:51:41.354561+00`. The database retains 3,557 unique lawn owner
profiles and 3,686 defensible lawn ownership links. Raw owner text remains in
admin-only register metadata for manual resolution.

The workbook sheet `BLOCK 19 (2)` normalizes to match key `192`, but all 305 of
its source lots are absent from the current mapped database. No rows from that
sheet were imported. Its private SQL/CSV package remains pending until those map
lots are created or the correct database block identifier is confirmed.
