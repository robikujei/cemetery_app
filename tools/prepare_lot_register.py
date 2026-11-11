"""Prepare a private XLSX register and transactional SQL import (requires openpyxl).

Usage: python tools/prepare_lot_register.py source.xlsx output_directory --block 36
Generated files contain personal data: keep the output outside the repository.
"""
import argparse
import collections
import datetime as dt
import json
import pathlib
import re

import openpyxl


def text(value):
    return '' if value is None else str(value).strip()


def lot_number(value):
    raw = text(value)
    if not re.fullmatch(r'\d+(?:\.0+)?', raw):
        raise ValueError(f'Invalid lot number: {raw}')
    return f'{int(float(raw)):03d}'


def purchase_date(value):
    if isinstance(value, (dt.datetime, dt.date)):
        return value.strftime('%Y-%m-%d')
    raw = re.sub(r'\s+', ' ', text(value).replace(',', ', ')).strip()
    for fmt in ('%B %d, %Y', '%m/%d/%y', '%m/%d/%Y', '%Y-%m-%d'):
        try:
            return dt.datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            pass
    return None


def prepare(source, block, prime_c_is_super=False):
    workbook = openpyxl.load_workbook(source, data_only=True)
    records, issues = [], []
    for sheet in workbook:
        rows = list(sheet.values)
        headers = [text(v).upper() for v in rows[0]]
        required = ['BLOCK', 'LOT TYPE', 'LOT', 'LOT OWNER/PURCHASER', 'DATE', 'DECEASED']
        if any(h not in headers for h in required):
            raise ValueError(f'Unexpected headers in {sheet.title}')
        previous = None
        for row_no, values in enumerate(rows[1:], 2):
            row = dict(zip(headers, values))
            if not any(text(v) for v in values):
                previous = None
                continue
            location = f'{sheet.title}:{row_no}'
            if not text(row['LOT']):
                if previous is not None and text(row['DECEASED']) and not any(text(row[h]) for h in required[:-1]):
                    old = previous['details'].get('deceased_names', '')
                    previous['details']['deceased_names'] = '\n'.join(filter(None, [old, text(row['DECEASED'])]))
                    previous['source_rows'] += f', {row_no}'
                else:
                    issues.append([location, '', 'Unassigned continuation row', json.dumps(row, default=str)])
                continue
            try:
                number = lot_number(row['LOT'])
            except ValueError as error:
                issues.append([location, '', str(error), ''])
                previous = None
                continue
            details = {}
            for target, header in [('owner_name', 'LOT OWNER/PURCHASER'), ('deceased_names', 'DECEASED')]:
                if text(row[header]):
                    details[target] = text(row[header])
            if text(row['DATE']):
                date = purchase_date(row['DATE'])
                if date:
                    details['purchase_date'] = date
                else:
                    details['purchase_note'] = text(row['DATE'])
                    issues.append([location, number, 'Date kept as a note; existing purchase date retained', text(row['DATE'])])
            source_block = text(row['BLOCK'])
            eligible = source_block in ('', block, block + '.0')
            if source_block != block and source_block != block + '.0':
                issues.append([location, number, 'Blank block: using requested block' if eligible else 'Different source block: excluded', source_block])
            kind = text(row['LOT TYPE'])
            if kind.upper() == 'PRIMCE C':
                issues.append([location, number, 'Lot type spelling corrected', kind + ' -> Prime C'])
                kind = 'PRIME C'
            kind = kind.title()
            if kind and kind[-2:] in (' A', ' B', ' C'):
                kind = kind[:-1] + kind[-1].upper()
            if prime_c_is_super and kind == 'Prime C':
                issues.append([location, number, 'Approved type mapping', 'Prime C -> Super Prime C'])
                kind = 'Super Prime C'
            record = dict(lot=number, lot_type=kind or None, details=details, source_rows=location, eligible=eligible)
            records.append(record)
            previous = record
    counts = collections.Counter(r['lot'] for r in records)
    for record in records:
        if counts[record['lot']] > 1:
            record['eligible'] = False
            issues.append([record['source_rows'], record['lot'], 'Duplicate spreadsheet lot: excluded', 'Resolve both entries before import'])
    return records, issues


def sql_files(records, block, output):
    payload = json.dumps([r for r in records if r['eligible']], ensure_ascii=False)
    # Quote as a PostgreSQL string, including any literal backslashes safely.
    literal = "'" + payload.replace("'", "''") + "'"
    setup = f"""SET standard_conforming_strings = on;
CREATE TEMP TABLE register_source ON COMMIT DROP AS
SELECT * FROM jsonb_to_recordset({literal}::jsonb)
AS r(lot text, lot_type text, details jsonb, source_rows text, eligible boolean);
CREATE TEMP TABLE register_matches ON COMMIT DROP AS
SELECT s.*, m.lot_id, m.matches
FROM register_source s CROSS JOIN LATERAL (
  SELECT min(l.lot_id) AS lot_id, count(*) AS matches
  FROM public.cemetery_lot l
  WHERE trim(l.block_number) = '{block}'
    AND trim(l.lot_number) ~ '^0*[0-9]+$'
    AND coalesce(nullif(ltrim(trim(l.lot_number), '0'), ''), '0') =
        coalesce(nullif(ltrim(s.lot, '0'), ''), '0')
) m;
"""
    preview = """SELECT s.lot, s.source_rows, s.matches, s.lot_id,
+       l.lot_class_type AS current_type, s.lot_type AS imported_type,
+       l.price AS current_price, l.pricing_type,
+       CASE WHEN s.lot_type IS NULL THEN l.price
+            WHEN l.pricing_type = 'at_need' THEN c.at_need_price
+            ELSE c.pre_need_price END AS expected_price,
+       CASE WHEN s.matches = 0 THEN 'Not found'
+            WHEN s.matches > 1 THEN 'Ambiguous: skipped'
+            WHEN s.lot_type IS NOT NULL AND c.lot_type IS NULL THEN 'Unknown catalog type'
+            ELSE 'Ready' END AS result
+FROM register_matches s
+LEFT JOIN public.cemetery_lot l ON l.lot_id = s.lot_id AND s.matches = 1
+LEFT JOIN public.lot_price_catalog c ON lower(c.lot_type) = lower(trim(s.lot_type))
+ORDER BY s.lot;
+""".replace('\n+', '\n')
    (output / '01_preview.sql').write_text('BEGIN;\n' + setup + preview + 'ROLLBACK;\n', encoding='utf-8')
    apply = """-- Run 01_preview.sql first. Only unique matches are updated.
BEGIN;
LOCK TABLE public.cemetery_lot IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE IF NOT EXISTS public.lot_register_details (
  lot_id integer PRIMARY KEY REFERENCES public.cemetery_lot(lot_id) ON DELETE CASCADE,
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);
ALTER TABLE public.lot_register_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lot_register_details FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.lot_register_details TO authenticated;
DROP POLICY IF EXISTS lot_register_admin_read ON public.lot_register_details;
CREATE POLICY lot_register_admin_read ON public.lot_register_details FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.users WHERE user_id = auth.uid() AND role = 'admin'));
-- Private backup: no API roles receive access to this schema.
CREATE SCHEMA IF NOT EXISTS private_lot_import;
REVOKE ALL ON SCHEMA private_lot_import FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private_lot_import.backups (
  run_id timestamptz NOT NULL, lot_id integer NOT NULL,
  old_type text, old_details jsonb, new_type text, new_details jsonb,
  PRIMARY KEY (run_id, lot_id)
);
ALTER TABLE private_lot_import.backups
  ADD COLUMN IF NOT EXISTS old_price numeric,
  ADD COLUMN IF NOT EXISTS new_price numeric,
  ADD COLUMN IF NOT EXISTS old_pricing_type text,
  ADD COLUMN IF NOT EXISTS new_pricing_type text;
""" + setup + """
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM register_matches s WHERE s.matches = 1 AND s.lot_type IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.lot_price_catalog c
                    WHERE lower(c.lot_type) = lower(trim(s.lot_type)))
  ) THEN RAISE EXCEPTION 'Import contains a lot type missing from the price catalog; run the preview';
  END IF;
END $$;
INSERT INTO private_lot_import.backups
  (run_id, lot_id, old_type, old_details, new_type, new_details,
   old_price, old_pricing_type)
SELECT transaction_timestamp(), l.lot_id, l.lot_class_type, d.details,
       coalesce(s.lot_type, l.lot_class_type), coalesce(d.details, '{}'::jsonb) || s.details,
       l.price, l.pricing_type
FROM public.cemetery_lot l JOIN register_matches s ON s.lot_id = l.lot_id
LEFT JOIN public.lot_register_details d ON d.lot_id = l.lot_id
WHERE s.matches = 1;
UPDATE public.cemetery_lot l
SET lot_class_type = b.new_type
FROM private_lot_import.backups b
WHERE b.run_id = transaction_timestamp() AND b.lot_id = l.lot_id
AND EXISTS (SELECT 1 FROM register_matches s WHERE s.lot_id = l.lot_id AND s.lot_type IS NOT NULL);
UPDATE private_lot_import.backups b
SET new_type = l.lot_class_type, new_price = l.price, new_pricing_type = l.pricing_type
FROM public.cemetery_lot l
WHERE b.run_id = transaction_timestamp() AND b.lot_id = l.lot_id;
INSERT INTO public.lot_register_details(lot_id, details)
SELECT lot_id, new_details FROM private_lot_import.backups WHERE run_id = transaction_timestamp()
ON CONFLICT (lot_id) DO UPDATE SET details = excluded.details;
SELECT transaction_timestamp() AS backup_run_id,
       count(*) FILTER (WHERE matches = 1) AS imported,
       count(*) FILTER (WHERE matches = 0) AS not_found,
       count(*) FILTER (WHERE matches > 1) AS ambiguous
FROM register_matches;
COMMIT;
"""
    (output / '02_import.sql').write_text(apply, encoding='utf-8')
    (output / '03_restore.sql').write_text("""-- Replace the timestamp below with backup_run_id from the import result.
-- Preview the chosen backup first. Restore refuses fields edited since import.
BEGIN;
DO $$ BEGIN RAISE EXCEPTION 'Set the backup run timestamp and remove this guard before restoring'; END $$;
LOCK TABLE public.cemetery_lot, public.lot_register_details IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE restore_register ON COMMIT DROP AS
SELECT b.* FROM private_lot_import.backups b
JOIN public.cemetery_lot l ON l.lot_id = b.lot_id
JOIN public.lot_register_details d ON d.lot_id = b.lot_id
WHERE b.run_id = '2000-01-01T00:00:00Z'::timestamptz
AND l.lot_class_type IS NOT DISTINCT FROM b.new_type
AND l.price IS NOT DISTINCT FROM b.new_price
AND l.pricing_type IS NOT DISTINCT FROM b.new_pricing_type
AND d.details IS NOT DISTINCT FROM b.new_details;
-- Only during locked recovery: preserve the exact backed-up price rather than
-- recalculating it with today's catalog. Other triggers remain enabled.
ALTER TABLE public.cemetery_lot DISABLE TRIGGER cemetery_lot_fixed_price;
UPDATE public.cemetery_lot l SET lot_class_type = b.old_type,
  price = b.old_price, pricing_type = b.old_pricing_type
FROM restore_register b WHERE b.lot_id = l.lot_id;
ALTER TABLE public.cemetery_lot ENABLE TRIGGER cemetery_lot_fixed_price;
UPDATE public.lot_register_details d SET details = b.old_details
FROM restore_register b WHERE b.lot_id = d.lot_id AND b.old_details IS NOT NULL;
DELETE FROM public.lot_register_details d USING restore_register b
WHERE b.lot_id = d.lot_id AND b.old_details IS NULL;
COMMIT;
""", encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    parser.add_argument('--block', required=True)
    parser.add_argument('--prime-c-is-super', action='store_true',
                        help='Explicitly map Prime C to Super Prime C using the approved catalog')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+', args.block):
        parser.error('block must be numeric')
    records, issues = prepare(args.source, args.block, args.prime_c_is_super)
    args.output.mkdir(parents=True, exist_ok=True)
    book = openpyxl.Workbook()
    sheet = book.active
    sheet.title = 'Normalized lots'
    sheet.append(['BLOCK (MATCH ONLY)', 'LOT', 'LOT TYPE', 'LOT OWNER/PURCHASER', 'PURCHASE DATE', 'DECEASED', 'PURCHASE NOTE', 'SOURCE ROWS', 'IMPORT ELIGIBLE'])
    for r in records:
        d = r['details']
        sheet.append([args.block, r['lot'], r['lot_type'], d.get('owner_name'), d.get('purchase_date'), d.get('deceased_names'), d.get('purchase_note'), r['source_rows'], r['eligible']])
    review = book.create_sheet('Review issues')
    review.append(['SOURCE ROW', 'LOT', 'ISSUE', 'ORIGINAL VALUE'])
    for issue in issues:
        review.append(issue)
    for ws in book:
        ws.freeze_panes = 'A2'
        ws.auto_filter.ref = ws.dimensions
        for row in ws:
            for cell in row:
                if isinstance(cell.value, str):
                    cell.data_type = 's'  # Never interpret spreadsheet content as a formula.
        for column in ws.columns:
            ws.column_dimensions[column[0].column_letter].width = 24
    book.save(args.output / 'block_register_normalized.xlsx')
    sql_files(records, args.block, args.output)
    report = {'source_entries': len(records), 'eligible_entries': sum(r['eligible'] for r in records), 'review_issues': len(issues), 'blank_policy': 'keep existing', 'block': args.block}
    (args.output / 'summary.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (args.output / 'README.txt').write_text('''Block register import — not yet applied to the database

1. Open block_register_normalized.xlsx. Review the Review issues sheet.
   Both duplicate lot 366 entries and the entry with source block 0 are excluded.
   Blank fields keep existing values. Non-date DATE values become purchase notes.
   Continuation deceased names stay with the preceding lot. Slash-separated names
   are preserved verbatim; no burial dates or user accounts are invented.
2. In the Supabase project used by the cemetery app, open SQL Editor and run
   01_preview.sql. It is read-only and rolls back its temporary tables.
   Check unmatched and ambiguous lots. Only exactly one match is eligible.
3. Run 02_import.sql in that same project to apply eligible matches.
   Save the returned backup_run_id and imported/not_found/ambiguous counts.
4. Refresh Admin > Lots. Register names and purchase details appear on lot cards
   and can be searched. These register details are visible only to admins.

Matching uses the existing block plus numeric lot number, so 1 matches 001.
The import does not change block, lot number, lot label, status, map
geometry, user accounts, ownership links, or burial/grave records. It replaces
nonblank lot type and register owner/purchase/deceased fields for matched lots.
Nonblank lot types apply catalog prices using each lot's existing pricing mode.
The backup includes prices and pricing modes before and after the import.
Existing linked owner/burial records remain separate from the spreadsheet register.
The import is one transaction and saves old/new field values to a private backup.
03_restore.sql is a guarded recovery template; set the returned run timestamp
and remove its guard only when intentionally restoring that import. Subsequent
edits are protected by comparison against the imported values.

These files contain personal data. Keep them out of GitHub and public hosting.
''', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
