#!/usr/bin/env python3
"""Tests for scripts/clipboard/copy_image_to_clipboard.py and phone/gallery copy wiring."""

import io
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "clipboard" / "copy_image_to_clipboard.py"
II_LINK = ROOT / "services" / "IiLinkService.qml"
GALLERY_SVC = ROOT / "services" / "PhoneGalleryService.qml"


FAKE_WL_COPY = """#!/usr/bin/env python3
import json
import os
import sys

out_dir = os.environ["FAKE_WL_COPY_OUT"]
with open(os.path.join(out_dir, "argv.json"), "w") as f:
    json.dump(sys.argv[1:], f)
data = sys.stdin.buffer.read()
with open(os.path.join(out_dir, "stdin.bin"), "wb") as f:
    f.write(data)
"""


class CopyImageToClipboardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.out = self.base / "out"
        self.out.mkdir()
        wl = self.bin / "wl-copy"
        wl.write_text(FAKE_WL_COPY, encoding="utf-8")
        wl.chmod(wl.stat().st_mode | stat.S_IXUSR)

        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin}:{self.env['PATH']}"
        self.env["FAKE_WL_COPY_OUT"] = str(self.out)

    def tearDown(self):
        self.tmp.cleanup()

    def _run(self, *args):
        return subprocess.run(
            ["python3", str(SCRIPT), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def _copied_bytes(self):
        return (self.out / "stdin.bin").read_bytes()

    def _copied_argv(self):
        import json
        return json.loads((self.out / "argv.json").read_text(encoding="utf-8"))

    def test_png_passthrough_and_delete(self):
        src = self.base / "sample.png"
        Image.new("RGBA", (12, 8), (255, 0, 0, 128)).save(src, format="PNG")
        original = src.read_bytes()

        res = self._run("--delete", str(src))
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertFalse(src.exists())
        self.assertEqual(self._copied_argv(), ["--type", "image/png"])
        self.assertEqual(self._copied_bytes(), original)

    def test_jpeg_with_exif_orientation_transposed_to_png(self):
        src = self.base / "photo.jpg"
        img = Image.new("RGB", (20, 10), (10, 120, 220))
        exif = img.getexif()
        exif[274] = 6  # Rotate 90 CW
        img.save(src, format="JPEG", exif=exif)

        res = self._run(str(src))
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(src.exists())
        self.assertEqual(self._copied_argv(), ["--type", "image/png"])

        data = self._copied_bytes()
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        with Image.open(io.BytesIO(data)) as out_img:
            self.assertEqual(out_img.format, "PNG")
            self.assertEqual(out_img.size, (10, 20))

    def test_webp_alpha_preserved_as_png(self):
        src = self.base / "sticker.webp"
        Image.new("RGBA", (16, 16), (0, 200, 100, 64)).save(src, format="WEBP")

        res = self._run(str(src))
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self._copied_argv(), ["--type", "image/png"])

        with Image.open(io.BytesIO(self._copied_bytes())) as out_img:
            self.assertEqual(out_img.format, "PNG")
            self.assertEqual(out_img.mode, "RGBA")
            self.assertEqual(out_img.getpixel((0, 0))[3], 64)

    def test_mislabeled_jpeg_with_png_extension_is_reencoded(self):
        src = self.base / "Screenshot_1.png"
        Image.new("RGB", (15, 9), (40, 50, 60)).save(src, format="JPEG")

        res = self._run(str(src))
        self.assertEqual(res.returncode, 0, res.stderr)
        data = self._copied_bytes()
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        with Image.open(io.BytesIO(data)) as out_img:
            self.assertEqual(out_img.format, "PNG")
            self.assertEqual(out_img.size, (15, 9))

    def test_delete_cleans_up_even_on_corrupt_file(self):
        src = self.base / "broken.jpg"
        src.write_bytes(b"not an image")

        res = self._run("--delete", str(src))
        self.assertNotEqual(res.returncode, 0)
        self.assertFalse(src.exists())

    def test_qml_services_use_image_clipboard_helper(self):
        ii_link = II_LINK.read_text(encoding="utf-8")
        gallery = GALLERY_SVC.read_text(encoding="utf-8")

        self.assertIn('copy_image_to_clipboard.py`, "--delete", path', ii_link)
        self.assertIn('copy_image_to_clipboard.py`', ii_link)
        self.assertNotIn('wl-copy --type "$1" < "$2"', ii_link)
        self.assertNotIn('wl-copy --type image/png < "$3"', ii_link)

        self.assertIn('copy_image_to_clipboard.py`, path', gallery)
        self.assertNotIn('wl-copy --type "$1" < "$2"', gallery)


if __name__ == "__main__":
    unittest.main()
