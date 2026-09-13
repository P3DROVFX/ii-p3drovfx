#!/usr/bin/env python3
"""Lock islands contract: Config defaults, the resolver's defaults and the
surface's id map agree, and the resolver keeps its read/write semantics."""

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JS = ROOT / "modules/common/functions/lock_islands.js"
CONFIG = ROOT / "modules/common/Config.qml"
SURFACE = ROOT / "modules/ii/lock/LockSurface.qml"


def js_list(name):
    m = re.search(rf"var {name} = (\[[^\]]*\]);", JS.read_text())
    return json.loads(m.group(1))


def config_list(name):
    src = CONFIG.read_text()
    block = src[src.index("property JsonObject islands: JsonObject {"):]
    m = re.search(rf"property list<string> {name}: (\[[^\]]*\])", block)
    return json.loads(m.group(1))


def surface_ids(island):
    src = SURFACE.read_text()
    block = src[src.index("readonly property var islandItems:"):]
    block = block[:block.index("})") + 2]
    m = re.search(rf'"{island}":\s*\{{(.*?)\}}', block, re.S)
    return re.findall(r'"([A-Za-z]+)":', m.group(1))


def run_js(expr):
    src = JS.read_text().replace(".pragma library", "")
    out = subprocess.run(["node", "-e", src + f"\nconsole.log(JSON.stringify({expr}));"],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


class LockIslandsContract(unittest.TestCase):
    def test_defaults_agree(self):
        for island, name in (("main", "MAIN_DEFAULT"), ("left", "LEFT_DEFAULT"), ("right", "RIGHT_DEFAULT")):
            self.assertEqual(config_list(island), js_list(name), island)
            self.assertEqual(set(surface_ids(island)), set(js_list(name)), island)

    def test_password_is_never_reorderable(self):
        self.assertIn('island === "main" && id === "password"', JS.read_text())

    @unittest.skipUnless(shutil.which("node"), "node not installed")
    def test_resolver_semantics(self):
        left = js_list("LEFT_DEFAULT")
        # Unknown ids skipped, known ids missing from the store keep their default neighbourhood.
        self.assertEqual(run_js(f'orderedItems(["weather","bogus","battery"], {json.dumps(left)})'),
                         ["weather", "keyboardLayout", "keepAwake", "mode", "battery", "capsLock", "alarm"])
        self.assertEqual(run_js(f"orderedItems([], {json.dumps(left)})"), left)
        # Writes keep unknown ids so an older/newer shell loses nothing.
        self.assertEqual(run_js('storedOrder(["a","b"], ["b","zzz","a"], ["a","b"])'), ["a", "b", "zzz"])
        self.assertFalse(run_js('reorderable("main", "password")'))
        self.assertTrue(run_js('reorderable("main", "confirm")'))


if __name__ == "__main__":
    unittest.main()
