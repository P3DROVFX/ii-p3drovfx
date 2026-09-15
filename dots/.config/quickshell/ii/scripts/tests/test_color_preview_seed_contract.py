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
    """The previews a first install shows before any wallpaper has been chosen.

    Nothing switches a wallpaper on a fresh install, so wallpaper_preview_colors
    .json does not exist yet and the shipped seed is the only thing that can
    answer. These lock the artefacts, the wiring and the two behaviours that keep
    a swatch from spawning a generator of its own.
    """

    def setUp(self):
        self.directories = read("modules/common/Directories.qml")
        self.cache = read("services/ThemePreviewCache.qml")
        self.button = read("modules/common/widgets/ColorPreviewButton.qml")
        self.wallpapers = read("services/Wallpapers.qml")
        self.logic = read("services/themePreview/ThemePreviewLogic.js")

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

    def test_directories_point_at_the_shipped_assets(self):
        for name, asset in (
            ("defaultPreviewColorsDarkPath", "assets/data/default_preview_colors_dark.json"),
            ("defaultPreviewColorsLightPath", "assets/data/default_preview_colors_light.json"),
            ("defaultWallpaperImagePath", "assets/images/default_wallpaper.png"),
        ):
            self.assertIn(f"property string {name}", self.directories)
            self.assertIn(f'Quickshell.shellPath("{asset}")', self.directories)

    def test_the_seed_is_read_per_mode_and_only_while_it_applies(self):
        # One file per mode, because switchwall generates the previews with the
        # mode it was called in.
        self.assertIn("Directories.defaultPreviewColorsDarkPath", self.cache)
        self.assertIn("Directories.defaultPreviewColorsLightPath", self.cache)
        self.assertIn("Appearance.m3colors.darkmode", self.cache)

        # Loaded only while the shell is on the wallpaper the seed describes and
        # the user's own file has nothing to say.
        self.assertIn("root.defaultWallpaperActive && Object.keys(root.userWallpaperPreviews).length === 0", self.cache)
        self.assertNotIn("root.wallpaperPreviews =", self.cache)

    def test_the_command_is_built_from_the_effective_wallpaper(self):
        # The root cause: an empty wallpaperPath used to leave this command
        # empty, and startColorFetch() returns before consulting any cache when
        # there is no command.
        self.assertIn("readonly property string activeWallpaperPath: Wallpapers.effectiveWallpaperPath", self.button)
        self.assertNotIn("return wallpaperPath;", self.button)

        # And the shared answer has to fall back to the shipped default, the way
        # BackgroundRoot, ConfigWallpaperSelector, ConfigBannerSelector and
        # switchwall.sh all already do.
        self.assertIn("readonly property string effectiveWallpaperPath", self.wallpapers)
        self.assertIn("Directories.defaultWallpaperImagePath", self.wallpapers)

    def test_one_generation_for_the_whole_grid(self):
        # The swatch asks the shared cache first, and only owns a process when
        # that answers false.
        self.assertIn("ThemePreviewCache.ensureWallpaperPreviews()", self.button)
        fetch = self.button.split("function startColorFetch()")[1].split("\n    }")[0]
        self.assertLess(fetch.index("loadFromCache"), fetch.index("ensureWallpaperPreviews"))
        self.assertLess(fetch.index("ensureWallpaperPreviews"), fetch.index("colorFetchProcess.running = true"))

        # A failed generation hands the swatch back to its own process rather
        # than looping on the same attempt.
        self.assertIn("signal wallpaperPreviewsGenerationFailed()", self.cache)
        self.assertIn("onWallpaperPreviewsGenerationFailed", self.button)
        self.assertIn("generatingWallpaperPreviews = false", self.cache)

    def test_the_generator_produces_what_a_wallpaper_switch_would(self):
        # --termscheme is not optional: without it the generator reaches
        # term_source_colors undefined and exits non-zero after writing.
        self.assertIn("--termscheme", self.cache)
        # switchwall's own stale-write guard, so a real switch supersedes this.
        self.assertIn("--request-token", self.cache)
        # Paths are quoted, never interpolated into the bash that runs them.
        self.assertIn("PreviewLogic.shellQuote(", self.cache)
        self.assertNotIn('--path "${wallpaper}"', self.cache)

    def test_the_regeneration_script_covers_both_modes(self):
        script = ROOT / "scripts/colors/generate-default-previews.sh"
        self.assertTrue(script.exists(), "the seed has no documented way to be regenerated")
        body = script.read_text(encoding="utf-8")
        self.assertIn("assets/images/default_wallpaper.png", body)
        self.assertIn("default_preview_colors_", body)
        # Both modes, from one loop: a single file would disagree with the
        # previews switchwall writes whenever the shell is in the other mode.
        self.assertIn("for mode in dark light; do", body)
        self.assertIn('--mode "$mode"', body)
        self.assertIn("--all-previews", body)

    def test_the_dead_wallpaper_preview_cache_is_gone(self):
        self.assertFalse((ROOT / "services/WallpaperPreviewCache.qml").exists())
        for path in ROOT.rglob("*.qml"):
            if any(part in (".git", "node_modules", "build") for part in path.parts):
                continue
            self.assertNotIn("WallpaperPreviewCache", path.read_text(encoding="utf-8"), str(path))


if __name__ == "__main__":
    unittest.main()
