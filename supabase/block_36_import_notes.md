# Block 36 relational import

`repair_block_36_relational_import.sql` promotes the 678 reviewed rows already
stored in `lot_register_details` into the tables consumed by the application.
It is deliberately scoped to Block 36 and refuses unexpected source counts,
duplicate lot numbers, conflicting ownerships, and ambiguous existing burials.

Initial 676-row import applied on October 15, 2026 (Asia/Manila), from the `main` checkout. Backup run:
`2026-10-14 21:14:00.697558+00`.

- 542 new non-login `users` profiles, plus one existing linked owner.
- 673 new `lot_ownership` records, plus one existing record preserved.
- 738 new `burial_record` records, plus two existing records preserved.
- 740 linked `graves` records, on 417 occupied lots; 257 lots reserved.
- The two excluded source lots and blank source fields are not fabricated.

Profiles do not create Supabase Auth accounts. Their email and password are
NULL. Check constraints preserve credential requirements for ordinary profiles.
Unknown death dates and ownership terms are allowed only on records with an
import key. Purchase dates populate ownership start dates; purchase notes are
preserved. Unknown payment status, installments, amounts, and dates remain NULL.
The import does not create transaction/payment records.

Deceased names split at slashes/newlines. Original annotations remain in names
and the source register. Grave labels identify imported records, not physical
positions within a lot. Existing lot geometry remains unchanged.

Validation included a full transaction rolled back before application, a
second rollback after application to verify repeatability, and a dry run of the
combined corrected import. There were zero mismatched grave-to-burial lot links.

Backups are in `private_lot_import.relational_backup`, inaccessible to API roles.
They retain pre-import lots, register rows, ownerships, burials, and graves.
New profiles/ownerships/burials have stable `block36:` import keys. Recovery
must compare current rows with the backup and check dependent records before
removing imported data; never blindly cascade-delete profiles or burials.
The old `03_restore.sql` restores only register metadata/pricing, not this
relational repair. Restoring NOT NULL constraints requires resolving imported
unknown values first.

The private Downloads import folder now contains a corrected `02_import.sql`
that performs both stages in one transaction, and the original register-only
script is retained as `02_register_only.original.sql`. Do not publish these
files: they contain personal data.

Lot 366 correction (October 15, 2026): source rows Sheet1:413 and 414 are
complementary records for the same lot, not conflicting owners. They were merged
and imported as one owner/ownership and three burials with linked graves.
Lot 366 is Occupied. Totals are now 544 owner profiles, 675 ownerships,
743 burials and 743 graves across 677 reviewed register lots.
Backup run: 2026-10-14 21:28:04.850836+00.
02_import.sql includes the merged source. 07_import_lot_366.sql is the targeted
repair; 08_lot_366_dry_run.sql rolls it back for preview.
At this stage, lot 498 remained excluded; the correction below resolves it.


Lot 498 correction (October 15, 2026): user confirmed Block 36 for source
Sheet1:564, originally marked block 0. Imported one ownership using the existing
owner profile and two burials with linked graves. Type corrected to Prime A
through the existing price trigger; status Occupied. Owner lot summary updated.
All 678 source lot numbers now included (36 and 489 have blank source details).
Current totals: 544 owner profiles, 676 ownerships, 745 burials and 745 graves.
Backup run: 2026-10-14 21:31:03.717766+00. Original lot/owner snapshots also in
private_lot_import.correction_backup. 09_import_lot_498.sql is the repair;
10_lot_498_dry_run.sql is its rollback preview.
