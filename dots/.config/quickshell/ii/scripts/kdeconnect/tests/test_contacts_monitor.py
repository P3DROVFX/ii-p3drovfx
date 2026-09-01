import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "contacts_monitor.py"
SPEC = importlib.util.spec_from_file_location("contacts_monitor", SCRIPT)
contacts_monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(contacts_monitor)


class ContactBirthdayParsingTests(unittest.TestCase):
    def parse(self, bday):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "person.vcf"
            path.write_text(
                "BEGIN:VCARD\nVERSION:4.0\nFN:Alex Example\nBDAY:" + bday + "\nEND:VCARD\n",
                encoding="utf-8",
            )
            return contacts_monitor.parse_vcard_file(path, "test-device")

    def test_parses_complete_iso_birthday(self):
        self.assertEqual(self.parse("1988-04-12")["birthday"], {"year": 1988, "month": 4, "day": 12})

    def test_parses_yearless_birthday(self):
        self.assertEqual(self.parse("--02-29")["birthday"], {"year": None, "month": 2, "day": 29})

    def test_ignores_time_suffix_and_malformed_dates(self):
        self.assertEqual(self.parse("2001-11-03T00:00:00")["birthday"], {"year": 2001, "month": 11, "day": 3})
        self.assertIsNone(self.parse("not-a-date")["birthday"])


if __name__ == "__main__":
    unittest.main()
