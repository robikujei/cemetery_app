from __future__ import annotations

import re
import sys
import unicodedata
from datetime import date, datetime
from pathlib import Path

import openpyxl


WORKBOOK = Path("COFFIN CRYPT - 2nd CYCLE(AutoRecovered).xlsx")
OUTPUT = Path("supabase/import_apartment_crypt_records.sql")

SHEET_MOUNTAINS = {
    "1A-COVID": "Mt. Abarim",
    "2-MT. ARARAT": "Mt. Ararat",
    "3-MT. BASHAN": "Mt. Bashan",
    "4-MT. CARMEL": "Mt. Carmel",
    "5-MT. EBAL": "Mt. Ebal",
    "6-MT. GERIZIM": "Mt. Gerizim",
    "7-GILBOA": "Mt. Gilboa",
    "8-GILIAD": "Mt. Giliad",
    "9-MT. HERMON": "Mt. Hermon",
    "10-MT. HOR": "Mt. Hor",
    "11-MT. HOREB": "Mt. Horeb",
    "12-MT. LEBANON": "Mt. Lebanon",
    "13-MT. MORIAH": "Mt. Moriah",
    "14-MT. MERON": "Mt. Meron",
    "15-MT. NEBO": "Mt. Nebo",
    "16-MT. OLIVET": "Mt. Olivet",
    "17-MT. ZURIEL": "Mt. Zuriel",
    "18-MT. ZION": "Mt. Zion",
    "19-MT.ZEMARAIM": "Mt. Zemaraim",
    "20-MT. TABOR": "Mt. Tabor",
    "21-MT. SINAI": "Mt. Sinai",
    "22-MT. SEIR": "Mt. Seir",
}

MOUNTAIN_ALIASES = {
    "abarim": "Mt. Abarim", "ararat": "Mt. Ararat",
    "bashan": "Mt. Bashan", "carmel": "Mt. Carmel",
    "ebal": "Mt. Ebal", "gerizim": "Mt. Gerizim",
    "gilboa": "Mt. Gilboa", "giliad": "Mt. Giliad",
    "gilead": "Mt. Giliad", "hermon": "Mt. Hermon",
    "horeb": "Mt. Horeb", "lebanon": "Mt. Lebanon",
    "moriah": "Mt. Moriah", "meron": "Mt. Meron",
    "nebo": "Mt. Nebo", "olivet": "Mt. Olivet",
    "zuriel": "Mt. Zuriel", "zion": "Mt. Zion",
    "zemaraim": "Mt. Zemaraim", "tabor": "Mt. Tabor",
    "sinai": "Mt. Sinai", "seir": "Mt. Seir",
}

HEADER_ALIASES = {
    "building": {"block no.", "bldg.", "bldg. no./name"},
    "level": {"level", "level no."},
    "niche": {"niche no."},
    "or_number": {"o. r. #", "o.r. #"},
    "application_date": {"date of application", "date of application & or", "date"},
    "lessee": {"name of lessee"},
    "deceased": {"name of deceased"},
    "contact": {"contact number"},
    "address": {"address"},
    "amount": {"amount"},
    "birth_date": {"born"},
    "death_date": {"died"},
    "interment_date": {"interment date", "date of interment"},
    "remarks": {"remarks"},
}


def clean(value: object) -> str:
    if value is None:
        return ""
    text = unicodedata.normalize("NFKC", str(value)).strip()
    return re.sub(r"\s+", " ", text)


def sql(value: object) -> str:
    text = clean(value)
    return "null" if not text else "'" + text.replace("'", "''") + "'"


def iso_date(value: object) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    text = clean(value)
    if not text:
        return ""
    for pattern in (r"^(\d{1,2})/(\d{1,2})/(\d{2,4})$", r"^(\d{1,2})-(\d{1,2})-(\d{2,4})$"):
        match = re.match(pattern, text)
        if match:
            month, day, year = map(int, match.groups())
            year += 2000 if year < 40 else 1900 if year < 100 else 0
            try:
                return date(year, month, day).isoformat()
            except ValueError:
                return ""
    return ""


def mountain_from_building(building: str, fallback: str) -> str:
    lowered = building.lower()
    for alias, mountain in MOUNTAIN_ALIASES.items():
        if re.search(rf"\b{re.escape(alias)}\b", lowered):
            return mountain
    return fallback


def wing_from_building(building: str) -> str:
    match = re.search(r"(?:^|\d|\s|-)([ab])(?:\s|-|$)", building.lower())
    return match.group(1).upper() if match else ""


def slot_from_niche(value: object) -> int | None:
    text = clean(value)
    match = re.search(r"\d+", text)
    if not match:
        return None
    number = int(match.group())
    if 1 <= number <= 100:
        return number
    slot = number % 100
    return 100 if slot == 0 else slot


def find_header(rows: list[tuple[object, ...]]) -> int | None:
    for index, row in enumerate(rows):
        values = {clean(value).lower() for value in row}
        if "niche no." in values and "name of deceased" in values:
            return index
    return None


def column_map(header: tuple[object, ...]) -> dict[str, int]:
    normalized = [clean(value).lower() for value in header]
    result: dict[str, int] = {}
    for field, aliases in HEADER_ALIASES.items():
        for index, value in enumerate(normalized):
            if value in aliases:
                result[field] = index
                break
    return result


def cell(row: tuple[object, ...], columns: dict[str, int], field: str) -> object:
    index = columns.get(field)
    return None if index is None or index >= len(row) else row[index]


def main() -> int:
    workbook = openpyxl.load_workbook(WORKBOOK, data_only=True, read_only=True)
    records: dict[tuple[str, str, int], dict[str, object]] = {}
    conflicts: list[str] = []

    for sheet_name, fallback_mountain in SHEET_MOUNTAINS.items():
        worksheet = workbook[sheet_name]
        rows = list(worksheet.iter_rows(values_only=True))
        header_index = find_header(rows)
        if header_index is None:
            continue
        columns = column_map(rows[header_index])
        niche_ordinal = 0
        for row_number, row in enumerate(rows[header_index + 1 :], header_index + 2):
            building = clean(cell(row, columns, "building"))
            mountain = mountain_from_building(building, fallback_mountain)
            wing = wing_from_building(building)
            slot = slot_from_niche(cell(row, columns, "niche"))
            if slot is not None:
                # Some legacy sheets omit the building value for an entire
                # wing. Their rows are still laid out as 100 A faces followed
                # by 100 B faces, so use that stable workbook position only
                # when the explicit building field provides no wing.
                if not wing and not building and niche_ordinal < 200:
                    wing = "A" if niche_ordinal < 100 else "B"
                niche_ordinal += 1
            deceased = clean(cell(row, columns, "deceased"))
            if not deceased:
                continue
            if wing not in {"A", "B"} or slot is None or not 1 <= slot <= 100:
                conflicts.append(f"{sheet_name}:{row_number}: invalid wing/slot ({building!r}, {cell(row, columns, 'niche')!r})")
                continue
            key = (mountain, wing, slot)
            record = {
                "mountain": mountain,
                "wing": wing,
                "slot": slot,
                "building": building,
                "level": clean(cell(row, columns, "level")),
                "niche": clean(cell(row, columns, "niche")),
                "or_number": clean(cell(row, columns, "or_number")),
                "application_date": iso_date(cell(row, columns, "application_date")),
                "lessee": clean(cell(row, columns, "lessee")),
                "deceased": deceased,
                "contact": clean(cell(row, columns, "contact")),
                "address": clean(cell(row, columns, "address")),
                "amount": clean(cell(row, columns, "amount")),
                "birth_date": iso_date(cell(row, columns, "birth_date")),
                "death_date": iso_date(cell(row, columns, "death_date")),
                "interment_date": iso_date(cell(row, columns, "interment_date")),
                "remarks": clean(cell(row, columns, "remarks")),
                "source": f"{sheet_name}:{row_number}",
            }
            if key in records and records[key]["deceased"].lower() != deceased.lower():
                conflicts.append(f"{sheet_name}:{row_number}: duplicate {key} ({records[key]['deceased']!r} vs {deceased!r})")
                continue
            records[key] = record

    mountains = list(dict.fromkeys(SHEET_MOUNTAINS.values()))
    lines = [
        "-- Generated by tools/prepare_crypt_import.py.",
        "-- Mountain names are the synchronization key. Review the conflict report before running.",
        "begin;",
        "update public.cemetery_lot set lot_label = 'Mt. Ararat' where block_number = '0' and lot_number = '0065' and coalesce(trim(lot_label),'') in ('', '0-0065');",
        "create temp table crypt_mountains (mountain text primary key);",
        "insert into crypt_mountains(mountain) values " + ",".join(f"({sql(m)})" for m in mountains) + ";",
        "do $$ begin if exists (select 1 from crypt_mountains m left join public.cemetery_lot l on lower(trim(l.lot_label)) = lower(m.mountain) and l.block_number = '0' group by m.mountain having count(l.lot_id) <> 1) then raise exception 'Every workbook mountain must match exactly one Block 0 lot label'; end if; end $$;",
        "insert into public.graves(lot_id, grave_label, status, notes)",
        "select l.lot_id, w.wing || '-' || lpad(s.slot::text,3,'0'), 'Available', 'Crypt grid initialized from workbook'",
        "from crypt_mountains m join public.cemetery_lot l on lower(trim(l.lot_label))=lower(m.mountain) and l.block_number='0' cross join (values ('A'),('B')) w(wing) cross join generate_series(1,100) s(slot)",
        "on conflict (lot_id, grave_label) do nothing;",
        "create temp table crypt_import (mountain text, wing text, slot int, building text, level text, niche text, or_number text, application_date date, lessee text, deceased text, contact text, address text, amount numeric, birth_date date, death_date date, interment_date date, remarks text, source text, import_key text primary key);",
    ]
    values = []
    for record in sorted(records.values(), key=lambda r: (str(r["mountain"]), str(r["wing"]), int(r["slot"]))):
        amount = re.sub(r"[^0-9.]", "", str(record["amount"]))
        amount_sql = amount if amount and re.fullmatch(r"\d+(?:\.\d+)?", amount) else "null"
        key = f"crypt:{str(record['mountain']).lower().replace(' ', '-')}:" f"{record['wing']}:{int(record['slot']):03d}"
        values.append("(" + ",".join([
            sql(record["mountain"]), sql(record["wing"]), str(record["slot"]), sql(record["building"]),
            sql(record["level"]), sql(record["niche"]), sql(record["or_number"]), sql(record["application_date"]),
            sql(record["lessee"]), sql(record["deceased"]), sql(record["contact"]), sql(record["address"]),
            amount_sql, sql(record["birth_date"]), sql(record["death_date"]), sql(record["interment_date"]),
            sql(record["remarks"]), sql(record["source"]), sql(key),
        ]) + ")")
    lines.append("insert into crypt_import values\n" + ",\n".join(values) + ";")
    lines.extend([
        "insert into public.burial_informants(full_name,address,cellphone_no)",
        "select distinct i.lessee, nullif(i.address,''), nullif(i.contact,'') from crypt_import i where nullif(trim(i.lessee),'') is not null and not exists (select 1 from public.burial_informants b where lower(trim(b.full_name))=lower(trim(i.lessee)) and coalesce(b.cellphone_no,'')=coalesce(nullif(i.contact,''),''));",
        "insert into public.burial_record(name_of_deceased,birth_date,death_date,burial_date,lot_id,application_date,informant_id,interment_date,burial_category,bldg_no,niche_no,level,lot_location_no,registered_lot_owner,registered_owner_contact_no,interment_or_number,interment_total,interment_payment_date,death_certificate_submitted,ownership_certificate_submitted,authority_document_submitted,register_import_key)",
        "select i.deceased,i.birth_date,i.death_date,i.interment_date,l.lot_id,i.application_date,(select b.informant_id from public.burial_informants b where lower(trim(b.full_name))=lower(trim(i.lessee)) and coalesce(b.cellphone_no,'')=coalesce(nullif(i.contact,''),'') order by b.informant_id limit 1),i.interment_date,'Apartment Crypt',i.building,i.niche,i.level,i.wing||'-'||lpad(i.slot::text,3,'0'),i.lessee,i.contact,i.or_number,i.amount,i.application_date,true,true,true,i.import_key from crypt_import i join public.cemetery_lot l on lower(trim(l.lot_label))=lower(i.mountain) and l.block_number='0'",
        "on conflict (register_import_key) do update set name_of_deceased=excluded.name_of_deceased,birth_date=excluded.birth_date,death_date=excluded.death_date,burial_date=excluded.burial_date,lot_id=excluded.lot_id,application_date=excluded.application_date,informant_id=excluded.informant_id,interment_date=excluded.interment_date,bldg_no=excluded.bldg_no,niche_no=excluded.niche_no,level=excluded.level,lot_location_no=excluded.lot_location_no,registered_lot_owner=excluded.registered_lot_owner,registered_owner_contact_no=excluded.registered_owner_contact_no,interment_or_number=excluded.interment_or_number,interment_total=excluded.interment_total,interment_payment_date=excluded.interment_payment_date,death_certificate_submitted=true,ownership_certificate_submitted=true,authority_document_submitted=true;",
        "update public.graves g set burial_id=b.burial_id,status='Occupied',notes='Imported from '||i.source from crypt_import i join public.cemetery_lot l on lower(trim(l.lot_label))=lower(i.mountain) and l.block_number='0' join public.burial_record b on b.register_import_key=i.import_key where g.lot_id=l.lot_id and g.grave_label=i.wing||'-'||lpad(i.slot::text,3,'0');",
        "update public.cemetery_lot l set status='Occupied' where exists(select 1 from public.graves g where g.lot_id=l.lot_id and g.status='Occupied');",
        "commit;",
        "select l.lot_number,l.lot_label,count(g.*) faces,count(g.*) filter(where g.status='Occupied') occupied from public.cemetery_lot l left join public.graves g on g.lot_id=l.lot_id where l.block_number='0' and exists(select 1 from crypt_mountains m where lower(m.mountain)=lower(trim(l.lot_label))) group by l.lot_number,l.lot_label order by l.lot_number;",
    ])
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    conflict_path = OUTPUT.with_suffix(".conflicts.txt")
    conflict_path.write_text("\n".join(conflicts) + ("\n" if conflicts else ""), encoding="utf-8")
    print(f"Prepared {len(records)} occupied crypt records across {len(mountains)} mountains.")
    print(f"Conflicts excluded: {len(conflicts)} ({conflict_path})")
    print(f"SQL: {OUTPUT}")
    return 0 if not conflicts else 2


if __name__ == "__main__":
    sys.exit(main())
