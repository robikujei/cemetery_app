import pathlib
import tempfile
import unittest

import openpyxl

from prepare_lawn_lot_import import generate_sql, segregate


HEADERS = [
    "BLOCK",
    "PLOT #",
    "LOT",
    "LOT OWNER/PURCHASER",
    "ADDRESS",
    "CONTACT",
    "AMOUNT",
    "OR #",
    "DATE",
    "STATUS",
    "DECEASED",
    "BORN",
    "DIED",
    "DATE OF INTERMENT",
]


class PrepareLawnLotImportTests(unittest.TestCase):
    def make_book(self, path):
        book = openpyxl.Workbook()
        sheet = book.active
        sheet.title = "BLOCK 13"
        sheet.append(HEADERS)
        sheet.append(
            [
                13,
                1,
                "RL",
                "Owner One",
                "Address",
                "09170000000",
                "1000",
                "OR-1",
                "2026-01-02",
                "CASH",
                "Deceased One",
                "1950-01-01",
                "2020-01-01",
                "2020-01-03",
            ]
        )
        sheet.append([None, None, None, None, None, None, None, None, None, None, "Deceased Two"])
        sheet.append([13, 2, "PRIME C", "Owner Two", None, None, None, None, None, None, None])
        old = book.create_sheet("BLOCK 36")
        old.append(HEADERS)
        old.append([36, 1, "RL", "Already Imported"])
        book.save(path)

    def test_segregates_database_rows_and_excludes_block_36(self):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "lawn.xlsx"
            self.make_book(source)
            data = segregate(source, {"36"})

            self.assertEqual(len(data["lots"]), 2)
            self.assertEqual(len(data["owners"]), 2)
            self.assertEqual(len(data["ownerships"]), 2)
            self.assertEqual(len(data["burials"]), 2)
            self.assertEqual(len(data["graves"]), 2)
            self.assertEqual(data["lots"][0]["lot_class_type"], "Regular Lot")
            self.assertIsNone(data["lots"][1]["lot_class_type"])
            categories = {issue["category"] for issue in data["issues"]}
            self.assertIn("lot_type_review", categories)
            self.assertIn("excluded_block", categories)

    def test_generates_preview_import_validation_and_rollback_sql(self):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "lawn.xlsx"
            output = pathlib.Path(directory) / "output"
            output.mkdir()
            self.make_book(source)
            data = segregate(source, {"36"})
            generate_sql(data, output)

            preview = (output / "01_preview.sql").read_text(encoding="utf-8")
            apply = (output / "02_import.sql").read_text(encoding="utf-8")
            self.assertIn("ROLLBACK;", preview)
            self.assertIn("Expected 2 segregated lawn lots", apply)
            self.assertTrue((output / "03_validate.sql").exists())
            self.assertTrue((output / "04_rollback.sql").exists())


if __name__ == "__main__":
    unittest.main()
