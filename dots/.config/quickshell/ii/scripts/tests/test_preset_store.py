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
from pathlib import Path
from unittest import mock

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

    def make_monorepo_remote(self, slug, presets_data):
        """Create a bare repo holding an index.json and subfolders for each preset."""
        work = os.path.join(self.root, "work", slug.replace("/", "__"))
        os.makedirs(work, exist_ok=True)
        index = {"schema": 1, "author": slug.split("/")[0], "presets": []}
        for p_id, p_info in presets_data.items():
            sub = os.path.join(work, "presets", p_id)
            os.makedirs(sub, exist_ok=True)
            with open(os.path.join(sub, "preset.json"), "w", encoding="utf-8") as handle:
                json.dump(p_info["manifest"], handle, indent=4)
            with open(os.path.join(sub, p_info["manifest"].get("config", "config.json")), "w", encoding="utf-8") as handle:
                json.dump(p_info["config"], handle, indent=4)
            for asset_name, content in (p_info.get("assets") or {}).items():
                with open(os.path.join(sub, asset_name), "wb") as handle:
                    handle.write(content)
            index["presets"].append({
                "id": p_id,
                "name": p_info["manifest"]["name"],
                "description": p_info["manifest"].get("description", ""),
                "version": p_info["manifest"]["version"],
                "configVersion": p_info["manifest"].get("configVersion"),
                "path": "presets/%s" % p_id,
            })
        with open(os.path.join(work, "index.json"), "w", encoding="utf-8") as handle:
            json.dump(index, handle, indent=4)
        git(["init", "-b", "main"], work)
        git(["add", "-A"], work)
        git(["commit", "-m", "initial collection"], work)

        bare = os.path.join(self.remotes, slug + ".git")
        os.makedirs(os.path.dirname(bare), exist_ok=True)
        git(["clone", "--bare", work, bare], self.root)
        return work, bare

    def push_monorepo_remote(self, work, bare, preset_id, manifest=None, config=None, message="update"):
        sub = os.path.join(work, "presets", preset_id)
        if manifest is not None:
            with open(os.path.join(sub, "preset.json"), "w", encoding="utf-8") as handle:
                json.dump(manifest, handle, indent=4)
            with open(os.path.join(work, "index.json"), "r+", encoding="utf-8") as handle:
                idx = json.load(handle)
                for p in idx.get("presets", []):
                    if p["id"] == preset_id:
                        p["version"] = manifest["version"]
                        p["configVersion"] = manifest.get("configVersion")
                        break
                handle.seek(0)
                json.dump(idx, handle, indent=4)
                handle.truncate()
        if config is not None:
            with open(os.path.join(sub, "config.json"), "w", encoding="utf-8") as handle:
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

    def test_a_generated_collision_name_is_accepted_back(self):
        import preset_store
        # install() renames a colliding preset to "Name (2)". If check_name
        # refused that, every command afterwards -- pull, diff, uninstall --
        # would refuse the preset the store itself had just created.
        self.assertEqual(preset_store.check_name("Midnight Slate (2)"), "Midnight Slate (2)")

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

    def test_discover_streams_repository_cards_before_metadata_probes_finish(self):
        """The store must paint useful cards before its slower raw probes run."""
        repository = {
            "full_name": "alice/fast-theme",
            "name": "fast-theme",
            "description": "A fast test preset.",
            "default_branch": "main",
            "owner": {"login": "alice", "avatar_url": "https://avatars.example/alice"},
            "stargazers_count": 7,
            "html_url": "https://github.com/alice/fast-theme",
            "pushed_at": "2026-09-09T00:00:00Z",
        }
        initial = []
        with mock.patch.object(self.store, "gh_token", return_value=None), \
             mock.patch.object(self.store, "http_json", return_value={"items": [repository]}), \
             mock.patch.object(self.store, "load_links", return_value={}), \
             mock.patch.object(self.store, "download_preview", return_value=""), \
             mock.patch.object(self.store, "read_optional_json", return_value={}), \
             mock.patch.object(self.store, "write_optional_json"), \
             mock.patch.object(self.store, "load_discover_meta_cache", return_value={}), \
             mock.patch.object(self.store, "save_discover_meta_cache"), \
             mock.patch.object(self.store, "probe_repo_meta",
                               return_value=("alice/fast-theme", "main", "preset", {
                                   "name": "Fast Theme", "screenshots": ["preview.png"]
                               })), \
             mock.patch.object(self.store, "emit", side_effect=initial.append):
            result = self.store.cmd_discover(30, stream=True)

        self.assertEqual(initial[0]["phase"], "initial")
        self.assertFalse(initial[0]["results"][0]["metadataReady"])
        self.assertEqual(initial[0]["results"][0]["name"], "fast-theme")
        self.assertTrue(result["results"][0]["metadataReady"])
        self.assertEqual(result["results"][0]["name"], "Fast Theme")

    def test_streamed_output_is_flushed_before_the_metadata_batch_finishes(self):
        with mock.patch("builtins.print") as printer:
            self.store.emit({"ok": True, "phase": "initial"})
        printer.assert_called_once_with('{"ok": true, "phase": "initial"}', flush=True)

    def test_negative_metadata_cache_entry_is_not_reused_after_a_network_failure(self):
        repo = {
            "full_name": "alice/possibly-later",
            "default_branch": "main",
            "pushed_at": "2026-09-09T00:00:00Z",
        }
        cache = {
            "alice/possibly-later": {
                "branch": "main",
                "updatedAt": "2026-09-09T00:00:00Z",
                "checkedAt": self.store.time.time(),
                "kind": "",
                "data": {},
            }
        }
        self.assertIsNone(self.store.cached_repo_meta(cache, repo))

    def test_publish_prepares_a_repository_local_github_noreply_identity(self):
        calls = []

        def fake_git(args, cwd, timeout=None):
            calls.append(args)
            if args[:2] == ["config", "--get"]:
                return 1, "", "not set"
            return 0, "", ""

        with mock.patch.object(self.store, "git", side_effect=fake_git):
            self.store.ensure_git_identity("/tmp/preset-store-test", {
                "login": "octocat",
                "userId": 583231,
            })

        self.assertIn(["config", "user.name", "octocat"], calls)
        self.assertIn(["config", "user.email", "583231+octocat@users.noreply.github.com"], calls)

    def test_new_publish_initializes_git_before_configuring_its_identity(self):
        with open(STORE_SCRIPT, encoding="utf-8") as handle:
            source = handle.read()
        new_repo_flow = source[source.index("if not is_existing_repo:", source.index("def cmd_publish")):
                              source.index("else:\n            ensure_git_identity(directory, auth)",
                                           source.index("def cmd_publish"))]
        self.assertLess(new_repo_flow.index("git(['init', '-b', 'main']"),
                        new_repo_flow.index("ensure_git_identity(directory, auth)"))


class TestStoreLoading(StoreTestCase):
    def setUp(self):
        super().setUp()
        import preset_store
        self.store = preset_store
        self.repo = {"full_name": "alice/themes", "name": "themes",
                     "default_branch": "main", "pushed_at": "revision-1",
                     "owner": {"login": "alice"}}
        self.index = {"presets": [{"id": "blue", "name": "Blue",
                                   "path": "presets/blue", "banner": "presets/blue/banner.png"}]}
        self.patchers = [mock.patch.object(self.store, "home", return_value=self.home),
                         mock.patch.object(self.store, "gh_token", return_value=None)]
        for patcher in self.patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def seed_metadata(self):
        cache = {}
        self.store.cache_repo_meta(cache, self.repo, "index", self.index)
        self.store.save_discover_meta_cache(cache)

    def test_store_preview_uses_screenshot_instead_of_sidebar_banner(self):
        preset = {"id": "estelar", "name": "Estelar", "path": "presets/estelar",
                  "banner": "presets/estelar/banner.png",
                  "wallpaper": "presets/estelar/wallpaper.jpeg",
                  "screenshots": ["presets/estelar/screenshots/1.png"]}
        collection = self.store.discover_result(self.repo, {}, "index", {"presets": [preset]}, True)[0]
        self.assertTrue(collection["imageUrl"].endswith("presets/estelar/screenshots/1.png"))
        single = dict(preset, screenshots=["screenshots/1.png"], banner="banner.png")
        single_row = self.store.discover_result(self.repo, {}, "preset", single, True)[0]
        self.assertTrue(single_row["imageUrl"].endswith("/screenshots/1.png"))
        preset["screenshots"] = []
        fallback = self.store.discover_result(self.repo, {}, "index", {"presets": [preset]}, True)[0]
        self.assertTrue(fallback["imageUrl"].endswith("presets/estelar/wallpaper.jpeg"))

    def test_first_frame_uses_cached_collection_without_provisional_wallpaper(self):
        self.seed_metadata()
        frames = []
        with mock.patch.object(self.store, "http_json", return_value={"items": [self.repo]}), \
             mock.patch.object(self.store, "emit", side_effect=frames.append), \
             mock.patch.object(self.store, "download_preview", return_value=""), \
             mock.patch.object(self.store, "probe_repo_meta") as probe:
            result = self.store.cmd_discover(stream=True)
        self.assertEqual(frames[0]["results"][0]["repo"], "alice/themes:blue")
        self.assertTrue(frames[0]["results"][0]["metadataReady"])
        probe.assert_not_called()
        self.assertEqual(result["results"][0]["name"], "Blue")

    def test_fast_repo_and_preview_stream_before_slow_repo_finishes(self):
        import threading
        ready = threading.Event()
        frames = []
        slow = dict(self.repo, full_name="alice/slow", name="slow")

        def probe(repo, token=None):
            if repo["name"] == "slow":
                if not ready.wait(3):
                    raise AssertionError("A slow repository blocked the fast preview")
            return repo["full_name"], "main", "index", self.index

        def receive(frame):
            frames.append(frame)
            if any(row.get("previewLocal") for row in frame["results"]):
                ready.set()

        with mock.patch.object(self.store, "http_json", return_value={"items": [self.repo, slow]}), \
             mock.patch.object(self.store, "probe_repo_meta", side_effect=probe), \
             mock.patch.object(self.store, "download_preview", return_value="file:///tmp/cached.png"), \
             mock.patch.object(self.store, "emit", side_effect=receive):
            self.store.cmd_discover(stream=True)
        self.assertTrue(ready.is_set())
        preview_frame = next(f for f in frames if any(r.get("previewLocal") for r in f["results"]))
        self.assertTrue(any(r["repo"] == "alice/slow" and not r["metadataReady"]
                            for r in preview_frame["results"]))

    def test_reopening_reuses_search_and_preview_without_network(self):
        self.seed_metadata()
        with mock.patch.object(self.store, "http_json", return_value={"items": [self.repo]}) as api, \
             mock.patch.object(self.store, "download_preview", return_value=""):
            self.store.cmd_discover()
            self.store.cmd_discover()
        self.assertEqual(api.call_count, 1)

    def test_offline_refresh_keeps_cached_cards(self):
        self.seed_metadata()
        with mock.patch.object(self.store, "http_json", return_value={"items": [self.repo]}), \
             mock.patch.object(self.store, "download_preview", return_value=""):
            self.store.cmd_discover()
        with mock.patch.object(self.store, "http_json", side_effect=TimeoutError("offline")), \
             mock.patch.object(self.store, "download_preview", return_value=""):
            result = self.store.cmd_discover(force=True)
        self.assertTrue(result["ok"])
        self.assertEqual(result["results"][0]["name"], "Blue")
        self.assertTrue(result["warning"])

    def test_detail_reuses_repo_and_index_and_caches_manifest(self):
        self.seed_metadata()
        manifest = {"schema": 1, "name": "Blue", "version": "1.0.0", "configVersion": 16,
                    "screenshots": ["preview.png"]}
        with mock.patch.object(self.store, "http_json") as api, \
             mock.patch.object(self.store, "http_text", return_value=json.dumps(manifest)) as raw:
            first = self.store.cmd_fetch_manifest("alice/themes:blue")
            second = self.store.cmd_fetch_manifest("alice/themes:blue")
        api.assert_not_called()
        self.assertEqual(raw.call_count, 1)
        self.assertTrue(raw.call_args.args[0].endswith("presets/blue/preset.json"))
        self.assertEqual(first, second)
        self.assertTrue(first["ok"])

    def test_media_download_has_hard_deadline_and_atomic_cache_reuse(self):
        def transfer(args, **kwargs):
            self.assertIn("--max-time", args)
            self.assertIn("--connect-timeout", args)
            self.assertIn("--max-filesize", args)
            destination = args[args.index("--output") + 1]
            Path(destination).write_bytes(b"\x89PNG\r\n\x1a\n" + b"preview")
            return 0, "200", ""

        from pathlib import Path
        with mock.patch.object(self.store, "run", side_effect=transfer) as curl:
            a = self.store.download_preview("https://raw.githubusercontent.com/alice/themes/main/banner.png", "r1")
            b = self.store.download_preview("https://raw.githubusercontent.com/alice/themes/main/banner.png", "r1")
        self.assertTrue(a.startswith("file://"))
        self.assertEqual(a, b)
        self.assertEqual(curl.call_count, 1)

    def test_rate_limit_cooldown_prevents_repeated_api_requests(self):
        import urllib.error
        self.seed_metadata()
        with mock.patch.object(self.store, "http_json", return_value={"items": [self.repo]}), \
             mock.patch.object(self.store, "download_preview", return_value=""):
            self.store.cmd_discover()
        limited = urllib.error.HTTPError("https://api.github.com", 429, "wait", {"Retry-After": "60"}, None)
        with mock.patch.object(self.store, "http_json", side_effect=limited) as api, \
             mock.patch.object(self.store, "download_preview", return_value=""):
            self.assertTrue(self.store.cmd_discover(force=True)["results"])
            self.assertTrue(self.store.cmd_discover(force=True)["results"])
        self.assertEqual(api.call_count, 1)

    def test_detail_metadata_arrives_before_screenshot_download(self):
        self.seed_metadata()
        frames = []
        manifest = {"schema": 1, "name": "Blue", "configVersion": 16,
                    "screenshots": ["preview.png"]}

        def download(url, revision):
            self.assertTrue(frames)
            self.assertEqual(frames[0]["phase"], "manifest")
            self.assertEqual(frames[0]["manifest"]["screenshotUrls"], [""])
            return "file:///cached/preview.png"

        with mock.patch.object(self.store, "http_text", return_value=json.dumps(manifest)), \
             mock.patch.object(self.store, "download_preview", side_effect=download), \
             mock.patch.object(self.store, "emit", side_effect=lambda f: frames.append(json.loads(json.dumps(f)))):
            result = self.store.cmd_fetch_manifest("alice/themes:blue", stream=True)
        self.assertEqual(result["phase"], "complete")
        self.assertEqual(result["manifest"]["screenshotUrls"], ["file:///cached/preview.png"])

    def test_concurrent_preview_requests_share_one_download(self):
        import concurrent.futures
        from pathlib import Path

        def transfer(args, **kwargs):
            Path(args[args.index("--output") + 1]).write_bytes(b"\x89PNG\r\n\x1a\npreview")
            return 0, "200", ""

        with mock.patch.object(self.store, "run", side_effect=transfer) as curl, \
             concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            urls = ["https://raw.githubusercontent.com/alice/themes/main/banner.png"] * 3
            results = list(pool.map(self.store.download_preview, urls))
        self.assertTrue(all(results))
        self.assertEqual(len(set(results)), 1)
        self.assertEqual(curl.call_count, 1)

    def test_changed_revision_invalidates_qt_image_cache_key(self):
        import os
        url = "https://raw.githubusercontent.com/alice/themes/main/banner.png"
        counter = 0

        def transfer(url, destination, *args):
            nonlocal counter
            counter += 1
            Path(destination).write_bytes(b"\x89PNG\r\n\x1a\npreview")
            os.utime(destination, ns=(counter * 1000000000, counter * 1000000000))

        with mock.patch.object(self.store, "curl_download", side_effect=transfer):
            first = self.store.download_preview(url, "revision-1")
            second = self.store.download_preview(url, "revision-2")
        self.assertNotEqual(first, second)
        self.assertTrue(first.startswith("file://") and second.startswith("file://"))

    def test_failed_preview_refresh_retains_last_good_image_and_backs_off(self):
        from pathlib import Path
        url = "https://raw.githubusercontent.com/alice/themes/main/banner.png"
        path = self.store.preview_path(url)
        path.parent.mkdir(parents=True)
        path.write_bytes(b"\x89PNG\r\n\x1a\nold-preview")
        with mock.patch.object(self.store, "curl_download", side_effect=TimeoutError("offline")) as curl:
            first = self.store.download_preview(url, "new-revision")
            second = self.store.download_preview(url, "new-revision")
        self.assertTrue(first.startswith(path.as_uri() + "?v="))
        self.assertEqual(second, first)
        self.assertEqual(curl.call_count, 1)
        self.assertEqual(path.read_bytes(), b"\x89PNG\r\n\x1a\nold-preview")



class TestPresetStoreQmlContract(unittest.TestCase):
    """Keep the streamed Python protocol aligned with its QML consumer."""

    def test_runner_consumes_split_parser_records_as_individual_json_lines(self):
        path = os.path.join(os.path.dirname(SCRIPTS_DIR), "services", "PresetStore.qml")
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        self.assertIn('splitMarker: "\\n"', source)
        self.assertIn('runner.acceptLine(data);', source)
        self.assertNotIn('function acceptChunk(', source)

    def test_initial_discovery_results_release_the_blocking_store_loader(self):
        path = os.path.join(os.path.dirname(SCRIPTS_DIR), "services", "PresetStore.qml")
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        self.assertIn('property bool discoverHydrating: false', source)
        self.assertIn('root.discovering = false;\n            root.discoverHydrating = true;', source)

    def test_store_controls_wait_for_streamed_discovery_to_finish(self):
        for relative_path in [
            ("modules", "settings", "configs", "presets", "PresetStoreTab.qml"),
            ("modules", "welcome", "WelcomePresetStorePane.qml"),
        ]:
            path = os.path.join(os.path.dirname(SCRIPTS_DIR), *relative_path)
            with open(path, encoding="utf-8") as handle:
                source = handle.read()
            self.assertEqual(source.count('enabled: !PresetStore.discovering && !PresetStore.discoverHydrating'), 2)

    def test_browsing_is_not_queued_as_a_preset_mutation(self):
        source = Path(os.path.dirname(SCRIPTS_DIR), "services", "PresetStore.qml").read_text()
        discover = source[source.index('    function discover('):source.index('    function fetchManifest(')]
        detail = source[source.index('    function fetchManifest('):source.index('    function install(')]
        self.assertIn('discoveryReader.start(', discover)
        self.assertNotIn('root._enqueue(', discover)
        self.assertNotIn('root._run(', detail)
        self.assertIn('payload.phase === "manifest"', source)

    def test_detail_install_label_requires_an_install_request(self):
        source = Path(os.path.dirname(SCRIPTS_DIR), "modules/settings/configs/presets/PresetDetailSubPage.qml").read_text()
        self.assertIn('PresetStore.actionPending("install", root.repo)', source)
        self.assertIn('actionLabel: root.installing', source)
        self.assertIn('enabled: !root.loading && root.manifest !== null', source)
        self.assertIn('repoTarget !== root.requestedInstallRepo', source)
        self.assertNotIn('PresetStore.busyFor', source)


    def test_installed_detail_offers_apply_and_restorable_active_preset_offers_undo(self):
        source = Path(os.path.dirname(SCRIPTS_DIR), "modules/settings/configs/presets/PresetDetailSubPage.qml").read_text()
        self.assertIn('Translation.tr("Apply now?")', source)
        self.assertIn('Translation.tr("Applied")', source)
        self.assertIn('visible: (root.applied && PresetStore.canRevert) || root.revertRequested', source)
        self.assertIn('anchors.right: installFab.left', source)
        self.assertIn('PresetStore.revert();', source)
        self.assertIn('!root.applied || root.hasUpdate', source)



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


class TestPreview(StoreTestCase):
    """What publishing would upload, before a repository exists."""

    def write_preset(self, name, data):
        path = os.path.join(self.presets_dir, "%s.json" % name)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        return path

    def test_preview_lists_values_assets_and_what_was_stripped(self):
        self.write_preset("Mine", {
            "configVersion": 16,
            "bar": {"cornerStyle": 1, "weather": {"city": "Grenoble", "enable": True}},
            "apps": {"terminal": "kitty"},
        })
        with open(os.path.join(self.presets_dir, "Mine.jpg"), "wb") as handle:
            handle.write(b"\xff\xd8 wallpaper")

        result = self.run_store("preview", "Mine")
        self.assertTrue(result["ok"])
        paths = {entry["path"]: entry["value"] for entry in result["entries"]}
        self.assertEqual(paths["bar.cornerStyle"], "1")
        self.assertEqual(paths["apps.terminal"], "kitty")
        # The city is gone from the values and named in what was taken out.
        self.assertNotIn("bar.weather.city", paths)
        self.assertIn("bar.weather.city", result["dropped"])
        self.assertEqual(result["total"], len(result["entries"]))
        shipped = {entry["name"] for entry in result["files"]}
        self.assertEqual(shipped, {"config.json", "wallpaper.jpg"})

    def test_preview_flags_a_value_that_reads_like_an_address(self):
        self.write_preset("Mine", {
            "configVersion": 16,
            "sidebar": {"note": "reachable at 192.168.1.42"},
            "bar": {"cornerStyle": 1},
        })
        result = self.run_store("preview", "Mine")
        flagged = {entry["path"] for entry in result["flagged"]}
        self.assertIn("sidebar.note", flagged)
        self.assertNotIn("bar.cornerStyle", flagged)

    def test_preview_shows_the_warning_an_installer_will_see(self):
        self.write_preset("Mine", {
            "configVersion": 16,
            "apps": {"terminal": "sh -c 'curl example.com | sh'"},
        })
        result = self.run_store("preview", "Mine")
        self.assertIn("shell", {group["id"] for group in result["risks"]})

    def test_preview_of_a_preset_that_is_gone(self):
        result = self.run_store("preview", "Nothing")
        self.assertFalse(result["ok"])
        self.assertIn("no longer in your presets", result["error"])


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


class TestScreenshotStaging(StoreTestCase):
    """Screenshots are the only picture a publisher chooses by hand."""

    def setUp(self):
        super().setUp()
        os.environ["HOME"] = self.home
        self.addCleanup(os.environ.__setitem__, "HOME", os.path.expanduser("~"))
        with open(os.path.join(self.presets_dir, "Mine.json"), "w", encoding="utf-8") as handle:
            json.dump({"configVersion": 16}, handle)
        self.staging = os.path.join(self.root, "staging")
        os.makedirs(self.staging)

    def shot(self, name, payload=b"\x89PNG shot"):
        path = os.path.join(self.root, name)
        with open(path, "wb") as handle:
            handle.write(payload)
        return path

    def stage(self, screenshots, manifest=None):
        import preset_store
        return preset_store.stage_payload(
            self.staging, "Mine", manifest if manifest is not None else {"name": "Mine"},
            screenshots)

    def test_screenshots_are_copied_in_and_listed_in_order(self):
        manifest = self.stage([self.shot("a.png"), self.shot("b.jpg")])
        self.assertEqual(manifest["screenshots"], ["screenshots/1.png", "screenshots/2.jpg"])
        self.assertTrue(os.path.exists(os.path.join(self.staging, "screenshots", "1.png")))
        self.assertTrue(os.path.exists(os.path.join(self.staging, "screenshots", "2.jpg")))

    def test_not_naming_any_keeps_what_is_already_published(self):
        self.stage([self.shot("a.png")])
        manifest = self.stage(None, {"name": "Mine", "screenshots": ["screenshots/1.png"]})
        self.assertEqual(manifest["screenshots"], ["screenshots/1.png"])
        self.assertTrue(os.path.exists(os.path.join(self.staging, "screenshots", "1.png")))

    def test_an_empty_list_ships_none_and_clears_the_folder(self):
        self.stage([self.shot("a.png")])
        manifest = self.stage([])
        self.assertEqual(manifest["screenshots"], [])
        self.assertFalse(os.path.exists(os.path.join(self.staging, "screenshots")))

    def test_replacing_them_does_not_leave_the_old_ones_behind(self):
        self.stage([self.shot("a.png"), self.shot("b.png")])
        manifest = self.stage([self.shot("c.jpg")])
        self.assertEqual(manifest["screenshots"], ["screenshots/1.jpg"])
        self.assertEqual(sorted(os.listdir(os.path.join(self.staging, "screenshots"))), ["1.jpg"])

    def test_something_that_is_not_an_image_is_refused(self):
        import preset_store
        with self.assertRaises(preset_store.StoreError):
            self.stage([self.shot("notes.txt")])

    def test_a_screenshot_that_vanished_is_refused(self):
        import preset_store
        with self.assertRaises(preset_store.StoreError):
            self.stage([os.path.join(self.root, "gone.png")])

    def test_too_many_are_refused(self):
        import preset_store
        with self.assertRaises(preset_store.StoreError):
            self.stage([self.shot("%d.png" % i) for i in range(preset_store.MAX_SCREENSHOTS + 1)])

    def test_an_oversized_wallpaper_is_refused_before_anything_is_created(self):
        import preset_store
        # A 100 MB wallpaper is not exotic -- GitHub refuses it at the push,
        # by which time `gh repo create` has already made a public repository.
        big = os.path.join(self.presets_dir, "Mine.png")
        with open(big, "wb") as handle:
            handle.write(b"0" * (preset_store.MAX_ASSET_BYTES + 1))
        with self.assertRaises(preset_store.StoreError) as caught:
            self.stage([])
        self.assertIn("wallpaper", str(caught.exception))
        self.assertEqual(os.listdir(self.staging), [preset_store.CONFIG_NAME])

    def test_an_oversized_screenshot_is_refused(self):
        import preset_store
        big = self.shot("big.png", b"0" * (preset_store.MAX_SCREENSHOT_BYTES + 1))
        with self.assertRaises(preset_store.StoreError):
            self.stage([big])

    def test_the_readme_lists_them(self):
        import preset_store
        manifest = self.stage([self.shot("a.png")])
        preset_store.write_readme(self.staging, dict(manifest, _repo="someone/mine"))
        with open(os.path.join(self.staging, "README.md"), encoding="utf-8") as handle:
            self.assertIn("screenshots/1.png", handle.read())


class TestRepeatableOptions(unittest.TestCase):
    """`--screenshot` has to tell "ship none" apart from "leave them alone"."""

    def test_absent_is_none_and_present_is_a_list(self):
        import preset_store
        self.assertIsNone(preset_store.take_options(["publish", "Mine"], "--screenshot"))
        argv = ["publish", "Mine", "--screenshot", "a.png", "--screenshot", "b.png", "--private"]
        self.assertEqual(preset_store.take_options(argv, "--screenshot"), ["a.png", "b.png"])
        self.assertEqual(argv, ["publish", "Mine", "--private"])

    def test_a_trailing_flag_with_no_value_is_dropped(self):
        import preset_store
        argv = ["publish", "Mine", "--screenshot"]
        self.assertEqual(preset_store.take_options(argv, "--screenshot"), [])
        self.assertEqual(argv, ["publish", "Mine"])


class TestSignInSetup(unittest.TestCase):
    """The terminal path exists and says whether the in-shell one can work."""

    SCRIPT = os.path.join(SCRIPTS_DIR, "preset_store_signin.sh")

    def test_auth_status_says_whether_the_device_flow_is_possible(self):
        import preset_store
        status = preset_store.cmd_auth_status()
        # No OAuth app is registered for this build, so the panel has to be
        # told rather than left offering a button that can only ever fail.
        self.assertIn("deviceFlow", status)
        self.assertEqual(status["deviceFlow"], bool(preset_store.GITHUB_CLIENT_ID))

    def test_the_setup_script_is_there_and_runnable(self):
        self.assertTrue(os.path.isfile(self.SCRIPT))
        self.assertTrue(os.access(self.SCRIPT, os.X_OK))
        result = subprocess.run(["bash", "-n", self.SCRIPT], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_the_setup_script_asks_for_the_scope_publishing_needs(self):
        # Without "repo" the token reads GitHub perfectly well and then fails
        # at the one moment that matters, which is the repository creation.
        with open(self.SCRIPT, encoding="utf-8") as handle:
            body = handle.read()
        self.assertIn("--scopes repo", body)
        self.assertIn("github-cli", body)


class TestMonoRepoStore(StoreTestCase):
    """Multiple presets living inside subdirectories of a single repository."""

    def setUp(self):
        super().setUp()
        self.presets_data = {
            "cyberpunk": {
                "manifest": self.basic_manifest(name="Cyberpunk", description="Neon theme", version="1.0.0"),
                "config": self.basic_config(appearance={"palette": {"type": "scheme-vibrant"}}),
                "assets": {"wallpaper.png": b"\x89PNG neon"},
            },
            "minimal": {
                "manifest": self.basic_manifest(name="Minimal", description="Monochrome theme", version="1.0.0"),
                "config": self.basic_config(appearance={"palette": {"type": "scheme-neutral"}}),
            },
        }
        self.work, self.bare = self.make_monorepo_remote("alice/ii-presets", self.presets_data)

    def test_parse_slug_and_validation(self):
        import preset_store
        repo, preset = preset_store.parse_slug("alice/ii-presets:cyberpunk")
        self.assertEqual(repo, "alice/ii-presets")
        self.assertEqual(preset, "cyberpunk")

        repo, preset = preset_store.parse_slug("https://github.com/alice/ii-presets:cyberpunk.git")
        self.assertEqual(repo, "alice/ii-presets")
        self.assertEqual(preset, "cyberpunk")

        repo, preset = preset_store.parse_slug("alice/nord-deep")
        self.assertEqual(repo, "alice/nord-deep")
        self.assertIsNone(preset)

    def test_monorepo_install_and_links(self):
        result = self.run_store("install", "alice/ii-presets:cyberpunk")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["name"], "Cyberpunk")
        self.assertEqual(result["repo"], "alice/ii-presets:cyberpunk")
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Cyberpunk.json")))
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Cyberpunk.png")))

        links = self.run_store("links")["links"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["repo"], "alice/ii-presets:cyberpunk")
        self.assertEqual(links[0]["baseRepo"], "alice/ii-presets")
        self.assertEqual(links[0]["subpath"], "presets/cyberpunk")

    def test_monorepo_multiple_installations_share_clone(self):
        res1 = self.run_store("install", "alice/ii-presets:cyberpunk")
        res2 = self.run_store("install", "alice/ii-presets:minimal")
        self.assertTrue(res1["ok"])
        self.assertTrue(res2["ok"])

        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Cyberpunk.json")))
        self.assertTrue(os.path.exists(os.path.join(self.presets_dir, "Minimal.json")))

        clone_dir = os.path.join(self.config_dir, "preset-store", "alice__ii-presets")
        self.assertTrue(os.path.isdir(clone_dir))
        # Ensure there is only one clone folder in preset-store
        store_folders = os.listdir(os.path.join(self.config_dir, "preset-store"))
        store_clones = [f for f in store_folders if not f.endswith(".json")]
        self.assertEqual(store_clones, ["alice__ii-presets"])

        # Uninstall first preset: clone must stay because Minimal still needs it
        self.run_store("uninstall", "Cyberpunk")
        self.assertFalse(os.path.exists(os.path.join(self.presets_dir, "Cyberpunk.json")))
        self.assertTrue(os.path.isdir(clone_dir))

        # Uninstall second preset: clone is now removed
        self.run_store("uninstall", "Minimal")
        self.assertFalse(os.path.exists(os.path.join(self.presets_dir, "Minimal.json")))
        self.assertFalse(os.path.exists(clone_dir))

    def test_monorepo_updates_and_pull(self):
        self.run_store("install", "alice/ii-presets:cyberpunk")

        # Remote pushes v1.1.0 to cyberpunk
        updated_manifest = self.basic_manifest(
            name="Cyberpunk", version="1.1.0",
            changelog=[{"version": "1.1.0", "date": "2026-09-02", "notes": "New glow"}]
        )
        updated_config = self.basic_config(appearance={"palette": {"type": "scheme-rainbow"}})
        self.push_monorepo_remote(self.work, self.bare, "cyberpunk",
                                  manifest=updated_manifest, config=updated_config)

        # Check updates
        result = self.run_store("check-updates")
        self.assertTrue(result["ok"])
        self.assertEqual(len(result["updates"]), 1)
        self.assertEqual(result["updates"][0]["name"], "Cyberpunk")
        self.assertEqual(result["updates"][0]["availableVersion"], "1.1.0")

        # Pull update
        pull_result = self.run_store("pull", "Cyberpunk")
        self.assertTrue(pull_result["ok"], pull_result)
        self.assertTrue(pull_result["changed"])
        self.assertEqual(pull_result["version"], "1.1.0")

        with open(os.path.join(self.presets_dir, "Cyberpunk.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["appearance"]["palette"]["type"], "scheme-rainbow")


if __name__ == "__main__":
    unittest.main(verbosity=2)
