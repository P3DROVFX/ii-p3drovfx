#!/usr/bin/env python3
"""Tests for the community preset store in preset_store.py.

The install, update and diff paths are exercised end to end against real git
repositories created in a temporary directory, so what is tested is the same
clone/fetch/fast-forward machinery that runs against GitHub. Nothing here
touches the network or the user's own configuration.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)

STORE_SCRIPT = os.path.join(SCRIPTS_DIR, "preset_store.py")


def git(args, cwd):
    env = dict(os.environ)
    env.update({
        "GIT_AUTHOR_NAME": "Preset Tester", "GIT_AUTHOR_EMAIL": "tester@example.invalid",
        "GIT_COMMITTER_NAME": "Preset Tester", "GIT_COMMITTER_EMAIL": "tester@example.invalid",
    })
    result = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        raise AssertionError("git %s failed: %s" % (" ".join(args), result.stderr))
    return result.stdout.strip()


class StoreTestCase(unittest.TestCase):
    """A sandboxed HOME, a sandboxed GitHub, and a preset repo to install."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="preset-store-test-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.home = os.path.join(self.root, "home")
        self.config_dir = os.path.join(self.home, ".config", "illogical-impulse")
        self.presets_dir = os.path.join(self.config_dir, "presets")
        os.makedirs(self.presets_dir)
        self.remotes = os.path.join(self.root, "remotes")
        os.makedirs(self.remotes)
        self.write_config({"configVersion": 16, "appearance": {"transparency": {"enable": True}}})

    # -- helpers ---------------------------------------------------------

    def write_config(self, data):
        with open(os.path.join(self.config_dir, "config.json"), "w", encoding="utf-8") as handle:
            json.dump(data, handle)

    def run_store(self, *args, **kwargs):
        """Run one store command in the sandbox and return its JSON line."""
        env = dict(os.environ)
        env["HOME"] = self.home
        env["II_PRESET_STORE_GIT_BASE"] = self.remotes + "/"
        env.update(kwargs.get("env", {}))
        result = subprocess.run([sys.executable, STORE_SCRIPT] + list(args),
                                capture_output=True, text=True, env=env, timeout=120)
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        self.assertTrue(lines, "no JSON was printed (stderr: %s)" % result.stderr)
        payload = json.loads(lines[-1])
        payload["_exit"] = result.returncode
        return payload

    def make_remote(self, slug, manifest, config, assets=None):
        """Create a bare repo at <remotes>/<slug>.git holding a preset."""
        work = os.path.join(self.root, "work", slug.replace("/", "__"))
        os.makedirs(work)
        with open(os.path.join(work, "preset.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=4)
        with open(os.path.join(work, manifest.get("config", "config.json")), "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=4)
        for name, content in (assets or {}).items():
            with open(os.path.join(work, name), "wb") as handle:
                handle.write(content)
        git(["init", "-b", "main"], work)
        git(["add", "-A"], work)
        git(["commit", "-m", "initial"], work)

        bare = os.path.join(self.remotes, slug + ".git")
        os.makedirs(os.path.dirname(bare), exist_ok=True)
        git(["clone", "--bare", work, bare], self.root)
        return work, bare

    def push_remote(self, work, bare, manifest=None, config=None, message="update"):
        if manifest is not None:
            with open(os.path.join(work, "preset.json"), "w", encoding="utf-8") as handle:
                json.dump(manifest, handle, indent=4)
        if config is not None:
            with open(os.path.join(work, "config.json"), "w", encoding="utf-8") as handle:
                json.dump(config, handle, indent=4)
        git(["add", "-A"], work)
        git(["commit", "-m", message], work)
        git(["push", bare, "main"], work)

    def basic_manifest(self, **overrides):
        manifest = {
            "schema": 1,
            "name": "Nord Deep",
            "author": "alice",
            "description": "A cold blue theme.",
            "version": "1.0.0",
            "configVersion": 16,
            "config": "config.json",
            "changelog": [{"version": "1.0.0", "date": "2026-09-01", "notes": "First release."}],
        }
        manifest.update(overrides)
        return manifest

    def basic_config(self, **overrides):
        config = {
            "configVersion": 16,
            "appearance": {"palette": {"type": "scheme-tonal-spot"}},
            "background": {"wallpaperPath": "$HOME/Pictures/nord.png"},
        }
        config.update(overrides)
        return config

    def install_basic(self, **manifest_overrides):
        manifest = self.basic_manifest(**manifest_overrides)
        work, bare = self.make_remote("alice/nord-deep", manifest, self.basic_config(),
                                      assets={"wallpaper.png": b"\x89PNG fake"})
        result = self.run_store("install", "alice/nord-deep")
        return work, bare, result


class TestPureHelpers(unittest.TestCase):
    """The bits that need neither a sandbox nor a subprocess."""

    def setUp(self):
        import preset_store
        self.store = preset_store

    def test_slug_accepts_a_full_url(self):
        self.assertEqual(self.store.check_slug("https://github.com/alice/nord-deep.git"),
                         "alice/nord-deep")

    def test_slug_rejects_a_path_traversal(self):
        with self.assertRaises(self.store.StoreError):
            self.store.check_slug("../../etc/passwd")

    def test_preset_name_rejects_a_path(self):
        for bad in ("../evil", "a/b", ".hidden", ""):
            with self.assertRaises(self.store.StoreError):
                self.store.check_name(bad)

    def test_preset_name_allows_spaces_and_dashes(self):
        self.assertEqual(self.store.check_name("Nord Deep-2"), "Nord Deep-2")

    def test_repo_name_is_derived_from_the_preset_name(self):
        self.assertEqual(self.store.repo_name_from_preset("Nord  Deep!! v2"), "nord-deep-v2")

    def test_version_bumping(self):
        self.assertEqual(self.store.bump_version("1.2.3", "patch"), "1.2.4")
        self.assertEqual(self.store.bump_version("1.2.3", "minor"), "1.3.0")
        self.assertEqual(self.store.bump_version("1.2.3", "major"), "2.0.0")
        # A version that was never set still has to produce a usable next one.
        self.assertEqual(self.store.bump_version("", "patch"), "0.0.1")

    def test_version_ordering_is_numeric_not_lexical(self):
        self.assertGreater(self.store.version_key("1.10.0"), self.store.version_key("1.9.0"))

    def test_diff_reports_added_removed_and_changed(self):
        changes = {c["path"]: c["kind"] for c in self.store.json_diff(
            {"a": 1, "b": {"c": 2}, "d": 3}, {"a": 1, "b": {"c": 9}, "e": 4})}
        self.assertEqual(changes.get("b.c"), "changed")
        self.assertEqual(changes.get("d"), "removed")
        self.assertEqual(changes.get("e"), "added")
        self.assertNotIn("a", changes)

    def test_manifest_without_a_name_is_refused(self):
        with self.assertRaises(self.store.StoreError):
            self.store.validate_manifest({"version": "1.0.0"})

    def test_manifest_cannot_point_its_config_outside_the_repo(self):
        for bad in ("/etc/passwd", "../../config.json"):
            with self.assertRaises(self.store.StoreError):
                self.store.validate_manifest({"name": "x", "config": bad})

    def test_compatibility_blocks_newer_and_allows_older(self):
        self.assertFalse(self.store.compatibility(999)["ok"])
        self.assertEqual(self.store.compatibility(999)["status"], "too-new")
        ours = self.store.current_config_version()
        self.assertIsNotNone(ours, "Config.qml should still declare currentConfigVersion")
        self.assertTrue(self.store.compatibility(ours - 1)["ok"])
        self.assertEqual(self.store.compatibility(ours - 1)["status"], "migrate")
        self.assertEqual(self.store.compatibility(ours)["status"], "current")

    def test_compatibility_is_undecided_when_the_preset_does_not_say(self):
        verdict = self.store.compatibility(None)
        self.assertTrue(verdict["ok"])
        self.assertEqual(verdict["status"], "unknown")


class TestInstall(StoreTestCase):
    def test_install_materialises_the_preset_and_its_wallpaper(self):
        _, _, result = self.install_basic()
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["name"], "Nord Deep")
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.json")))
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.png")))

    def test_install_records_where_the_preset_came_from(self):
        self.install_basic()
        links = self.run_store("links")["links"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["repo"], "alice/nord-deep")
        self.assertEqual(links[0]["version"], "1.0.0")
        self.assertFalse(links[0]["owned"])
        self.assertTrue(links[0]["present"])
        self.assertTrue(links[0]["installed"])

    def test_installing_the_same_repo_twice_is_refused(self):
        self.install_basic()
        again = self.run_store("install", "alice/nord-deep")
        self.assertFalse(again["ok"])
        self.assertIn("already installed", again["error"])

    def test_a_name_collision_does_not_overwrite_an_existing_preset(self):
        with open(os.path.join(self.presets_dir, "Nord Deep.json"), "w", encoding="utf-8") as handle:
            json.dump({"configVersion": 16, "mine": True}, handle)
        _, _, result = self.install_basic()
        self.assertEqual(result["name"], "Nord Deep (2)")
        with open(os.path.join(self.presets_dir, "Nord Deep.json"), encoding="utf-8") as handle:
            self.assertTrue(json.load(handle).get("mine"))

    def test_a_preset_made_for_a_newer_shell_is_blocked(self):
        _, _, result = self.install_basic(configVersion=999)
        self.assertFalse(result["ok"])
        self.assertIn("newer version", result["error"])
        self.assertFalse(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.json")))
        self.assertEqual(self.run_store("links")["total"], 0)

    def test_a_blocked_preset_can_still_be_forced(self):
        manifest = self.basic_manifest(configVersion=999)
        self.make_remote("alice/nord-deep", manifest, self.basic_config())
        result = self.run_store("install", "alice/nord-deep", "--force")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["compatibility"]["status"], "too-new")

    def test_a_repo_without_a_manifest_is_not_a_preset(self):
        work = os.path.join(self.root, "work", "bare")
        os.makedirs(work)
        with open(os.path.join(work, "README.md"), "w", encoding="utf-8") as handle:
            handle.write("not a preset")
        git(["init", "-b", "main"], work)
        git(["add", "-A"], work)
        git(["commit", "-m", "initial"], work)
        bare = os.path.join(self.remotes, "alice/plain.git")
        os.makedirs(os.path.dirname(bare), exist_ok=True)
        git(["clone", "--bare", work, bare], self.root)

        result = self.run_store("install", "alice/plain")
        self.assertFalse(result["ok"])
        self.assertIn("preset.json", result["error"])
        # The failed clone must not be left behind for check-updates to trip on.
        self.assertFalse(os.path.exists(os.path.join(
            self.config_dir, "preset-store", "alice__plain")))

    def test_a_manifest_naming_a_missing_config_is_refused(self):
        manifest = self.basic_manifest(config="theme.json")
        work = os.path.join(self.root, "work", "alice__ghost")
        os.makedirs(work)
        with open(os.path.join(work, "preset.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        git(["init", "-b", "main"], work)
        git(["add", "-A"], work)
        git(["commit", "-m", "initial"], work)
        bare = os.path.join(self.remotes, "alice/ghost.git")
        os.makedirs(os.path.dirname(bare), exist_ok=True)
        git(["clone", "--bare", work, bare], self.root)

        result = self.run_store("install", "alice/ghost")
        self.assertFalse(result["ok"])
        self.assertIn("does not carry", result["error"])

    def test_a_published_secret_is_stripped_on_the_way_in(self):
        config = self.basic_config()
        config["ai"] = {"apiKey": "sk-should-never-arrive"}
        self.make_remote("alice/leaky", self.basic_manifest(name="Leaky"), config)
        result = self.run_store("install", "alice/leaky")
        self.assertTrue(result["ok"], result)
        with open(os.path.join(self.presets_dir, "Leaky.json"), encoding="utf-8") as handle:
            installed = json.dumps(json.load(handle))
        self.assertNotIn("sk-should-never-arrive", installed)

    def test_a_missing_repository_reports_a_reason(self):
        result = self.run_store("install", "alice/nope")
        self.assertFalse(result["ok"])
        self.assertTrue(result["error"])
        self.assertEqual(result["_exit"], 1)


class TestUpdates(StoreTestCase):
    def test_a_freshly_installed_preset_has_no_updates(self):
        self.install_basic()
        result = self.run_store("check-updates")
        self.assertTrue(result["ok"])
        self.assertEqual(result["updates"], [])
        self.assertEqual(result["problems"], [])

    def test_a_new_release_is_reported_with_only_its_own_changelog(self):
        work, bare, _ = self.install_basic()
        manifest = self.basic_manifest(version="1.1.0", changelog=[
            {"version": "1.1.0", "date": "2026-09-02", "notes": "Softer accents."},
            {"version": "1.0.0", "date": "2026-09-01", "notes": "First release."},
        ])
        self.push_remote(work, bare, manifest=manifest,
                         config=self.basic_config(appearance={"palette": {"type": "scheme-vibrant"}}))
        result = self.run_store("check-updates")
        self.assertEqual(len(result["updates"]), 1)
        update = result["updates"][0]
        self.assertEqual(update["installedVersion"], "1.0.0")
        self.assertEqual(update["availableVersion"], "1.1.0")
        self.assertEqual([entry["version"] for entry in update["changelog"]], ["1.1.0"])

    def test_pull_applies_the_new_release_to_the_stored_preset(self):
        work, bare, _ = self.install_basic()
        self.push_remote(work, bare, manifest=self.basic_manifest(version="1.1.0"),
                         config=self.basic_config(appearance={"palette": {"type": "scheme-vibrant"}}))
        result = self.run_store("pull", "Nord Deep")
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["changed"])
        self.assertEqual(result["version"], "1.1.0")
        with open(os.path.join(self.presets_dir, "Nord Deep.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["appearance"]["palette"]["type"], "scheme-vibrant")

    def test_pull_with_nothing_new_is_not_an_error(self):
        self.install_basic()
        result = self.run_store("pull", "Nord Deep")
        self.assertTrue(result["ok"], result)
        self.assertFalse(result["changed"])

    def test_pull_refuses_a_release_made_for_a_newer_shell(self):
        work, bare, _ = self.install_basic()
        self.push_remote(work, bare, manifest=self.basic_manifest(version="2.0.0", configVersion=999))
        result = self.run_store("pull", "Nord Deep")
        self.assertFalse(result["ok"])
        self.assertIn("newer version", result["error"])
        links = self.run_store("links")["links"]
        self.assertEqual(links[0]["version"], "1.0.0")

    def test_a_rewritten_history_is_reported_rather_than_merged(self):
        work, bare, _ = self.install_basic()
        # The author force-pushes a different history over the tag we installed.
        git(["checkout", "--orphan", "fresh"], work)
        git(["add", "-A"], work)
        git(["commit", "-m", "rebuilt"], work)
        git(["push", "--force", bare, "fresh:main"], work)
        result = self.run_store("pull", "Nord Deep")
        self.assertFalse(result["ok"])
        self.assertIn("rewritten", result["error"])

    def test_a_deleted_clone_is_reported_as_a_problem_not_a_crash(self):
        self.install_basic()
        shutil.rmtree(os.path.join(self.config_dir, "preset-store", "alice__nord-deep"))
        result = self.run_store("check-updates")
        self.assertTrue(result["ok"])
        self.assertEqual(len(result["problems"]), 1)
        self.assertEqual(result["problems"][0]["name"], "Nord Deep")

    def test_pulling_something_that_never_came_from_the_store(self):
        result = self.run_store("pull", "Handmade")
        self.assertFalse(result["ok"])
        self.assertIn("did not come from the store", result["error"])


class TestDiff(StoreTestCase):
    def test_incoming_diff_lists_what_a_pull_would_change(self):
        work, bare, _ = self.install_basic()
        self.push_remote(work, bare, config=self.basic_config(
            appearance={"palette": {"type": "scheme-vibrant"}}))
        result = self.run_store("diff", "Nord Deep", "--incoming")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["direction"], "incoming")
        paths = {change["path"]: change for change in result["changes"]}
        self.assertIn("appearance.palette.type", paths)
        self.assertEqual(paths["appearance.palette.type"]["to"], "scheme-vibrant")

    def test_outgoing_diff_is_empty_right_after_installing(self):
        self.install_basic()
        result = self.run_store("diff", "Nord Deep")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["direction"], "outgoing")
        self.assertEqual(result["total"], 0, result["changes"])

    def test_outgoing_diff_sees_a_local_edit(self):
        self.install_basic()
        path = os.path.join(self.presets_dir, "Nord Deep.json")
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        data["appearance"]["palette"]["type"] = "scheme-expressive"
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        result = self.run_store("diff", "Nord Deep")
        paths = {change["path"] for change in result["changes"]}
        self.assertIn("appearance.palette.type", paths)


class TestRemoval(StoreTestCase):
    def test_unlink_forgets_the_repo_but_keeps_the_preset(self):
        self.install_basic()
        result = self.run_store("unlink", "Nord Deep")
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.run_store("links")["total"], 0)
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.json")))

    def test_uninstall_removes_the_preset_and_its_assets(self):
        self.install_basic()
        result = self.run_store("uninstall", "Nord Deep")
        self.assertTrue(result["ok"], result)
        self.assertEqual(self.run_store("links")["total"], 0)
        self.assertFalse(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.json")))
        self.assertFalse(os.path.exists(os.path.join(self.presets_dir, "Nord Deep.png")))

    def test_uninstall_leaves_other_presets_alone(self):
        self.install_basic()
        with open(os.path.join(self.presets_dir, "Nord Deep Extra.json"), "w", encoding="utf-8") as handle:
            json.dump({"configVersion": 16}, handle)
        self.run_store("uninstall", "Nord Deep")
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Nord Deep Extra.json")))


class TestPublishGuards(StoreTestCase):
    """Publishing itself needs a real GitHub account; its refusals do not."""

    def test_publishing_something_that_is_not_a_preset(self):
        result = self.run_store("publish", "Nothing Here", "--repo", "nothing-here")
        self.assertFalse(result["ok"])
        self.assertEqual(result["_exit"], 1)

    def test_pushing_an_update_to_someone_elses_preset_is_refused(self):
        self.install_basic()
        result = self.run_store("push-update", "Nord Deep")
        self.assertFalse(result["ok"])
        self.assertIn("someone else", result["error"])

    def test_an_invalid_repository_name_is_refused(self):
        result = self.run_store("publish", "Nord Deep", "--repo", "../escape")
        self.assertFalse(result["ok"])

    def test_the_staged_payload_carries_the_config_and_the_wallpaper(self):
        import preset_store
        os.environ["HOME"] = self.home
        try:
            with open(os.path.join(self.presets_dir, "Mine.json"), "w", encoding="utf-8") as handle:
                json.dump({"configVersion": 16, "ai": {"apiKey": "sk-secret"}}, handle)
            with open(os.path.join(self.presets_dir, "Mine.png"), "wb") as handle:
                handle.write(b"\x89PNG fake")
            with open(os.path.join(self.presets_dir, "Mine_profile.png"), "wb") as handle:
                handle.write(b"\x89PNG face")
            staging = os.path.join(self.root, "staging")
            os.makedirs(staging)
            manifest = preset_store.stage_payload(staging, "Mine", {"name": "Mine"})
            self.assertEqual(manifest.get("wallpaper"), "wallpaper.png")
            self.assertTrue(os.path.exists(os.path.join(staging, "config.json")))
            with open(os.path.join(staging, "config.json"), encoding="utf-8") as handle:
                self.assertNotIn("sk-secret", handle.read())
            # The author's own face is never part of a public preset.
            self.assertEqual([n for n in os.listdir(staging) if "profile" in n], [])
        finally:
            os.environ["HOME"] = os.path.expanduser("~")


if __name__ == "__main__":
    unittest.main(verbosity=2)
