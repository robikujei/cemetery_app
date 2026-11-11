"""Generate a guarded Family Estate import from the masterlist workbook.

Usage:
  python tools/prepare_family_estate_import.py "C:\\path\\MASTERLIST & INTERMENT RECORD.xlsx"

The resulting SQL is intentionally reviewed and run in Supabase SQL Editor.
It refuses to write unless all 66 source estates match one uniquely-labelled
Family Estate lot by phase and estate number.
"""

from __future__ import annotations

import datetime as dt
import json
import pathlib
import sys
from typing import Any

from openpyxl import load_workbook


ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "supabase" / "import_family_estate_records.sql"


def value(cell: Any) -> str:
    if cell is None:
        return ""
    if isinstance(cell, (dt.datetime, dt.date)):
        return cell.date().isoformat() if isinstance(cell, dt.datetime) else cell.isoformat()
    return str(cell).strip()


def date_parts(raw: Any, expected: int) -> list[str | None]:
    parts = [part.strip() for part in value(raw).split("/") if part.strip()]
    if not parts:
        return [None] * expected
    if len(parts) != expected:
        raise ValueError(f"Expected {expected} slash-separated values, got {len(parts)}: {raw!r}")
    parsed: list[str | None] = []
    for part in parts:
        for fmt in ("%m-%d-%Y", "%m/%d/%Y", "%Y-%m-%d"):
            try:
                parsed.append(dt.datetime.strptime(part, fmt).date().isoformat())
                break
            except ValueError:
                continue
        else:
            raise ValueError(f"Unrecognised date: {part!r}")
    return parsed


def main(source: pathlib.Path) -> None:
    workbook = load_workbook(source, data_only=True)
    estates: list[dict[str, Any]] = []
    for sheet in workbook.worksheets:
        name = sheet.title.upper()
        phase = "1" if "PH 1" in name or "PHASE 1" in name else "2" if "PH2" in name or "PH 2" in name or "PHASE 2" in name else None
        if phase is None:
            raise ValueError(f"Cannot determine phase from worksheet {sheet.title!r}")
        for row in range(2, sheet.max_row + 1):
            estate = sheet.cell(row, 1).value
            if estate is None:
                continue
            estate_no = int(float(estate))
            owner = value(sheet.cell(row, 2).value)
            deceased_raw = value(sheet.cell(row, 8).value)
            names = [part.strip() for part in deceased_raw.split("/") if part.strip()]
            births = date_parts(sheet.cell(row, 9).value, len(names)) if names else []
            deaths = date_parts(sheet.cell(row, 10).value, len(names)) if names else []
            interment = value(sheet.cell(row, 11).value) or None
            if interment:
                interment = dt.date.fromisoformat(interment).isoformat()
            estate_row = {
                "phase": phase,
                "estate_no": estate_no,
                "owner_name": owner or None,
                "address": value(sheet.cell(row, 3).value) or None,
                "phone": value(sheet.cell(row, 4).value) or None,
                "amount": value(sheet.cell(row, 5).value) or None,
                "or_number": value(sheet.cell(row, 6).value) or None,
                "purchase_date": value(sheet.cell(row, 7).value) or None,
                "interment_status": value(sheet.cell(row, 12).value) or None,
                "certification_fee": value(sheet.cell(row, 13).value) or None,
                "certification_or_number": value(sheet.cell(row, 14).value) or None,
                "certification_date": value(sheet.cell(row, 15).value) or None,
                "remarks": value(sheet.cell(row, 16).value) or None,
                "burials": [
                    {
                        "name": person,
                        "birth_date": births[index],
                        "death_date": deaths[index],
                        "interment_date": interment,
                    }
                    for index, person in enumerate(names)
                ],
            }
            estates.append(estate_row)

    if len(estates) != 66:
        raise ValueError(f"Expected 66 estates, found {len(estates)}")
    if sum(len(item["burials"]) for item in estates) != 10:
        raise ValueError("Expected 10 deceased records; inspect merged names before importing")

    payload = json.dumps(estates, ensure_ascii=False).replace("$json$", "$$ || '$json$' || $$")
    sql = f'''-- Generated from {source.name}. Do not edit the JSON payload manually.
-- Family Estate import: 66 estates, 10 deceased records.
-- The import matches only lots labelled with:
--   block_number = Family Estate Phase 1/2 and lot_number = estate number.
-- It aborts before writing if any of the 66 lots is missing or ambiguous.
BEGIN;
SET LOCAL lock_timeout = '10s';
LOCK TABLE public.cemetery_lot, public.users, public.lot_ownership,
  public.burial_record IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.burial_record ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.lot_ownership ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.lot_ownership ADD COLUMN IF NOT EXISTS purchase_note text;
CREATE UNIQUE INDEX IF NOT EXISTS users_register_import_key ON public.users(register_import_key);
CREATE UNIQUE INDEX IF NOT EXISTS burial_register_import_key ON public.burial_record(register_import_key);
CREATE UNIQUE INDEX IF NOT EXISTS ownership_register_import_key ON public.lot_ownership(register_import_key);
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL, ALTER COLUMN password DROP NOT NULL;
ALTER TABLE public.burial_record ALTER COLUMN death_date DROP NOT NULL;
ALTER TABLE public.lot_ownership ALTER COLUMN start_date DROP NOT NULL, ALTER COLUMN total_months DROP NOT NULL;

CREATE TEMP TABLE fe_source ON COMMIT DROP AS
SELECT * FROM jsonb_to_recordset($json${payload}$json$::jsonb)
  AS s(phase text, estate_no integer, owner_name text, address text, phone text,
       amount text, or_number text, purchase_date text, interment_status text,
       certification_fee text, certification_or_number text, certification_date text,
       remarks text, burials jsonb);

DO $$ BEGIN
  IF (SELECT count(*) FROM fe_source) <> 66 THEN
    RAISE EXCEPTION 'Expected 66 Family Estate rows';
  END IF;
  IF EXISTS(SELECT 1 FROM fe_source GROUP BY phase, estate_no HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Duplicate Phase + Estate Number in source';
  END IF;
END $$;

CREATE TEMP TABLE fe_matches ON COMMIT DROP AS
SELECT s.*, l.lot_id
FROM fe_source s JOIN public.cemetery_lot l
  ON lower(trim(l.block_number)) = lower('Family Estate Phase ' || s.phase)
 AND ltrim(regexp_replace(coalesce(l.lot_number, ''), '\\D', '', 'g'), '0') = s.estate_no::text;

DO $$ BEGIN
  IF (SELECT count(*) FROM fe_matches) <> 66 THEN
    RAISE EXCEPTION 'Expected 66 unique Family Estate matches, found %. Check each lot has Family Estate Phase 1/2 and its estate number saved in Lot Number.', (SELECT count(*) FROM fe_matches);
  END IF;
  IF EXISTS(SELECT 1 FROM fe_matches GROUP BY phase, estate_no HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'A Family Estate source row matches more than one lot';
  END IF;
END $$;

-- Preview this result before the inserts below when reviewing in SQL Editor.
SELECT phase, estate_no, lot_id, owner_name, jsonb_array_length(burials) AS deceased_count
FROM fe_matches ORDER BY phase::integer, estate_no;

CREATE TEMP TABLE fe_owners ON COMMIT DROP AS
SELECT upper(trim(owner_name)) AS owner_key, min(owner_name) AS owner_name,
       min(phone) AS phone, min(address) AS address,
       'family-estate:owner:' || md5(upper(trim(owner_name))) AS import_key
FROM fe_matches WHERE owner_name IS NOT NULL GROUP BY upper(trim(owner_name));
ALTER TABLE fe_owners ADD COLUMN user_id uuid;

INSERT INTO public.users(name, phone, address, role, register_import_key)
SELECT owner_name, phone, address, 'lot_owner', import_key FROM fe_owners
ON CONFLICT (register_import_key) DO UPDATE
SET name=excluded.name, phone=coalesce(public.users.phone, excluded.phone),
    address=coalesce(public.users.address, excluded.address);
UPDATE fe_owners o SET user_id=u.user_id FROM public.users u WHERE u.register_import_key=o.import_key;

INSERT INTO public.lot_ownership(lot_id, user_id, start_date, total_months, status, purchase_note, register_import_key)
SELECT m.lot_id, o.user_id, nullif(m.purchase_date,'')::date, NULL, 'Active',
  concat_ws(' | ', 'Family Estate Phase '||m.phase||', Estate '||m.estate_no,
    nullif('OR #'||m.or_number, 'OR #'), nullif('Amount '||m.amount, 'Amount '), nullif(m.remarks,'')),
  'family-estate:ownership:'||m.phase||':'||m.estate_no
FROM fe_matches m JOIN fe_owners o ON o.owner_key=upper(trim(m.owner_name))
ON CONFLICT (register_import_key) DO UPDATE
SET user_id=excluded.user_id, purchase_note=excluded.purchase_note;

CREATE TEMP TABLE fe_burials ON COMMIT DROP AS
SELECT m.*, b.ordinality AS burial_position, b.item
FROM fe_matches m CROSS JOIN LATERAL jsonb_array_elements(m.burials) WITH ORDINALITY AS b(item, ordinality);

INSERT INTO public.burial_record(name_of_deceased, birth_date, death_date, burial_date,
  interment_date, lot_id, lot_location_no, registered_lot_owner, registered_owner_contact_no,
  burial_category, interment_total, interment_or_number, interment_payment_date, register_import_key)
SELECT item->>'name', nullif(item->>'birth_date','')::date, nullif(item->>'death_date','')::date,
  nullif(item->>'interment_date','')::date, nullif(item->>'interment_date','')::date,
  lot_id, 'FE-P'||phase||'-'||lpad(estate_no::text, 2, '0'), owner_name, phone,
  coalesce(interment_status, 'Family Estate'), NULL, certification_or_number,
  nullif(certification_date,'')::date,
  'family-estate:burial:'||phase||':'||estate_no||':'||burial_position
FROM fe_burials
ON CONFLICT (register_import_key) DO UPDATE
SET name_of_deceased=excluded.name_of_deceased, birth_date=excluded.birth_date,
  death_date=excluded.death_date, burial_date=excluded.burial_date,
  interment_date=excluded.interment_date, lot_id=excluded.lot_id,
  registered_lot_owner=excluded.registered_lot_owner,
  registered_owner_contact_no=excluded.registered_owner_contact_no;

UPDATE public.cemetery_lot l SET status=CASE
  WHEN EXISTS(SELECT 1 FROM public.burial_record b WHERE b.lot_id=l.lot_id
    AND b.register_import_key LIKE 'family-estate:burial:%') THEN 'Occupied'
  WHEN EXISTS(SELECT 1 FROM public.lot_ownership o WHERE o.lot_id=l.lot_id
    AND o.register_import_key LIKE 'family-estate:ownership:%') THEN 'Reserved'
  ELSE l.status END
WHERE l.lot_id IN (SELECT lot_id FROM fe_matches);

SELECT pg_notify('pgrst', 'reload schema');
SELECT (SELECT count(*) FROM fe_matches) AS matched_estates,
  (SELECT count(*) FROM fe_owners) AS imported_owner_profiles,
  (SELECT count(*) FROM fe_burials) AS imported_burials;
COMMIT;
'''
    OUTPUT.write_text(sql, encoding="utf-8")
    print(f"Wrote {OUTPUT} with {len(estates)} estates and {sum(len(e['burials']) for e in estates)} burial records.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: prepare_family_estate_import.py MASTERLIST.xlsx")
    main(pathlib.Path(sys.argv[1]))
