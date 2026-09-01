#!/usr/bin/env python3
"""Edit Mode motion audit: every animation the mode adds takes its duration
and curve from an Appearance tier - no raw durations, no hand-picked easing."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = sorted(
    list((ROOT / "modules/ii/editMode").glob("*.qml"))
    + list((ROOT / "modules/ii/bar").glob("BarEdit*.qml"))
    + list((ROOT / "modules/ii/background/desktopMenu").glob("*.qml"))
)
TIER = re.compile(r"Appearance\.animation\.[A-Za-z]+\.(numberAnimation|colorAnimation)")


class EditModeMotionAudit(unittest.TestCase):
    def test_no_raw_durations_or_easing(self):
        for path in FILES:
            for n, line in enumerate(path.read_text().splitlines(), 1):
                self.assertNotRegex(line, r"\bduration:\s*\d", f"{path.name}:{n} raw duration")
                self.assertNotIn("Easing.", line, f"{path.name}:{n} hand-picked easing")
                self.assertNotRegex(line, r"\b(Number|Property|Color)Animation\s*\{", f"{path.name}:{n} bare animation")

    def test_every_behavior_uses_a_tier(self):
        for path in FILES:
            lines = path.read_text().splitlines()
            for i, line in enumerate(lines):
                if "Behavior on" not in line:
                    continue
                window = "\n".join(lines[i:i + 4])
                self.assertRegex(window, TIER, f"{path.name}:{i + 1} Behavior without an Appearance tier")


if __name__ == "__main__":
    unittest.main()
