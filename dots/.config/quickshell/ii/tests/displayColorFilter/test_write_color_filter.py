from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WRITER = REPOSITORY_ROOT / "scripts" / "display" / "write_color_filter.py"


class ColorFilterWriterTest(unittest.TestCase):
    def test_publishes_identical_shader_to_both_paths(self) -> None:
        shader = "#version 300 es\nvoid main() {}\n"
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            first = directory / "a" / "filter.glsl"
            second = directory / "b" / "filter.glsl"

            completed = subprocess.run(
                [
                    sys.executable,
                    str(WRITER),
                    "--output",
                    str(first),
                    "--output",
                    str(second),
                ],
                input=shader,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(first.read_text(encoding="utf-8"), shader)
            self.assertEqual(second.read_text(encoding="utf-8"), shader)
            self.assertEqual(list(first.parent.glob(".filter.glsl.*")), [])
            self.assertEqual(list(second.parent.glob(".filter.glsl.*")), [])

    def test_rejects_empty_shader(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "filter.glsl"
            completed = subprocess.run(
                [sys.executable, str(WRITER), "--output", str(output)],
                input="",
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
