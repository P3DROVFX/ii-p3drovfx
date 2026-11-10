import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SCHEME_PATTERN = re.compile(r"^scheme-[a-z-]+$")
COLOR_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")
SEED_KEYS = ("primary", "primary_container", "secondary", "tertiary")


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ColorPreviewSeedContractTest(unittest.TestCase):
    """The shipped swatches cover every wallpaper scheme in both modes."""

    def load_seed(self, mode: str):
        path = ROOT / f"assets/data/default_preview_colors_{mode}.json"
        self.assertTrue(path.exists(), f"{path.name} is missing; run scripts/colors/generate-default-previews.sh")
        return json.loads(path.read_text(encoding="utf-8"))

    def test_both_modes_ship_a_complete_seed(self):
        grids = sorted(re.findall(
            r'"scheme-[a-z-]+"',
            read("modules/common/widgets/ColorPreviewGrid.qml").split("wallpaperColorSchemes")[1].split("]")[0]))

        for mode in ("dark", "light"):
            seed = self.load_seed(mode)
            self.assertTrue(seed, mode)
            for scheme, entry in seed.items():
                self.assertRegex(scheme, SCHEME_PATTERN, mode)
                for key in SEED_KEYS:
                    self.assertRegex(entry.get(key, ""), COLOR_PATTERN, f"{mode}/{scheme}/{key}")

            # A scheme added to the swatch grid without being regenerated here
            # would be the one blank button left, so the lists must match.
            self.assertEqual(sorted(f'"{name}"' for name in seed), grids, mode)



if __name__ == "__main__":
    unittest.main()
