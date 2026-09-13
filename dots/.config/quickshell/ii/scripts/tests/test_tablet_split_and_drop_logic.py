#!/usr/bin/env python3
"""Unit tests for the tablet family's drop-preview and split-divider geometry (pure JS, run in node)."""

from pathlib import Path
import json
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
DROP = ROOT / "modules/tablet/appDrawer/TabletDropLayout.js"
SPLIT = ROOT / "modules/tablet/windows/TabletSplitGeometry.js"
NODE = shutil.which("node")


def run_js(path: Path, expression: str):
    """Evaluates `expression` in a context holding the library's top-level functions."""
    script = (
        "const vm = require('vm'); const fs = require('fs'); const ctx = {}; vm.createContext(ctx);"
        f"vm.runInContext(fs.readFileSync({json.dumps(str(path))}, 'utf8').replace(/^\\.pragma library\\s*$/m, ''), ctx);"
        f"process.stdout.write(JSON.stringify(vm.runInContext({json.dumps(expression)}, ctx)));"
    )
    out = subprocess.run([NODE, "-e", script], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


AREA = {"x": 0, "y": 50, "width": 1920, "height": 950}


def win(address, x, y, w, h):
    return {"address": address, "cls": "kitty", "x": x, "y": y, "width": w, "height": h}


@unittest.skipIf(NODE is None, "node is not installed")
class DropLayoutTests(unittest.TestCase):
    def plan(self, **overrides):
        data = {"point": {"x": 100, "y": 500}, "area": AREA, "gapsIn": 6, "gapsOut": 5,
                "layout": "dwindle", "windows": [], "splitRatio": 1}
        data.update(overrides)
        return run_js(DROP, f"planDrop({json.dumps(data)})")

    def test_empty_workspace_takes_the_whole_usable_area(self):
        plan = self.plan()
        self.assertEqual(plan["mode"], "empty")
        self.assertEqual(plan["incoming"], {"x": 5, "y": 55, "width": 1910, "height": 940})

    def test_dwindle_left_half_splits_beside_the_window(self):
        full = win("0xa", 5, 55, 1910, 940)
        plan = self.plan(windows=[full], point={"x": 200, "y": 500})
        self.assertEqual(plan["mode"], "dwindle")
        self.assertEqual(plan["direction"], "l")
        self.assertEqual(plan["targetAddress"], "0xa")
        incoming, existing = plan["incoming"], plan["windows"][0]["to"]
        self.assertEqual(incoming["x"], 5)
        self.assertEqual(incoming["width"] + existing["width"] + 12, 1910)
        self.assertEqual(existing["x"], incoming["x"] + incoming["width"] + 12)

    def test_dwindle_near_top_edge_splits_vertically(self):
        full = win("0xa", 5, 55, 1910, 940)
        plan = self.plan(windows=[full], point={"x": 960, "y": 70})
        self.assertEqual(plan["direction"], "u")
        self.assertEqual(plan["incoming"]["width"], 1910)
        self.assertLess(plan["incoming"]["y"], plan["windows"][0]["to"]["y"])

    def test_dwindle_targets_the_window_under_the_finger(self):
        left = win("0xa", 5, 55, 949, 940)
        right = win("0xb", 966, 55, 949, 940)
        plan = self.plan(windows=[left, right], point={"x": 1800, "y": 500})
        self.assertEqual(plan["targetAddress"], "0xb")
        self.assertEqual(plan["direction"], "r")
        self.assertEqual(plan["windows"][0]["to"], plan["windows"][0]["from"])

    def test_master_slave_joins_the_stack(self):
        full = win("0xa", 5, 55, 1910, 940)
        plan = self.plan(layout="master", mfact=0.5, newStatus="slave", windows=[full])
        self.assertEqual(plan["mode"], "master")
        self.assertEqual(plan["windows"][0]["to"]["x"], 5)
        self.assertGreater(plan["incoming"]["x"], plan["windows"][0]["to"]["x"])
        self.assertEqual(plan["incoming"]["height"], 940)

    def test_floating_uses_the_float_placement(self):
        rect = {"x": 300, "y": 200, "width": 800, "height": 600}
        plan = self.plan(windows=[win("0xa", 5, 55, 1910, 940)], floating=True, floatRect=rect)
        self.assertEqual(plan["mode"], "floating")
        self.assertEqual(plan["incoming"], rect)
        self.assertEqual(plan["windows"][0]["to"], plan["windows"][0]["from"])


@unittest.skipIf(NODE is None, "node is not installed")
class SplitGeometryTests(unittest.TestCase):
    def test_two_windows_side_by_side_share_one_divider(self):
        windows = [win("0xa", 5, 55, 949, 940), win("0xb", 966, 55, 949, 940)]
        found = run_js(SPLIT, f"dividers({json.dumps(windows)}, {{}})")
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["orientation"], "vertical")
        self.assertEqual(found[0]["position"], 954)
        self.assertEqual(found[0]["thickness"], 12)
        self.assertEqual(found[0]["before"], ["0xa"])

    def test_window_beside_a_stack_gets_one_merged_edge(self):
        windows = [win("0xa", 5, 55, 949, 940), win("0xb", 966, 55, 949, 464), win("0xc", 966, 531, 949, 464)]
        found = run_js(SPLIT, f"dividers({json.dumps(windows)}, {{}})")
        vertical = [d for d in found if d["orientation"] == "vertical"]
        horizontal = [d for d in found if d["orientation"] == "horizontal"]
        self.assertEqual(len(vertical), 1)
        self.assertEqual(sorted(vertical[0]["after"]), ["0xb", "0xc"])
        self.assertEqual((vertical[0]["start"], vertical[0]["end"]), (55, 995))
        self.assertEqual(len(horizontal), 1)
        self.assertEqual(horizontal[0]["before"], ["0xb"])

    def test_resize_clamps_and_only_sizes_the_first_side(self):
        windows = [win("0xa", 5, 55, 949, 940), win("0xb", 966, 55, 949, 940)]
        expr = (f"(() => {{ const w = {json.dumps(windows)}; const d = dividers(w, {{}})[0];"
                " return [resizePlan(d, w, 20, 200), resizePlan(d, w, 700, 200), evenPosition(d, w)]; })()")
        low, mid, even = run_js(SPLIT, expr)
        self.assertEqual(low["position"], 205)
        self.assertEqual(mid["resizes"], [{"address": "0xa", "width": 695, "height": 940}])
        self.assertEqual(even, 954)


if __name__ == "__main__":
    unittest.main()
