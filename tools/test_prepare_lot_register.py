import datetime as dt
import pathlib
import tempfile
import unittest

import openpyxl

from prepare_lot_register import lot_number, prepare, purchase_date, sql_files


class RegisterTests(unittest.TestCase):
    def test_number_and_dates(self):
        self.assertEqual([lot_number(v) for v in (1, 10.0, '100', '0001')], ['001', '010', '100', '001'])
        with self.assertRaises(ValueError):
            lot_number('1-3')
        self.assertEqual(purchase_date('JANUARY 28,2020'), '2020-01-28')
        self.assertEqual(purchase_date(dt.datetime(2020, 1, 6)), '2020-01-06')
        self.assertEqual(purchase_date('4/16/20'), '2020-04-16')
        self.assertIsNone(purchase_date('WITH BALANCE'))
        self.assertIsNone(purchase_date('FEBRUARY 30,2020'))

    def test_continuations_duplicates_blanks_and_block(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'input.xlsx'
            book = openpyxl.Workbook()
            sheet = book.active
            sheet.append(['BLOCK ', 'LOT TYPE', 'LOT ', 'LOT OWNER/PURCHASER', 'DATE', 'DECEASED'])
            sheet.append([36, 'PRIMCE C', 1, "O'Brien", 'WITH BALANCE', 'Person A'])
            sheet.append([None, None, None, None, None, 'Person B'])
            sheet.append([36, None, 2, None, None, None])
            sheet.append([36, None, 2, 'Different owner', None, None])
            sheet.append([0, None, 3, None, None, None])
            sheet.append([None, None, 4, None, None, None])
            book.save(path)
            records, issues = prepare(path, '36')
            self.assertEqual(records[0]['details']['deceased_names'], 'Person A\nPerson B')
            self.assertEqual(records[0]['lot_type'], 'Prime C')
            mapped, _ = prepare(path, '36', prime_c_is_super=True)
            self.assertEqual(mapped[0]['lot_type'], 'Super Prime C')
            self.assertNotIn('purchase_date', records[0]['details'])
            self.assertEqual(records[1]['details'], {})
            self.assertEqual([r['eligible'] for r in records], [True, False, False, False, True])
            sql_files(records, '36', pathlib.Path(directory))
            sql = (pathlib.Path(directory) / '02_import.sql').read_text(encoding='utf-8')
            self.assertIn("O''Brien", sql)
            self.assertNotIn('Different owner', sql)
            self.assertTrue(issues)


if __name__ == '__main__':
    unittest.main()
