"""Contract tests for defaults/dependencies.json and scripts/deps/deps.py."""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

II_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(II_DIR / "scripts" / "deps"))

import deps  # noqa: E402

MANIFEST = II_DIR / "defaults" / "dependencies.json"


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = deps.main(argv)
    return code, out.getvalue()


class ManifestShape(unittest.TestCase):
    def setUp(self):
        self.features = deps.load_manifest(MANIFEST)

    def test_ids_are_unique_and_cli_safe(self):
        ids = [f["id"] for f in self.features]
        self.assertEqual(len(ids), len(set(ids)))
        for fid in ids:
            # The setup script splits id lists on commas and spaces, and "core"
            # is its word for the whole required tier.
            self.assertRegex(fid, r"^[a-z0-9][a-z0-9-]*$")
            self.assertNotEqual(fid, "core")

    def test_every_feature_is_complete(self):
        for f in self.features:
            with self.subTest(f["id"]):
                self.assertIn(f["tier"], ("required", "optional"))
                self.assertTrue(f.get("label"))
                self.assertTrue(f.get("description"))
                self.assertTrue(f.get("packages"))

    def test_every_package_resolves_on_arch(self):
        for f in self.features:
            for pkg in f["packages"]:
                with self.subTest(f["id"]):
                    self.assertTrue(deps.package_name(pkg, "arch"))

    def test_required_packages_are_in_official_repos(self):
        # install and update offer these unattended-ish; no AUR builds there.
        for f in self.features:
            if f["tier"] == "required":
                for pkg in f["packages"]:
                    self.assertFalse(pkg.get("aur"), f["id"])
                    self.assertTrue(deps.package_name(pkg, "fedora"), f["id"])


class Evaluate(unittest.TestCase):
    FEATURES = [
        {"id": "a", "tier": "required", "packages": [{"name": "a", "bin": "a-bin"}]},
        {"id": "b", "tier": "optional", "packages": [
            {"name": "b1", "bin": "b1"},
            {"arch": "b2-aur", "aur": True, "fedora": None, "bin": "b2"},
        ]},
        {"id": "c", "tier": "optional", "packages": [{"arch": "c", "fedora": None, "bin": "c"}]},
    ]

    def evaluate(self, distro, present, helper="yay"):
        with mock.patch.object(deps, "has_bin", side_effect=lambda names: names in present), \
                mock.patch.object(deps, "aur_helper", return_value=helper):
            return {f["id"]: f for f in deps.evaluate(self.FEATURES, distro)["features"]}

    def test_statuses(self):
        report = self.evaluate("arch", {"b1"})
        self.assertEqual(report["a"]["status"], "missing")
        self.assertEqual(report["b"]["status"], "partial")
        self.assertTrue(report["b"]["installable"])

    def test_aur_without_helper_is_not_installable(self):
        report = self.evaluate("arch", {"b1"}, helper="")
        self.assertFalse(report["b"]["installable"])

    def test_unpackaged_distro(self):
        report = self.evaluate("fedora", set())
        self.assertEqual(report["c"]["status"], "unavailable")
        self.assertFalse(report["c"]["installable"])
        # b2 has no Fedora package, but b1 does.
        self.assertEqual(report["b"]["status"], "missing")


class StateRecord(unittest.TestCase):
    def test_record_owned_forget(self):
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": tmp}), \
                mock.patch.object(deps, "pm_has", return_value=True), \
                mock.patch.object(deps, "detect_distro", return_value="arch"):
            run(["record", "phone", "scrcpy", "mpv"])
            run(["record", "camera", "mpv"])
            # mpv is shared with another feature, so removing phone keeps it.
            self.assertEqual(run(["owned", "phone"])[1].split(), ["scrcpy"])
            run(["forget", "phone", "scrcpy"])
            data = json.loads((Path(tmp) / "ii-p3drovfx" / "deps.json").read_text())
            self.assertEqual(data["installed"], {"phone": ["mpv"], "camera": ["mpv"]})


class Plan(unittest.TestCase):
    def test_unknown_feature_exits_3(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as ctx:
            run(["--manifest", str(MANIFEST), "plan", "--features", "no-such-feature"])
        self.assertEqual(ctx.exception.code, 3)

    def test_plan_rows_have_four_columns(self):
        with mock.patch.object(deps, "has_bin", return_value=False), \
                mock.patch.object(deps, "has_python", return_value=False), \
                mock.patch.object(deps, "pm_has", return_value=False), \
                mock.patch.dict(os.environ, {"II_DEPS_DISTRO": "arch"}):
            code, out = run(["--manifest", str(MANIFEST), "plan", "--tier", "required"])
        self.assertEqual(code, 0)
        rows = [line.split("\t") for line in out.splitlines()]
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(len(row), 4)
            self.assertEqual(row[0], "repo")


if __name__ == "__main__":
    unittest.main()
