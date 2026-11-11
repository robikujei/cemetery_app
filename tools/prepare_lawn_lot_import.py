"""Segregate the consolidated lawn register and generate a guarded SQL import.

Usage:
  python tools/prepare_lawn_lot_import.py source.xlsx output_directory

The output contains personal data. Keep it outside the repository. The tool
does not connect to Supabase; run 01_preview.sql before 02_import.sql.
"""

from __future__ import annotations

import argparse
import collections
import csv
import datetime as dt
import hashlib
import json
import pathlib
import re
from typing import Any

import openpyxl
from openpyxl.utils.datetime import from_excel


CATALOG_TYPES = {
    "REGULAR LOT": "Regular Lot",
    "RL": "Regular Lot",
    "PRIME A": "Prime A",
    "PA": "Prime A",
    "PRIME B": "Prime B",
    "PB": "Prime B",
    "SUPER PRIME A": "Super Prime A",
    "SPA": "Super Prime A",
    "SUPER PRIME B": "Super Prime B",
    "SPB": "Super Prime B",
    "SUPER PRIME C": "Super Prime C",
    "SPC": "Super Prime C",
    "CORNER LOT": "Corner Lot",
    "CL": "Corner Lot",
}
AMBIGUOUS_TYPES = {"PRIME C", "PRIMCE C"}


def text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()
    return str(value).strip()


def compact(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", text(value).lower())


def header_index(row: tuple[Any, ...]) -> dict[str, int]:
    return {compact(value): index for index, value in enumerate(row) if text(value)}


def cell(row: tuple[Any, ...], headers: dict[str, int], *aliases: str) -> str:
    for alias in aliases:
        index = headers.get(compact(alias))
        if index is not None and index < len(row):
            return text(row[index])
    return ""


def normalize_block(raw: str, sheet: str) -> str | None:
    candidate = raw or re.sub(r"^BLOCK\s+", "", sheet, flags=re.I)
    normalized = compact(candidate)
    if not normalized:
        return None
    digits = "".join(re.findall(r"\d+", normalized))
    if not digits:
        return None
    return str(int(digits))


def normalize_lot(raw: str) -> str | None:
    value = text(raw)
    if not re.fullmatch(r"\d+(?:\.0+)?", value):
        return None
    return str(int(float(value)))


def normalize_name(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def stable_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:24]


def parse_date(value: str) -> str | None:
    raw = re.sub(r"\s+", " ", text(value)).strip()
    if not raw:
        return None
    if re.fullmatch(r"\d{5}(?:\.\d+)?", raw):
        try:
            return from_excel(float(raw)).date().isoformat()
        except (TypeError, ValueError, OverflowError):
            pass
    for fmt in (
        "%Y-%m-%d",
        "%Y-%m-%dT%H:%M:%S",
        "%m/%d/%Y",
        "%m/%d/%y",
        "%B %d, %Y",
        "%b %d, %Y",
    ):
        try:
            return dt.datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            pass
    return None


def canonical_lot_type(raw: str) -> tuple[str | None, str | None]:
    value = re.sub(r"\s+", " ", raw.upper()).strip()
    if not value:
        return None, None
    if value in CATALOG_TYPES:
        return CATALOG_TYPES[value], None
    if value in AMBIGUOUS_TYPES:
        return None, "Prime C is not in the current price catalog; existing database type will be kept"
    return None, "Unknown lot type; existing database type will be kept"


def write_csv(path: pathlib.Path, rows: list[dict[str, Any]], columns: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    key: json.dumps(value, ensure_ascii=False)
                    if isinstance(value, (dict, list))
                    else value
                    for key, value in row.items()
                }
            )


def _date_or_issue(
    raw: str,
    source: str,
    field: str,
    issues: list[dict[str, str]],
) -> str | None:
    parsed = parse_date(raw)
    if raw and parsed is None:
        issues.append(
            {
                "source": source,
                "lot_key": "",
                "category": "invalid_date",
                "detail": f"{field} retained only in raw metadata: {raw}",
                "action": "Review before relying on this date",
            }
        )
    return parsed


def segregate(
    source: pathlib.Path,
    excluded_blocks: set[str],
    included_blocks: set[str] | None = None,
    excluded_owner_keys: set[str] | None = None,
) -> dict[str, Any]:
    workbook = openpyxl.load_workbook(source, read_only=True, data_only=True)
    raw_lots: list[dict[str, Any]] = []
    issues: list[dict[str, str]] = []

    for sheet in workbook.worksheets:
        rows = sheet.iter_rows(values_only=True)
        first = next(rows, None)
        if first is None:
            continue
        headers = header_index(first)
        if not sheet.title.upper().startswith("BLOCK ") or compact("PLOT #") not in headers:
            continue
        sheet_block = normalize_block("", sheet.title)
        previous: dict[str, Any] | None = None
        for row_number, row in enumerate(rows, 2):
            if not any(text(item) for item in row):
                continue
            source_ref = f"{sheet.title}:{row_number}"
            plot_raw = cell(row, headers, "PLOT #")
            deceased = cell(row, headers, "DECEASED", "DECEASED (1st interment)")
            if not plot_raw:
                if deceased and previous is not None:
                    previous["burials"].append(
                        {
                            "source": source_ref,
                            "name": deceased,
                            "birth_date_raw": cell(row, headers, "BORN"),
                            "death_date_raw": cell(row, headers, "DIED"),
                            "interment_date_raw": cell(row, headers, "DATE OF INTERMENT"),
                        }
                    )
                else:
                    issues.append(
                        {
                            "source": source_ref,
                            "lot_key": "",
                            "category": "unassigned_row",
                            "detail": "Nonblank row has no plot number or attachable deceased name",
                            "action": "Review manually; not imported",
                        }
                    )
                continue

            block_raw = cell(row, headers, "BLOCK")
            block = normalize_block(block_raw, sheet.title)
            lot = normalize_lot(plot_raw)
            if block is None or lot is None:
                issues.append(
                    {
                        "source": source_ref,
                        "lot_key": "",
                        "category": "invalid_location",
                        "detail": f"Block={block_raw!r}; plot={plot_raw!r}",
                        "action": "Correct the source location before import",
                    }
                )
                previous = None
                continue

            raw_type = cell(row, headers, "LOT")
            mapped_type, type_issue = canonical_lot_type(raw_type)
            key = f"{block}:{lot}"
            record = {
                "source_key": f"lawn:{key}",
                "source": source_ref,
                "block_number": block,
                "lot_number": lot,
                "lot_label": f"{block}-{lot.zfill(3)}",
                "raw_lot_type": raw_type,
                "lot_class_type": mapped_type,
                "owner_name": cell(row, headers, "LOT OWNER/PURCHASER", "PURCHASER/OWNER"),
                "address": cell(row, headers, "ADDRESS"),
                "phone": cell(row, headers, "CONTACT", "CONTACT #", "CONTACT#"),
                "amount_raw": cell(row, headers, "AMOUNT"),
                "or_number": cell(row, headers, "OR #", "O.R#"),
                "purchase_date_raw": cell(row, headers, "DATE"),
                "register_status": cell(row, headers, "STATUS"),
                "burials": [],
            }
            if deceased:
                record["burials"].append(
                    {
                        "source": source_ref,
                        "name": deceased,
                        "birth_date_raw": cell(row, headers, "BORN"),
                        "death_date_raw": cell(row, headers, "DIED"),
                        "interment_date_raw": cell(row, headers, "DATE OF INTERMENT"),
                    }
                )
            if (
                included_blocks is not None
                and block not in included_blocks
                and sheet_block not in included_blocks
            ):
                previous = record
                continue
            if type_issue:
                issues.append(
                    {
                        "source": source_ref,
                        "lot_key": key,
                        "category": "lot_type_review",
                        "detail": f"{raw_type}: {type_issue}",
                        "action": "Lot remains importable; database type is not overwritten",
                    }
                )
            if block in excluded_blocks or sheet_block in excluded_blocks:
                issues.append(
                    {
                        "source": source_ref,
                        "lot_key": key,
                        "category": "excluded_block",
                        "detail": (
                            f"Sheet block {sheet_block} is already imported; "
                            f"raw row block was {block}"
                        ),
                        "action": "Excluded from this package",
                    }
                )
                previous = record
                continue
            raw_lots.append(record)
            previous = record

    grouped: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for row in raw_lots:
        grouped[row["source_key"]].append(row)

    lots: list[dict[str, Any]] = []
    for source_key, duplicates in sorted(grouped.items()):
        if len(duplicates) == 1:
            lots.append(duplicates[0])
            continue
        owner_keys = {normalize_name(row["owner_name"]) for row in duplicates if row["owner_name"]}
        types = {row["lot_class_type"] for row in duplicates if row["lot_class_type"]}
        if len(owner_keys) > 1 or len(types) > 1:
            issues.append(
                {
                    "source": ", ".join(row["source"] for row in duplicates),
                    "lot_key": source_key.removeprefix("lawn:"),
                    "category": "conflicting_duplicate",
                    "detail": "Duplicate lot rows have conflicting owners or lot types",
                    "action": "Excluded until manually resolved",
                }
            )
            continue
        merged = duplicates[0]
        for row in duplicates[1:]:
            merged["source"] += f", {row['source']}"
            merged["burials"].extend(row["burials"])
            for field in (
                "owner_name",
                "address",
                "phone",
                "amount_raw",
                "or_number",
                "purchase_date_raw",
                "register_status",
                "lot_class_type",
            ):
                if not merged[field] and row[field]:
                    merged[field] = row[field]
        issues.append(
            {
                "source": merged["source"],
                "lot_key": source_key.removeprefix("lawn:"),
                "category": "merged_duplicate",
                "detail": f"Merged {len(duplicates)} complementary source rows",
                "action": "Included as one database lot",
            }
        )
        lots.append(merged)

    owner_groups: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for lot in lots:
        if lot["owner_name"]:
            owner_groups[normalize_name(lot["owner_name"])].append(lot)

    owners: list[dict[str, Any]] = []
    owner_key_by_lot: dict[str, str] = {}
    excluded_owner_keys = excluded_owner_keys or set()
    for normalized_name, owner_lots in sorted(owner_groups.items()):
        import_key = f"lawn:owner:{stable_hash(normalized_name)}"
        phones = {compact(row["phone"]) for row in owner_lots if row["phone"]}
        if len(phones) > 1:
            issues.append(
                {
                    "source": ", ".join(row["source"] for row in owner_lots),
                    "lot_key": ", ".join(row["source_key"].removeprefix("lawn:") for row in owner_lots),
                    "category": "owner_identity_conflict",
                    "detail": (
                        "The same normalized owner name has multiple contact numbers; "
                        f"owner key {import_key}"
                    ),
                    "action": "Ownership rows excluded until identity is reviewed",
                }
            )
            continue
        if import_key in excluded_owner_keys:
            issues.append(
                {
                    "source": ", ".join(row["source"] for row in owner_lots),
                    "lot_key": ", ".join(
                        row["source_key"].removeprefix("lawn:") for row in owner_lots
                    ),
                    "category": "existing_owner_name_collision",
                    "detail": f"Database preview collision for owner key {import_key}",
                    "action": "Owner profile and ownership excluded; review identity manually",
                }
            )
            continue
        display_name = min((row["owner_name"] for row in owner_lots), key=len)
        if len(display_name) > 100:
            issues.append(
                {
                    "source": ", ".join(row["source"] for row in owner_lots),
                    "lot_key": ", ".join(
                        row["source_key"].removeprefix("lawn:") for row in owner_lots
                    ),
                    "category": "owner_name_too_long",
                    "detail": "Owner name exceeds the users.name limit of 100 characters",
                    "action": "Ownership rows excluded until the name is reviewed",
                }
            )
            continue
        selected_phone = next((row["phone"] for row in owner_lots if row["phone"]), "")
        if len(selected_phone) > 20:
            issues.append(
                {
                    "source": ", ".join(row["source"] for row in owner_lots),
                    "lot_key": ", ".join(
                        row["source_key"].removeprefix("lawn:") for row in owner_lots
                    ),
                    "category": "owner_phone_too_long",
                    "detail": "Contact value exceeds users.phone; preserved in lot metadata only",
                    "action": "Owner remains importable without a normalized phone",
                }
            )
            selected_phone = ""
        blocks = sorted({row["block_number"] for row in owner_lots}, key=lambda item: int(item))
        lot_labels = sorted(
            {row["lot_label"] for row in owner_lots},
            key=lambda item: tuple(int(part) for part in item.split("-")),
        )
        owner = {
            "import_key": import_key,
            "normalized_name": normalized_name,
            "name": display_name,
            "phone": selected_phone,
            "address": next((row["address"] for row in owner_lots if row["address"]), ""),
            "block_number": ", ".join(blocks),
            "lot_number": ", ".join(lot_labels),
            "number_of_lots": len(owner_lots),
        }
        owners.append(owner)
        for row in owner_lots:
            owner_key_by_lot[row["source_key"]] = import_key

    ownerships: list[dict[str, Any]] = []
    burials: list[dict[str, Any]] = []
    graves: list[dict[str, Any]] = []
    lot_exports: list[dict[str, Any]] = []
    for lot in lots:
        source_key = lot["source_key"]
        source_ref = lot["source"]
        purchase_date = _date_or_issue(
            lot["purchase_date_raw"], source_ref, "purchase date", issues
        )
        owner_import_key = owner_key_by_lot.get(source_key)
        details = {
            "source_workbook": source.name,
            "source_rows": source_ref,
            "owner_name": lot["owner_name"] or None,
            "address": lot["address"] or None,
            "contact_number": lot["phone"] or None,
            "amount_raw": lot["amount_raw"] or None,
            "or_number": lot["or_number"] or None,
            "purchase_date_raw": lot["purchase_date_raw"] or None,
            "register_status": lot["register_status"] or None,
            "raw_lot_type": lot["raw_lot_type"] or None,
        }
        lot_exports.append(
            {
                "source_key": source_key,
                "source": source_ref,
                "block_number": lot["block_number"],
                "lot_number": lot["lot_number"],
                "lot_label": lot["lot_label"],
                "lot_class_type": lot["lot_class_type"],
                "details_json": details,
            }
        )
        if owner_import_key:
            note_parts = [
                f"Register status: {lot['register_status']}" if lot["register_status"] else "",
                f"Amount: {lot['amount_raw']}" if lot["amount_raw"] else "",
                f"OR: {lot['or_number']}" if lot["or_number"] else "",
            ]
            ownerships.append(
                {
                    "import_key": f"lawn:ownership:{lot['block_number']}:{lot['lot_number']}",
                    "source_lot_key": source_key,
                    "owner_import_key": owner_import_key,
                    "start_date": purchase_date,
                    "purchase_note": "; ".join(part for part in note_parts if part),
                }
            )

        seen_burials: set[str] = set()
        for burial_row in lot["burials"]:
            for name in re.split(r"[/\n\r]+", burial_row["name"]):
                name = name.strip()
                normalized = normalize_name(name)
                if not normalized or normalized in seen_burials:
                    continue
                seen_burials.add(normalized)
                if len(name) > 100:
                    issues.append(
                        {
                            "source": burial_row["source"],
                            "lot_key": source_key.removeprefix("lawn:"),
                            "category": "deceased_name_too_long",
                            "detail": "Deceased name exceeds burial_record.name_of_deceased limit",
                            "action": "Burial excluded until the name is reviewed",
                        }
                    )
                    continue
                birth_date = _date_or_issue(
                    burial_row["birth_date_raw"], burial_row["source"], "birth date", issues
                )
                death_date = _date_or_issue(
                    burial_row["death_date_raw"], burial_row["source"], "death date", issues
                )
                interment_date = _date_or_issue(
                    burial_row["interment_date_raw"],
                    burial_row["source"],
                    "interment date",
                    issues,
                )
                import_key = (
                    f"lawn:burial:{lot['block_number']}:{lot['lot_number']}:"
                    f"{stable_hash(normalized)}"
                )
                burials.append(
                    {
                        "import_key": import_key,
                        "source_lot_key": source_key,
                        "name_of_deceased": name,
                        "normalized_name": normalized,
                        "birth_date": birth_date,
                        "death_date": death_date,
                        "interment_date": interment_date,
                        "registered_lot_owner": lot["owner_name"],
                        "registered_owner_contact_no": lot["phone"],
                        "lot_location_no": lot["lot_label"],
                        "burial_category": lot["lot_class_type"] or lot["raw_lot_type"],
                        "source": burial_row["source"],
                    }
                )
                graves.append(
                    {
                        "source_lot_key": source_key,
                        "burial_import_key": import_key,
                        "status": "Occupied",
                        "notes": (
                            "Imported from consolidated lawn register. "
                            "Individual grave position was not recorded."
                        ),
                    }
                )

    workbook.close()
    return {
        "lots": lot_exports,
        "owners": owners,
        "ownerships": ownerships,
        "burials": burials,
        "graves": graves,
        "issues": issues,
    }


def sql_literal(rows: list[dict[str, Any]], columns: list[tuple[str, str]]) -> str:
    payload = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    if "$lawn$" in payload:
        raise ValueError("Source data contains the SQL dollar-quote marker")
    definition = ", ".join(f"{name} {kind}" for name, kind in columns)
    return f"SELECT * FROM jsonb_to_recordset($lawn${payload}$lawn$::jsonb) AS r({definition})"


def sql_setup(data: dict[str, Any]) -> str:
    lot_columns = [
        ("source_key", "text"), ("source", "text"), ("block_number", "text"),
        ("lot_number", "text"), ("lot_label", "text"), ("lot_class_type", "text"),
        ("details_json", "jsonb"),
    ]
    owner_columns = [
        ("import_key", "text"), ("normalized_name", "text"), ("name", "text"),
        ("phone", "text"), ("address", "text"), ("block_number", "text"),
        ("lot_number", "text"), ("number_of_lots", "integer"),
    ]
    ownership_columns = [
        ("import_key", "text"), ("source_lot_key", "text"),
        ("owner_import_key", "text"), ("start_date", "date"), ("purchase_note", "text"),
    ]
    burial_columns = [
        ("import_key", "text"), ("source_lot_key", "text"),
        ("name_of_deceased", "text"), ("normalized_name", "text"),
        ("birth_date", "date"), ("death_date", "date"), ("interment_date", "date"),
        ("registered_lot_owner", "text"), ("registered_owner_contact_no", "text"),
        ("lot_location_no", "text"), ("burial_category", "text"), ("source", "text"),
    ]
    grave_columns = [
        ("source_lot_key", "text"), ("burial_import_key", "text"),
        ("status", "text"), ("notes", "text"),
    ]
    return f"""
CREATE TEMP TABLE lawn_lots ON COMMIT DROP AS {sql_literal(data['lots'], lot_columns)};
CREATE TEMP TABLE lawn_owners ON COMMIT DROP AS {sql_literal(data['owners'], owner_columns)};
CREATE TEMP TABLE lawn_ownerships ON COMMIT DROP AS {sql_literal(data['ownerships'], ownership_columns)};
CREATE TEMP TABLE lawn_burials ON COMMIT DROP AS {sql_literal(data['burials'], burial_columns)};
CREATE TEMP TABLE lawn_graves ON COMMIT DROP AS {sql_literal(data['graves'], grave_columns)};
CREATE TEMP TABLE lawn_matches ON COMMIT DROP AS
SELECT s.*, m.lot_id, m.matches
FROM lawn_lots s CROSS JOIN LATERAL (
  SELECT min(l.lot_id) AS lot_id, count(*)::integer AS matches
  FROM public.cemetery_lot l
  WHERE regexp_replace(upper(trim(coalesce(l.block_number,''))),'[^A-Z0-9]','','g') = s.block_number
    AND trim(l.lot_number) ~ '^0*[0-9]+$'
    AND coalesce(nullif(ltrim(trim(l.lot_number),'0'),''),'0') =
        coalesce(nullif(ltrim(s.lot_number,'0'),''),'0')
) m;
"""


def generate_sql(data: dict[str, Any], output: pathlib.Path) -> None:
    setup = sql_setup(data)
    preview = f"""-- Read-only preview. This transaction always rolls back.
BEGIN;
{setup}
SELECT matches, count(*) AS source_lots FROM lawn_matches GROUP BY matches ORDER BY matches;
SELECT block_number, count(*) AS source_lots,
  count(*) FILTER(WHERE matches=1) AS matched,
  count(*) FILTER(WHERE matches=0) AS not_found,
  count(*) FILTER(WHERE matches>1) AS ambiguous
FROM lawn_matches GROUP BY block_number ORDER BY block_number::integer;
SELECT source_key, source, matches FROM lawn_matches WHERE matches<>1 ORDER BY block_number::integer, lot_number::integer;
SELECT s.source_key, s.lot_class_type
FROM lawn_matches s LEFT JOIN public.lot_price_catalog c
  ON lower(c.lot_type)=lower(s.lot_class_type)
WHERE s.lot_class_type IS NOT NULL AND c.lot_type IS NULL;
SELECT o.import_key, count(u.user_id) AS existing_name_matches
FROM lawn_owners o LEFT JOIN public.users u
  ON regexp_replace(upper(trim(u.name)),'[^A-Z0-9]','','g')=o.normalized_name
 AND u.register_import_key IS DISTINCT FROM o.import_key
GROUP BY o.import_key HAVING count(u.user_id)>0;
SELECT ow.import_key, m.source_key, existing.ownership_id
FROM lawn_ownerships ow JOIN lawn_matches m ON m.source_key=ow.source_lot_key AND m.matches=1
JOIN public.lot_ownership existing ON existing.lot_id=m.lot_id;
SELECT
  (SELECT count(*) FROM lawn_matches) AS source_lots,
  (SELECT count(*) FROM lawn_matches WHERE matches=1) AS matched_lots,
  (SELECT count(*) FROM lawn_matches WHERE matches=0) AS not_found_lots,
  (SELECT count(*) FROM lawn_matches WHERE matches>1) AS ambiguous_lots,
  (SELECT count(*) FROM lawn_matches s LEFT JOIN public.lot_price_catalog c
    ON lower(c.lot_type)=lower(s.lot_class_type)
    WHERE s.lot_class_type IS NOT NULL AND c.lot_type IS NULL) AS unknown_catalog_types,
  (SELECT count(*) FROM lawn_owners o JOIN public.users u
    ON regexp_replace(upper(trim(u.name)),'[^A-Z0-9]','','g')=o.normalized_name
    AND u.register_import_key IS DISTINCT FROM o.import_key) AS owner_name_collisions,
  (SELECT coalesce(jsonb_agg(DISTINCT o.import_key),'[]'::jsonb)
   FROM lawn_owners o JOIN public.users u
    ON regexp_replace(upper(trim(u.name)),'[^A-Z0-9]','','g')=o.normalized_name
    AND u.register_import_key IS DISTINCT FROM o.import_key) AS owner_collision_keys,
  (SELECT count(*) FROM lawn_ownerships ow JOIN lawn_matches m
    ON m.source_key=ow.source_lot_key AND m.matches=1
    JOIN public.lot_ownership existing ON existing.lot_id=m.lot_id) AS existing_ownerships;
ROLLBACK;
"""

    expected_lots = len(data["lots"])
    apply = f"""-- Run 01_preview.sql first. This import is transactional and idempotent.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.cemetery_lot, public.users, public.lot_ownership,
  public.burial_record IN SHARE ROW EXCLUSIVE MODE;

CREATE SCHEMA IF NOT EXISTS private_lot_import;
REVOKE ALL ON SCHEMA private_lot_import FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private_lot_import.relational_backup(
  run_id timestamptz NOT NULL, table_name text NOT NULL, row_key text NOT NULL,
  row_data jsonb NOT NULL, PRIMARY KEY(run_id,table_name,row_key));
CREATE TABLE IF NOT EXISTS private_lot_import.created_rows(
  run_id timestamptz NOT NULL, table_name text NOT NULL, row_key text NOT NULL,
  PRIMARY KEY(run_id,table_name,row_key));

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.burial_record ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.lot_ownership ADD COLUMN IF NOT EXISTS register_import_key text;
ALTER TABLE public.lot_ownership ADD COLUMN IF NOT EXISTS purchase_note text;
CREATE UNIQUE INDEX IF NOT EXISTS users_register_import_key ON public.users(register_import_key);
CREATE UNIQUE INDEX IF NOT EXISTS burial_register_import_key ON public.burial_record(register_import_key);
CREATE UNIQUE INDEX IF NOT EXISTS ownership_register_import_key ON public.lot_ownership(register_import_key);
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL, ALTER COLUMN password DROP NOT NULL;
ALTER TABLE public.burial_record ALTER COLUMN death_date DROP NOT NULL;
ALTER TABLE public.lot_ownership ALTER COLUMN start_date DROP NOT NULL,
  ALTER COLUMN total_months DROP NOT NULL;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.users'::regclass AND conname='users_registered_credentials') THEN
    ALTER TABLE public.users ADD CONSTRAINT users_registered_credentials CHECK
      ((email IS NOT NULL AND password IS NOT NULL) OR (register_import_key IS NOT NULL AND role='lot_owner'));
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.burial_record'::regclass AND conname='burial_registered_death_date') THEN
    ALTER TABLE public.burial_record ADD CONSTRAINT burial_registered_death_date CHECK
      (death_date IS NOT NULL OR register_import_key IS NOT NULL);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.lot_ownership'::regclass AND conname='ownership_registered_terms') THEN
    ALTER TABLE public.lot_ownership ADD CONSTRAINT ownership_registered_terms CHECK
      ((start_date IS NOT NULL AND total_months IS NOT NULL) OR register_import_key IS NOT NULL);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.lot_register_details(
  lot_id integer PRIMARY KEY REFERENCES public.cemetery_lot(lot_id) ON DELETE CASCADE,
  details jsonb NOT NULL DEFAULT '{{}}'::jsonb);
ALTER TABLE public.lot_register_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lot_register_details FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.lot_register_details TO authenticated;
DROP POLICY IF EXISTS lot_register_admin_read ON public.lot_register_details;
CREATE POLICY lot_register_admin_read ON public.lot_register_details FOR SELECT TO authenticated
USING(EXISTS(SELECT 1 FROM public.users WHERE user_id=auth.uid() AND role='admin'));

CREATE TABLE IF NOT EXISTS public.graves(
  grave_id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  lot_id integer NOT NULL REFERENCES public.cemetery_lot(lot_id) ON DELETE CASCADE,
  grave_label text NOT NULL, status text NOT NULL DEFAULT 'Available',
  burial_id integer REFERENCES public.burial_record(burial_id) ON DELETE SET NULL,
  notes text, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(lot_id,grave_label));

{setup}
DO $$ BEGIN
  IF (SELECT count(*) FROM lawn_matches)<>{expected_lots} THEN
    RAISE EXCEPTION 'Expected {expected_lots} segregated lawn lots';
  END IF;
  IF EXISTS(SELECT 1 FROM lawn_matches WHERE matches<>1) THEN
    RAISE EXCEPTION 'Every source lot must match exactly one cemetery_lot; run preview';
  END IF;
  IF EXISTS(SELECT 1 FROM lawn_matches s LEFT JOIN public.lot_price_catalog c
      ON lower(c.lot_type)=lower(s.lot_class_type)
      WHERE s.lot_class_type IS NOT NULL AND c.lot_type IS NULL) THEN
    RAISE EXCEPTION 'A mapped lot type is absent from lot_price_catalog';
  END IF;
END $$;

INSERT INTO private_lot_import.relational_backup
SELECT transaction_timestamp(),'cemetery_lot',l.lot_id::text,to_jsonb(l)
FROM public.cemetery_lot l JOIN lawn_matches s USING(lot_id)
UNION ALL SELECT transaction_timestamp(),'lot_register_details',d.lot_id::text,to_jsonb(d)
FROM public.lot_register_details d JOIN lawn_matches s USING(lot_id)
UNION ALL SELECT transaction_timestamp(),'lot_ownership',o.ownership_id::text,to_jsonb(o)
FROM public.lot_ownership o JOIN lawn_matches s USING(lot_id)
UNION ALL SELECT transaction_timestamp(),'burial_record',b.burial_id::text,to_jsonb(b)
FROM public.burial_record b JOIN lawn_matches s USING(lot_id)
UNION ALL SELECT transaction_timestamp(),'graves',g.grave_id::text,to_jsonb(g)
FROM public.graves g JOIN lawn_matches s USING(lot_id);

WITH inserted AS(
  INSERT INTO public.lot_register_details(lot_id,details)
  SELECT lot_id,details_json FROM lawn_matches
  ON CONFLICT(lot_id) DO UPDATE SET details=public.lot_register_details.details||excluded.details
  RETURNING lot_id)
SELECT count(*) FROM inserted;
UPDATE public.cemetery_lot l SET lot_class_type=s.lot_class_type
FROM lawn_matches s WHERE s.lot_id=l.lot_id AND s.lot_class_type IS NOT NULL
AND l.lot_class_type IS DISTINCT FROM s.lot_class_type;

ALTER TABLE lawn_owners ADD COLUMN mapped_user_id uuid;
UPDATE lawn_owners s SET mapped_user_id=u.user_id FROM public.users u
WHERE u.register_import_key=s.import_key;
UPDATE lawn_owners s SET mapped_user_id=u.user_id
FROM lawn_ownerships ow JOIN lawn_matches m ON m.source_key=ow.source_lot_key
JOIN public.lot_ownership existing ON existing.lot_id=m.lot_id
JOIN public.users u ON u.user_id=existing.user_id
WHERE ow.owner_import_key=s.import_key
AND regexp_replace(upper(trim(u.name)),'[^A-Z0-9]','','g')=s.normalized_name;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM lawn_owners s JOIN public.users u
    ON regexp_replace(upper(trim(u.name)),'[^A-Z0-9]','','g')=s.normalized_name
    WHERE u.register_import_key IS DISTINCT FROM s.import_key
      AND u.user_id IS DISTINCT FROM s.mapped_user_id) THEN
    RAISE EXCEPTION 'Existing owner name collision requires review';
  END IF;
END $$;
WITH inserted AS(
  INSERT INTO public.users(name,phone,address,role,register_import_key,
    block_number,lot_number,number_of_lots)
  SELECT name,nullif(phone,''),nullif(address,''),'lot_owner',import_key,
    block_number,lot_number,number_of_lots FROM lawn_owners WHERE mapped_user_id IS NULL
  ON CONFLICT(register_import_key) DO NOTHING RETURNING user_id)
INSERT INTO private_lot_import.created_rows
SELECT transaction_timestamp(),'users',user_id::text FROM inserted;
UPDATE lawn_owners s SET mapped_user_id=u.user_id FROM public.users u
WHERE s.mapped_user_id IS NULL AND u.register_import_key=s.import_key;

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM lawn_ownerships s JOIN lawn_matches m ON m.source_key=s.source_lot_key
    JOIN public.lot_ownership existing ON existing.lot_id=m.lot_id
    JOIN lawn_owners owner ON owner.import_key=s.owner_import_key
    WHERE existing.user_id IS DISTINCT FROM owner.mapped_user_id) THEN
    RAISE EXCEPTION 'Existing lot ownership conflicts with lawn register';
  END IF;
END $$;
WITH inserted AS(
  INSERT INTO public.lot_ownership(lot_id,user_id,start_date,total_months,
    months_paid,status,purchase_note,register_import_key)
  SELECT m.lot_id,o.mapped_user_id,s.start_date,NULL,NULL,NULL,
    nullif(s.purchase_note,''),s.import_key
  FROM lawn_ownerships s JOIN lawn_matches m ON m.source_key=s.source_lot_key
  JOIN lawn_owners o ON o.import_key=s.owner_import_key
  ON CONFLICT(lot_id) DO NOTHING RETURNING ownership_id)
INSERT INTO private_lot_import.created_rows
SELECT transaction_timestamp(),'lot_ownership',ownership_id::text FROM inserted;

ALTER TABLE lawn_burials ADD COLUMN mapped_burial_id integer;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM lawn_burials s JOIN lawn_matches m ON m.source_key=s.source_lot_key
    JOIN public.burial_record b ON b.lot_id=m.lot_id
      AND regexp_replace(upper(trim(b.name_of_deceased)),'[^A-Z0-9]','','g')=s.normalized_name
    GROUP BY s.import_key HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Multiple existing burials match one source burial';
  END IF;
  IF EXISTS(SELECT 1 FROM lawn_burials WHERE length(name_of_deceased)>100) THEN
    RAISE EXCEPTION 'A deceased name exceeds 100 characters';
  END IF;
END $$;
UPDATE lawn_burials s SET mapped_burial_id=b.burial_id
FROM lawn_matches m JOIN public.burial_record b ON b.lot_id=m.lot_id
WHERE m.source_key=s.source_lot_key
AND regexp_replace(upper(trim(b.name_of_deceased)),'[^A-Z0-9]','','g')=s.normalized_name;
UPDATE lawn_burials s SET mapped_burial_id=b.burial_id FROM public.burial_record b
WHERE s.mapped_burial_id IS NULL AND b.register_import_key=s.import_key;
WITH inserted AS(
  INSERT INTO public.burial_record(name_of_deceased,birth_date,death_date,
    burial_date,interment_date,lot_id,registered_lot_owner,
    registered_owner_contact_no,lot_location_no,burial_category,
    death_certificate_submitted,ownership_certificate_submitted,
    authority_document_submitted,register_import_key)
  SELECT s.name_of_deceased,s.birth_date,s.death_date,s.interment_date,
    s.interment_date,m.lot_id,nullif(s.registered_lot_owner,''),
    nullif(s.registered_owner_contact_no,''),s.lot_location_no,
    nullif(s.burial_category,''),true,true,true,s.import_key
  FROM lawn_burials s JOIN lawn_matches m ON m.source_key=s.source_lot_key
  WHERE s.mapped_burial_id IS NULL
  ON CONFLICT(register_import_key) DO NOTHING RETURNING burial_id)
INSERT INTO private_lot_import.created_rows
SELECT transaction_timestamp(),'burial_record',burial_id::text FROM inserted;
UPDATE lawn_burials s SET mapped_burial_id=b.burial_id FROM public.burial_record b
WHERE s.mapped_burial_id IS NULL AND b.register_import_key=s.import_key;
WITH inserted AS(
  INSERT INTO public.graves(lot_id,grave_label,status,burial_id,notes)
  SELECT m.lot_id,'Register '||b.mapped_burial_id,g.status,b.mapped_burial_id,g.notes
  FROM lawn_graves g JOIN lawn_matches m ON m.source_key=g.source_lot_key
  JOIN lawn_burials b ON b.import_key=g.burial_import_key
  WHERE NOT EXISTS(SELECT 1 FROM public.graves existing WHERE existing.burial_id=b.mapped_burial_id)
  RETURNING grave_id)
INSERT INTO private_lot_import.created_rows
SELECT transaction_timestamp(),'graves',grave_id::text FROM inserted;

UPDATE public.cemetery_lot l SET status=CASE
  WHEN EXISTS(SELECT 1 FROM public.burial_record b WHERE b.lot_id=l.lot_id) THEN 'Occupied'
  WHEN EXISTS(SELECT 1 FROM public.lot_ownership o WHERE o.lot_id=l.lot_id) THEN 'Reserved'
  ELSE l.status END
WHERE l.lot_id IN(SELECT lot_id FROM lawn_matches);

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM lawn_burials WHERE mapped_burial_id IS NULL) THEN
    RAISE EXCEPTION 'Burial import verification failed';
  END IF;
  IF EXISTS(SELECT 1 FROM lawn_burials b JOIN lawn_matches m ON m.source_key=b.source_lot_key
    WHERE NOT EXISTS(SELECT 1 FROM public.graves g
      WHERE g.burial_id=b.mapped_burial_id AND g.lot_id=m.lot_id)) THEN
    RAISE EXCEPTION 'Grave link verification failed';
  END IF;
END $$;
SELECT pg_notify('pgrst','reload schema');
SELECT transaction_timestamp() AS backup_run_id,
  (SELECT count(*) FROM lawn_matches) AS matched_lots,
  (SELECT count(*) FROM lawn_owners) AS owner_profiles,
  (SELECT count(*) FROM lawn_ownerships) AS ownerships,
  (SELECT count(*) FROM lawn_burials) AS burials,
  (SELECT count(*) FROM lawn_graves) AS graves;
COMMIT;
"""

    validate = """SELECT
  count(*) FILTER(WHERE register_import_key LIKE 'lawn:owner:%') AS lawn_owner_profiles
FROM public.users;
SELECT count(*) AS lawn_ownerships FROM public.lot_ownership
WHERE register_import_key LIKE 'lawn:ownership:%';
SELECT count(*) AS lawn_burials FROM public.burial_record
WHERE register_import_key LIKE 'lawn:burial:%';
SELECT count(*) AS broken_grave_links FROM public.burial_record b
WHERE b.register_import_key LIKE 'lawn:burial:%'
AND NOT EXISTS(SELECT 1 FROM public.graves g WHERE g.burial_id=b.burial_id AND g.lot_id=b.lot_id);
"""
    rollback = """-- Recovery template. Set the exact backup_run_id returned by 02_import.sql.
BEGIN;
DO $$ BEGIN RAISE EXCEPTION 'Set backup_run_id and remove this guard before rollback'; END $$;
SET LOCAL lock_timeout='10s';
CREATE TEMP TABLE rollback_run(run_id timestamptz) ON COMMIT DROP;
INSERT INTO rollback_run VALUES('2000-01-01T00:00:00Z');
DELETE FROM public.graves g USING private_lot_import.created_rows c,rollback_run r
WHERE c.run_id=r.run_id AND c.table_name='graves' AND g.grave_id::text=c.row_key;
DELETE FROM public.burial_record b USING private_lot_import.created_rows c,rollback_run r
WHERE c.run_id=r.run_id AND c.table_name='burial_record' AND b.burial_id::text=c.row_key;
DELETE FROM public.lot_ownership o USING private_lot_import.created_rows c,rollback_run r
WHERE c.run_id=r.run_id AND c.table_name='lot_ownership' AND o.ownership_id::text=c.row_key;
DELETE FROM public.users u USING private_lot_import.created_rows c,rollback_run r
WHERE c.run_id=r.run_id AND c.table_name='users' AND u.user_id::text=c.row_key
AND NOT EXISTS(SELECT 1 FROM public.lot_ownership o WHERE o.user_id=u.user_id);
UPDATE public.cemetery_lot l SET
  lot_class_type=b.row_data->>'lot_class_type',
  pricing_type=b.row_data->>'pricing_type',
  price=(b.row_data->>'price')::numeric,
  status=b.row_data->>'status'
FROM private_lot_import.relational_backup b,rollback_run r
WHERE b.run_id=r.run_id AND b.table_name='cemetery_lot' AND l.lot_id::text=b.row_key;
DELETE FROM public.lot_register_details d USING rollback_run r
WHERE NOT EXISTS(SELECT 1 FROM private_lot_import.relational_backup b
  WHERE b.run_id=r.run_id AND b.table_name='lot_register_details' AND b.row_key=d.lot_id::text)
AND d.lot_id IN(SELECT row_key::integer FROM private_lot_import.relational_backup b
  WHERE b.run_id=r.run_id AND b.table_name='cemetery_lot');
UPDATE public.lot_register_details d SET details=(b.row_data->'details')
FROM private_lot_import.relational_backup b,rollback_run r
WHERE b.run_id=r.run_id AND b.table_name='lot_register_details' AND d.lot_id::text=b.row_key;
COMMIT;
"""
    (output / "01_preview.sql").write_text(preview, encoding="utf-8")
    (output / "02_import.sql").write_text(apply, encoding="utf-8")
    (output / "03_validate.sql").write_text(validate, encoding="utf-8")
    (output / "04_rollback.sql").write_text(rollback, encoding="utf-8")


def generate_identity_reconciliation(data: dict[str, Any], output: pathlib.Path) -> None:
    keys = sorted(
        {
            match.group(1)
            for issue in data["issues"]
            if issue["category"] == "owner_identity_conflict"
            for match in [re.search(r"(lawn:owner:[a-f0-9]+)", issue["detail"])]
            if match is not None
        }
    )
    if not keys:
        return
    quoted = ",".join("'" + key + "'" for key in keys)
    sql = f"""-- Removes uncertain ownership links for global same-name/contact conflicts.
-- Raw register metadata and burial evidence are preserved for manual review.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.users,public.lot_ownership,public.cemetery_lot
  IN SHARE ROW EXCLUSIVE MODE;
CREATE TABLE IF NOT EXISTS private_lot_import.identity_conflict_backup(
  run_id timestamptz NOT NULL, table_name text NOT NULL, row_key text NOT NULL,
  row_data jsonb NOT NULL, PRIMARY KEY(run_id,table_name,row_key));
CREATE TEMP TABLE affected_ownerships ON COMMIT DROP AS
SELECT o.* FROM public.lot_ownership o JOIN public.users u USING(user_id)
WHERE u.register_import_key IN ({quoted})
  AND o.register_import_key LIKE 'lawn:ownership:%';
INSERT INTO private_lot_import.identity_conflict_backup
SELECT transaction_timestamp(),'lot_ownership',ownership_id::text,to_jsonb(a)
FROM affected_ownerships a
UNION ALL
SELECT transaction_timestamp(),'users',u.user_id::text,to_jsonb(u)
FROM public.users u WHERE u.register_import_key IN ({quoted});
DELETE FROM public.lot_ownership o USING affected_ownerships a
WHERE o.ownership_id=a.ownership_id;
UPDATE public.cemetery_lot l SET status=CASE
  WHEN EXISTS(SELECT 1 FROM public.burial_record b WHERE b.lot_id=l.lot_id) THEN 'Occupied'
  WHEN EXISTS(SELECT 1 FROM public.lot_ownership o WHERE o.lot_id=l.lot_id) THEN 'Reserved'
  ELSE 'Available' END
WHERE l.lot_id IN(SELECT lot_id FROM affected_ownerships);
DELETE FROM public.users u WHERE u.register_import_key IN ({quoted})
AND NOT EXISTS(SELECT 1 FROM public.lot_ownership o WHERE o.user_id=u.user_id);
SELECT transaction_timestamp() AS reconciliation_run_id,
  (SELECT count(*) FROM affected_ownerships) AS removed_uncertain_ownerships;
COMMIT;
"""
    (output / "05_reconcile_identity_conflicts.sql").write_text(sql, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument(
        "--exclude-block",
        action="append",
        default=["36"],
        help="Block already imported; may be repeated (default: 36)",
    )
    parser.add_argument(
        "--include-block",
        action="append",
        help="Generate a package only for this normalized block; may be repeated",
    )
    parser.add_argument(
        "--exclude-owner-key",
        action="append",
        help="Owner import key flagged by the database preview; may be repeated",
    )
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    included_blocks = set(args.include_block) if args.include_block else None
    data = segregate(
        args.source,
        set(args.exclude_block),
        included_blocks,
        set(args.exclude_owner_key or []),
    )
    schemas = {
        "lots": ["source_key", "source", "block_number", "lot_number", "lot_label", "lot_class_type", "details_json"],
        "owners": ["import_key", "normalized_name", "name", "phone", "address", "block_number", "lot_number", "number_of_lots"],
        "ownerships": ["import_key", "source_lot_key", "owner_import_key", "start_date", "purchase_note"],
        "burials": ["import_key", "source_lot_key", "name_of_deceased", "normalized_name", "birth_date", "death_date", "interment_date", "registered_lot_owner", "registered_owner_contact_no", "lot_location_no", "burial_category", "source"],
        "graves": ["source_lot_key", "burial_import_key", "status", "notes"],
        "issues": ["source", "lot_key", "category", "detail", "action"],
    }
    filenames = {
        "lots": "cemetery_lot_matches.csv",
        "owners": "users_lot_owners.csv",
        "ownerships": "lot_ownership.csv",
        "burials": "burial_record.csv",
        "graves": "graves.csv",
        "issues": "review_exceptions.csv",
    }
    for key, filename in filenames.items():
        write_csv(args.output / filename, data[key], schemas[key])
    generate_sql(data, args.output)
    generate_identity_reconciliation(data, args.output)
    summary = {
        "source_workbook": args.source.name,
        "excluded_blocks": sorted(set(args.exclude_block)),
        "included_blocks": sorted(included_blocks) if included_blocks else "all remaining",
        "cemetery_lot_matches": len(data["lots"]),
        "users_lot_owners": len(data["owners"]),
        "lot_ownership": len(data["ownerships"]),
        "burial_record": len(data["burials"]),
        "graves": len(data["graves"]),
        "review_exceptions": len(data["issues"]),
        "live_database_changes": 0,
    }
    (args.output / "summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    (args.output / "README.txt").write_text(
        """Lawn-lot database import package (contains personal data)

1. Review summary.json, review_exceptions.csv, and the database-shaped CSVs.
2. Run 01_preview.sql in the Supabase SQL Editor. It always rolls back.
3. Resolve every unmatched/ambiguous lot and owner/ownership conflict.
4. Run 02_import.sql only after the preview is clean. Save backup_run_id.
5. Run 03_validate.sql. Use 04_rollback.sql only for deliberate recovery.

Block 36 is excluded because it was previously imported. Blank or ambiguous
values are not invented. Raw register values remain in admin-only lot metadata.
No payment transactions are created from status/amount text.
""",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
