"""Segregate the remaining crypt and lawn-lot workbooks into reviewable CSVs.

Usage:
  python tools/segregate_remaining_registers.py crypt.xlsx lawn.xlsx output_directory

The output contains personal data. Use a folder outside the Git repository and
review the manifest before any database import. Source values are retained as
text; this tool deliberately does not invent dates, payment states, or links.
"""
import csv
import json
import pathlib
import re
import sys

import openpyxl


def value(item):
    """Make a cell safe for CSV without converting a date to a locale string."""
    if item is None:
        return ""
    if hasattr(item, "isoformat"):
        return item.isoformat()
    return str(item).strip()


def compact(text):
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def nonempty(row):
    return any(value(cell) for cell in row)


def write_csv(path, rows, columns):
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def header_index(row):
    return {compact(value(cell)): position for position, cell in enumerate(row) if value(cell)}


def cell(row, headers, *aliases):
    for alias in aliases:
        position = headers.get(compact(alias))
        if position is not None and position < len(row):
            return value(row[position])
    return ""


def crypt_rows(book):
    records, skipped = [], []
    for sheet in book.worksheets:
        rows = list(sheet.iter_rows(values_only=True))
        header_at = next((i for i, row in enumerate(rows[:5])
                          if any(compact(value(v)) in {"nicheno", "nichenumber"} for v in row)), None)
        if header_at is None:
            skipped.append({"source_sheet": sheet.title, "reason": "No niche-register header"})
            continue
        headers = header_index(rows[header_at])
        for row_number, row in enumerate(rows[header_at + 1:], header_at + 2):
            if not nonempty(row):
                continue
            niche = cell(row, headers, "Niche No.", "Niche Number")
            if not niche:
                skipped.append({"source_sheet": sheet.title, "source_row": row_number,
                                "reason": "Nonblank row without niche number"})
                continue
            records.append({
                "source_workbook": "COFFIN CRYPT - 2nd CYCLE(AutoRecovered).xlsx",
                "source_sheet": sheet.title, "source_row": row_number,
                "building_or_block": cell(row, headers, "Block No.", "Bldg.", "Bldg. No.", "Bldg. No./Name"),
                "level": cell(row, headers, "LEVEL", "Level No."), "niche_number": niche,
                "or_number": cell(row, headers, "O. R. #"),
                "application_date": cell(row, headers, "Date of Application", "Date of Application & OR"),
                "interment_date": cell(row, headers, "Date of Interment", "Date/Time of Interment", "INTERMENT DATE"),
                "expiration_date": cell(row, headers, "Expiration Date"),
                "lessee_name": cell(row, headers, "Name of Lessee"),
                "deceased_name": cell(row, headers, "Name of Deceased"),
                "birth_date": cell(row, headers, "Born", "BORN"), "death_date": cell(row, headers, "Died", "DIED"),
                "contact_number": cell(row, headers, "Contact Number"), "address": cell(row, headers, "Address"),
            })
    return records, skipped


def lawn_rows(book):
    lots, continuations, schedules, map_cells, skipped = [], [], [], [], []
    for sheet in book.worksheets:
        rows = list(sheet.iter_rows(values_only=True))
        first = header_index(rows[0]) if rows else {}
        title = sheet.title.upper()
        is_block = title.startswith("BLOCK ") and "plot" in first
        is_final = title.startswith("FINAL")
        is_map = "MAP" in title
        if is_block:
            previous_lot = ""
            for row_number, row in enumerate(rows[1:], 2):
                if not nonempty(row):
                    continue
                plot = cell(row, first, "PLOT #")
                deceased = cell(row, first, "DECEASED", "DECEASED (1st interment)")
                if not plot:
                    if deceased and previous_lot:
                        continuations.append({"source_sheet": sheet.title, "source_row": row_number,
                                              "block_number": re.sub(r"\D", "", sheet.title),
                                              "plot_number": previous_lot, "deceased_name": deceased,
                                              "birth_date": cell(row, first, "BORN"), "death_date": cell(row, first, "DIED"),
                                              "interment_date": cell(row, first, "DATE OF INTERMENT")})
                    else:
                        skipped.append({"source_sheet": sheet.title, "source_row": row_number,
                                        "reason": "Nonblank block row without plot number"})
                    continue
                previous_lot = plot
                lots.append({
                    "source_workbook": "CONSOLIDATED LAWN LOTS (version 1).xlsb.xlsx",
                    "source_sheet": sheet.title, "source_row": row_number,
                    "block_number": cell(row, first, "BLOCK") or re.sub(r"\D", "", sheet.title),
                    "plot_number": plot, "lot_type": cell(row, first, "LOT"),
                    "owner_or_purchaser": cell(row, first, "LOT OWNER/PURCHASER", "PURCHASER/OWNER"),
                    "address": cell(row, first, "ADDRESS"), "contact_number": cell(row, first, "CONTACT", "CONTACT #", "CONTACT#"),
                    "amount": cell(row, first, "AMOUNT"), "or_number": cell(row, first, "OR #", "O.R#"),
                    "purchase_date": cell(row, first, "DATE"), "status": cell(row, first, "STATUS"),
                    "deceased_name": deceased, "birth_date": cell(row, first, "BORN"),
                    "death_date": cell(row, first, "DIED"), "interment_date": cell(row, first, "DATE OF INTERMENT"),
                })
        elif is_final:
            headers = header_index(rows[0])
            for row_number, row in enumerate(rows[1:], 2):
                if not nonempty(row):
                    continue
                schedules.append({"source_sheet": sheet.title, "source_row": row_number,
                                  "lot_reference": value(row[1]) if len(row) > 1 else "",
                                  "or_number": cell(row, headers, "OR No."),
                                  "application_date": cell(row, headers, "Date of Application"),
                                  "applicant_name": cell(row, headers, "Name of Applicant"),
                                  "deceased_name": cell(row, headers, "Name of Deceased"),
                                  "contact_number": cell(row, headers, "Contact No."),
                                  "address": cell(row, headers, "Address"),
                                  "interment_schedule": cell(row, headers, "Interment Order/ Schedule")})
        elif is_map:
            for row_number, row in enumerate(rows, 1):
                for column_number, item in enumerate(row, 1):
                    if value(item):
                        map_cells.append({"source_sheet": sheet.title, "row": row_number,
                                          "column": column_number, "value": value(item)})
        elif title.startswith("SUMMARY"):
            continue
        else:
            skipped.append({"source_sheet": sheet.title, "reason": "Unclassified sheet"})
    return lots, continuations, schedules, map_cells, skipped


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    crypt_path, lawn_path, output = map(pathlib.Path, sys.argv[1:])
    output.mkdir(parents=True, exist_ok=True)
    crypt, crypt_skipped = crypt_rows(openpyxl.load_workbook(crypt_path, read_only=True, data_only=True))
    lawn = lawn_rows(openpyxl.load_workbook(lawn_path, read_only=True, data_only=True))
    lots, continuations, schedules, map_cells, lawn_skipped = lawn
    write_csv(output / "crypt_niche_records.csv", crypt, list(crypt[0]) if crypt else [])
    write_csv(output / "lawn_lot_registers.csv", lots, list(lots[0]) if lots else [])
    write_csv(output / "lawn_interment_continuations.csv", continuations, list(continuations[0]) if continuations else [])
    write_csv(output / "lawn_interment_schedules.csv", schedules, list(schedules[0]) if schedules else [])
    write_csv(output / "lawn_map_cells.csv", map_cells, ["source_sheet", "row", "column", "value"])
    skipped = crypt_skipped + lawn_skipped
    write_csv(output / "review_exceptions.csv", skipped, ["source_sheet", "source_row", "reason"])
    manifest = {"crypt_niche_records": len(crypt), "lawn_lot_registers": len(lots),
                "lawn_interment_continuations": len(continuations), "lawn_interment_schedules": len(schedules),
                "lawn_map_cells": len(map_cells), "review_exceptions": len(skipped)}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
