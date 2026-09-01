#!/usr/bin/env python3
"""Deterministic tests for the local Mozilla browser-sites backend."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = ROOT / "scripts" / "browser_sites_helper.py"
QML_PATH = ROOT / "services" / "BrowserSites.qml"


def load_helper():
    spec = importlib.util.spec_from_file_location("browser_sites_helper", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load browser_sites_helper")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def create_places(profile: Path, mtime: float, rows=(), bookmark_ids=()) -> Path:
    profile.mkdir(parents=True, exist_ok=True)
    database = profile / "places.sqlite"
    with closing(sqlite3.connect(database)) as connection, connection:
        connection.executescript(
            """
            CREATE TABLE moz_places (
                id INTEGER PRIMARY KEY,
                url TEXT,
                title TEXT,
                frecency INTEGER
            );
            CREATE TABLE moz_bookmarks (
                id INTEGER PRIMARY KEY,
                fk INTEGER,
                type INTEGER,
                title TEXT
            );
            """
        )
        connection.executemany(
            "INSERT INTO moz_places(id, url, title, frecency) VALUES (?, ?, ?, ?)",
            rows,
        )
        connection.executemany(
            "INSERT INTO moz_bookmarks(id, fk, type, title) VALUES (?, ?, 1, NULL)",
            [(index + 1, place_id) for index, place_id in enumerate(bookmark_ids)],
        )
    os.utime(database, (mtime, mtime))
    return database


def write_profiles_ini(directory: Path, text: str) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    ini = directory / "profiles.ini"
    ini.write_text(text.strip() + "\n", encoding="utf-8")
    return ini


class BrowserSitesDiscoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = load_helper()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_install_default_wins_over_conflicting_profile_default(self) -> None:
        browser = self.home / ".browser"
        install = browser / "Profiles" / "active"
        misleading = browser / "Profiles" / "abandoned"
        create_places(install, 100)
        create_places(misleading, 200)
        ini = write_profiles_ini(
            browser,
            """
            [InstallABC]
            Default=Profiles/active

            [Profile0]
            Name=Abandoned
            IsRelative=1
            Path=Profiles/abandoned
            Default=1
            """,
        )

        resolved = self.helper.resolve_profiles_ini(ini)

        self.assertEqual(resolved.profile_path, install.resolve())

    def test_multiple_install_defaults_choose_newest_places_mtime(self) -> None:
        browser = self.home / ".browser"
        old = browser / "old"
        current = browser / "current"
        create_places(old, 100)
        create_places(current, 300)
        ini = write_profiles_ini(
            browser,
            """
            [InstallA]
            Default=old
            [InstallB]
            Default=current
            """,
        )

        resolved = self.helper.resolve_profiles_ini(ini)

        self.assertEqual(resolved.profile_path, current.resolve())

    def test_profile_default_then_newest_profile_fallback(self) -> None:
        browser = self.home / ".browser"
        default = browser / "default"
        newer = browser / "newer"
        create_places(default, 100)
        create_places(newer, 300)
        default_ini = write_profiles_ini(
            browser,
            """
            [Profile0]
            IsRelative=1
            Path=default
            Default=1
            [Profile1]
            IsRelative=1
            Path=newer
            """,
        )
        self.assertEqual(
            self.helper.resolve_profiles_ini(default_ini).profile_path,
            default.resolve(),
        )

        no_default = self.home / ".other"
        older = no_default / "older"
        newest = no_default / "newest"
        create_places(older, 400)
        create_places(newest, 600)
        fallback_ini = write_profiles_ini(
            no_default,
            """
            [Profile0]
            IsRelative=1
            Path=older
            [Profile1]
            IsRelative=1
            Path=newest
            """,
        )
        self.assertEqual(
            self.helper.resolve_profiles_ini(fallback_ini).profile_path,
            newest.resolve(),
        )

    def test_global_discovery_chooses_newest_and_override_is_authoritative(self) -> None:
        first_root = self.home / ".first"
        first = first_root / "profile"
        create_places(first, 100)
        write_profiles_ini(
            first_root,
            """
            [Profile0]
            IsRelative=1
            Path=profile
            Default=1
            """,
        )

        flatpak_root = self.home / ".var" / "app" / "org.example.Browser" / ".mozilla"
        second = flatpak_root / "profile"
        create_places(second, 900)
        write_profiles_ini(
            flatpak_root,
            """
            [Profile0]
            IsRelative=1
            Path=profile
            Default=1
            """,
        )

        detected = self.helper.discover_profile(self.home)
        overridden = self.helper.discover_profile(self.home, override=str(first))

        self.assertEqual(detected.profile_path, second.resolve())
        self.assertEqual(overridden.profile_path, first.resolve())
        self.assertIsNone(
            self.helper.discover_profile(self.home, override=str(self.home / "missing"))
        )


class BrowserSitesIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = load_helper()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.profile = self.root / "profile"
        self.rows = [
            (1, "https://example.com/docs", "Example docs", 40),
            (2, "https://rooted.test/", "Root bookmark", 20),
            (3, "https://example.com/article", "Example article", 1000),
            (4, "https://duplicate.test/a", "Duplicate A", 100),
            (5, "https://duplicate.test/b", "Duplicate B", 200),
            (6, "https://rooted.test/news", "Rooted news", 500),
            (7, "ftp://ignored.test/file", "FTP", 900),
            (8, "https://empty-title.test/", "", 800),
            (9, "https://zero.test/", "Zero", 0),
        ]
        self.places = create_places(self.profile, 100, self.rows, [1, 2])

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_index_keeps_all_bookmarks_limits_and_collapses_history(self) -> None:
        sites = self.helper.build_index(
            self.places, include_history=True, max_indexed_sites=2
        )

        by_url = {site["url"]: site for site in sites}
        self.assertIn("https://example.com/docs", by_url)
        self.assertTrue(by_url["https://example.com/docs"]["bookmarked"])
        self.assertEqual(by_url["https://example.com/docs"]["source"], "favorite")
        self.assertIn("https://rooted.test/", by_url)
        self.assertIn("https://example.com/", by_url)
        self.assertIn("https://duplicate.test/", by_url)
        self.assertEqual(by_url["https://duplicate.test/"]["frecency"], 200)
        self.assertEqual(by_url["https://duplicate.test/"]["title"], "Duplicate B")
        self.assertEqual(by_url["https://duplicate.test/"]["source"], "suggested")
        self.assertNotIn("https://rooted.test/news", by_url)
        self.assertEqual(len([site for site in sites if not site["bookmarked"]]), 2)
        self.assertEqual(len(sites), len(set(by_url)))

    def test_include_history_false_returns_only_bookmarks(self) -> None:
        sites = self.helper.build_index(
            self.places, include_history=False, max_indexed_sites=50
        )

        self.assertEqual(
            {site["url"] for site in sites},
            {"https://example.com/docs", "https://rooted.test/"},
        )
        self.assertTrue(all(site["bookmarked"] for site in sites))

    def test_bookmarks_ignore_history_filters_and_use_title_fallback_order(self) -> None:
        with closing(sqlite3.connect(self.places)) as connection, connection:
            connection.executemany(
                "INSERT INTO moz_places(id, url, title, frecency) VALUES (?, ?, ?, ?)",
                [
                    (10, "https://zero-bookmark.test/saved", None, 0),
                    (11, "https://negative-bookmark.test/saved", "Places title", -1),
                    (12, "https://places-fallback.test/saved", "Places fallback", 0),
                    (13, "https://host-fallback.test/saved", None, -1),
                ],
            )
            connection.executemany(
                "INSERT INTO moz_bookmarks(id, fk, type, title) VALUES (?, ?, 1, ?)",
                [
                    (10, 10, "Zero bookmark"),
                    (11, 11, "Named bookmark"),
                    (12, 12, ""),
                    (13, 13, None),
                    # Multiple bookmark rows for one place still project one URL.
                    (14, 10, ""),
                ],
            )

        sites = self.helper.build_index(
            self.places, include_history=False, max_indexed_sites=0
        )
        by_url = {site["url"]: site for site in sites}

        self.assertEqual(by_url["https://zero-bookmark.test/saved"]["title"], "Zero bookmark")
        self.assertEqual(by_url["https://zero-bookmark.test/saved"]["frecency"], 0)
        self.assertEqual(by_url["https://negative-bookmark.test/saved"]["title"], "Named bookmark")
        self.assertEqual(by_url["https://negative-bookmark.test/saved"]["frecency"], -1)
        self.assertEqual(by_url["https://places-fallback.test/saved"]["title"], "Places fallback")
        self.assertEqual(by_url["https://host-fallback.test/saved"]["title"], "host-fallback.test")
        self.assertEqual(
            sum(site["url"] == "https://zero-bookmark.test/saved" for site in sites),
            1,
        )

    def test_sqlite_is_opened_only_through_an_immutable_uri(self) -> None:
        with patch.object(
            self.helper.sqlite3, "connect", wraps=sqlite3.connect
        ) as connect:
            self.helper.build_index(
                self.places, include_history=False, max_indexed_sites=1
            )

        self.assertEqual(connect.call_count, 1)
        args, kwargs = connect.call_args
        self.assertTrue(args[0].endswith("?immutable=1"))
        self.assertIs(kwargs["uri"], True)

    def test_history_cursor_stops_after_collecting_the_requested_hosts(self) -> None:
        class TrackingRows:
            def __init__(self):
                self.rows = iter(
                    [
                        ("First", "https://first.test/page", 100),
                        ("Second", "https://second.test/page", 90),
                        ("Third", "https://third.test/page", 80),
                    ]
                )
                self.consumed = 0

            def __iter__(self):
                return self

            def __next__(self):
                row = next(self.rows)
                self.consumed += 1
                return row

        history_rows = TrackingRows()

        class FakeConnection:
            def execute(self, query):
                if "JOIN moz_places AS p" in query:
                    return iter(())
                return history_rows

            def close(self):
                return None

        with patch.object(
            self.helper, "_connect_immutable", return_value=FakeConnection()
        ):
            sites = self.helper.build_index(
                self.places, include_history=True, max_indexed_sites=1
            )

        self.assertEqual(len(sites), 1)
        self.assertEqual(sites[0]["host"], "first.test")
        self.assertEqual(history_rows.consumed, 1)


class BrowserSitesOpenTabsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = load_helper()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.profile = Path(self.temp.name) / "profile"
        (self.profile / "sessionstore-backups").mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def literal_mozlz4(value: object) -> bytes:
        payload = json.dumps(value, separators=(",", ":")).encode()
        length = len(payload)
        block = bytearray([min(15, length) << 4])
        if length >= 15:
            remaining = length - 15
            while remaining >= 255:
                block.append(255)
                remaining -= 255
            block.append(remaining)
        block.extend(payload)
        return b"mozLz40\0" + length.to_bytes(4, "little") + bytes(block)

    def write_session(self, value: object) -> Path:
        path = self.profile / "sessionstore-backups" / "recovery.jsonlz4"
        path.write_bytes(self.literal_mozlz4(value))
        return path

    def test_reads_current_http_tabs_and_deduplicates_exact_urls(self) -> None:
        self.write_session({
            "windows": [
                {
                    "selected": 2,
                    "tabs": [
                        {
                            "index": 1,
                            "pinned": True,
                            "lastAccessed": 10,
                            "entries": [{"url": "https://example.test/a", "title": "Older"}],
                        },
                        {
                            "index": 2,
                            "lastAccessed": 30,
                            "entries": [
                                {"url": "https://old.test/", "title": "Old"},
                                {"url": "https://example.test/a", "title": "Selected"},
                            ],
                        },
                        {
                            "index": 1,
                            "entries": [{"url": "about:blank", "title": "Blank"}],
                        },
                    ],
                }
            ]
        })

        tabs = self.helper.read_open_tabs(self.profile)

        self.assertEqual(len(tabs), 1)
        self.assertEqual(tabs[0]["url"], "https://example.test/a")
        self.assertEqual(tabs[0]["title"], "Selected")
        self.assertEqual(tabs[0]["source"], "open")
        self.assertTrue(tabs[0]["selected"])
        self.assertEqual(tabs[0]["tabCount"], 2)

    def test_merge_prioritizes_open_exact_url_and_hides_same_host_suggestion(self) -> None:
        opened = [{
            "title": "Open article", "url": "https://example.test/a",
            "host": "example.test", "path": "/a", "frecency": 0,
            "bookmarked": False, "source": "open", "selected": True,
            "pinned": False, "lastAccessed": 20, "tabCount": 1,
        }]
        indexed = [
            {
                "title": "Saved article", "url": "https://example.test/a",
                "host": "example.test", "path": "/a", "frecency": 90,
                "bookmarked": True, "source": "favorite",
            },
            {
                "title": "Example history", "url": "https://example.test/",
                "host": "example.test", "path": "/", "frecency": 100,
                "bookmarked": False, "source": "suggested",
            },
            {
                "title": "Other", "url": "https://other.test/",
                "host": "other.test", "path": "/", "frecency": 50,
                "bookmarked": False, "source": "suggested",
            },
        ]

        merged = self.helper.merge_site_sources(opened, indexed)

        self.assertEqual([site["source"] for site in merged], ["open", "suggested"])
        self.assertTrue(merged[0]["bookmarked"])
        self.assertEqual(merged[0]["frecency"], 90)
        self.assertEqual(merged[1]["host"], "other.test")


class BrowserSitesFaviconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = load_helper()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.profile = self.root / "profile"
        self.profile.mkdir()
        self.cache = self.root / "cache"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_modern_favicon_schema_picks_largest_at_most_64_and_sha1_cache(self) -> None:
        database = self.profile / "favicons.sqlite"
        blobs = {16: b"icon-16", 64: b"icon-64", 128: b"icon-128"}
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.executescript(
                """
                CREATE TABLE moz_icons (
                    id INTEGER PRIMARY KEY,
                    icon_url TEXT,
                    width INTEGER,
                    data BLOB
                );
                CREATE TABLE moz_pages_w_icons (
                    id INTEGER PRIMARY KEY,
                    page_url TEXT
                );
                CREATE TABLE moz_icons_to_pages (
                    page_id INTEGER,
                    icon_id INTEGER
                );
                INSERT INTO moz_pages_w_icons(id, page_url)
                VALUES (1, 'https://example.com/docs');
                """
            )
            for icon_id, width in enumerate((16, 64, 128), start=1):
                connection.execute(
                    "INSERT INTO moz_icons(id, icon_url, width, data) VALUES (?, ?, ?, ?)",
                    (icon_id, f"https://example.com/favicon-{width}.png", width, blobs[width]),
                )
                connection.execute(
                    "INSERT INTO moz_icons_to_pages(page_id, icon_id) VALUES (1, ?)",
                    (icon_id,),
                )

        extracted = self.helper.extract_favicon(
            self.profile, "https://example.com/docs", self.cache, max_cache_entries=8
        )

        expected = self.cache / (hashlib.sha1(b"example.com").hexdigest() + ".png")
        self.assertEqual(extracted, expected)
        self.assertEqual(expected.read_bytes(), blobs[64])
        self.assertFalse(any(path.name.startswith(".") for path in self.cache.iterdir()))

    def test_favicon_size_wins_globally_before_page_association(self) -> None:
        database = self.profile / "favicons.sqlite"
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.executescript(
                """
                CREATE TABLE moz_icons (
                    id INTEGER PRIMARY KEY,
                    icon_url TEXT,
                    width INTEGER,
                    data BLOB
                );
                CREATE TABLE moz_pages_w_icons (
                    id INTEGER PRIMARY KEY,
                    page_url TEXT
                );
                CREATE TABLE moz_icons_to_pages (
                    page_id INTEGER,
                    icon_id INTEGER
                );
                INSERT INTO moz_pages_w_icons(id, page_url) VALUES
                    (1, 'https://example.com/docs'),
                    (2, 'https://example.com/');
                INSERT INTO moz_icons(id, icon_url, width, data) VALUES
                    (1, 'https://example.com/exact-16.png', 16, X'65786163742D3136'),
                    (2, 'https://example.com/root-64.png', 64, X'726F6F742D3634');
                INSERT INTO moz_icons_to_pages(page_id, icon_id) VALUES
                    (1, 1),
                    (2, 2);
                """
            )

        extracted = self.helper.extract_favicon(
            self.profile, "https://example.com/docs", self.cache
        )

        self.assertIsNotNone(extracted)
        self.assertEqual(extracted.read_bytes(), b"root-64")

    def test_favicon_missing_or_unknown_schema_fails_safely(self) -> None:
        with closing(sqlite3.connect(self.profile / "favicons.sqlite")) as connection, connection:
            connection.execute("CREATE TABLE unrelated (id INTEGER)")

        self.assertIsNone(
            self.helper.extract_favicon(
                self.profile, "https://example.com/", self.cache
            )
        )
        self.assertIsNone(
            self.helper.extract_favicon(
                self.root / "missing-profile", "https://example.com/", self.cache
            )
        )

    def test_favicon_scan_keeps_only_the_current_best_blob(self) -> None:
        source = HELPER_PATH.read_text(encoding="utf-8")
        favicon_scan = source.split("def _favicon_bytes", 1)[1].split(
            "def _prune_favicon_cache", 1
        )[0]

        self.assertIn("best_key", favicon_scan)
        self.assertIn("best_data", favicon_scan)
        self.assertNotIn("candidates.append", favicon_scan)


class BrowserSitesPrivateWindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.helper = load_helper()

    def test_private_support_requires_literal_flag_in_default_handler_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            data = root / "data"
            applications = data / "applications"
            applications.mkdir(parents=True)
            config.mkdir()
            (config / "mimeapps.list").write_text(
                """
                [Default Applications]
                x-scheme-handler/https=generic-browser.desktop;
                x-scheme-handler/http=generic-browser.desktop;
                """.strip()
                + "\n",
                encoding="utf-8",
            )
            desktop = applications / "generic-browser.desktop"
            desktop.write_text(
                """
                [Desktop Entry]
                Type=Application
                Exec=/opt/browser/bin/browser %u

                [Desktop Action private]
                Exec=/opt/browser/bin/browser --private-window %u
                """.strip()
                + "\n",
                encoding="utf-8",
            )

            support = self.helper.discover_private_window(
                config_home=config, data_home=data, data_dirs=[]
            )
            self.assertTrue(support.supported)
            self.assertEqual(
                support.command,
                ["/opt/browser/bin/browser", "--private-window", "__URL__"],
            )

            desktop.write_text(
                "[Desktop Entry]\nType=Application\nExec=/opt/browser/bin/browser %u\n",
                encoding="utf-8",
            )
            unsupported = self.helper.discover_private_window(
                config_home=config, data_home=data, data_dirs=[]
            )
            self.assertFalse(unsupported.supported)
            self.assertEqual(unsupported.command, [])

    def test_real_environment_uses_xdg_mime_as_authoritative_handler(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            data = root / "data"
            applications = data / "applications"
            applications.mkdir(parents=True)
            config.mkdir()
            (config / "mimeapps.list").write_text(
                "[Default Applications]\n"
                "x-scheme-handler/https=fallback.desktop;\n",
                encoding="utf-8",
            )
            (applications / "fallback.desktop").write_text(
                "[Desktop Entry]\nExec=/fallback --private-window %u\n",
                encoding="utf-8",
            )
            (applications / "authoritative.desktop").write_text(
                "[Desktop Entry]\nExec=/authoritative --private-window %u\n",
                encoding="utf-8",
            )

            environment = {
                "XDG_CONFIG_HOME": str(config),
                "XDG_DATA_HOME": str(data),
                "XDG_DATA_DIRS": "",
            }
            with patch.dict(os.environ, environment), patch.object(
                self.helper,
                "_default_handler_from_xdg_mime",
                return_value="authoritative.desktop",
            ):
                support = self.helper.discover_private_window()

            self.assertEqual(support.desktop_id, "authoritative.desktop")
            self.assertEqual(
                support.command,
                ["/authoritative", "--private-window", "__URL__"],
            )


class BrowserSitesQmlContractTests(unittest.TestCase):
    def test_file_utils_dependency_is_imported(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")

        self.assertIn("import qs.modules.common.functions", qml)
        self.assertIn("FileUtils.trimFileProtocol", qml)

    def test_matching_is_in_memory_and_process_free(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")
        matching = qml.split("function matchSites", 1)[1].split(
            "function requestFavicon", 1
        )[0]

        self.assertIn("root.sites", matching)
        self.assertIn("maxResults", matching)
        self.assertIn("site?.host", qml)
        self.assertIn("site?.title", qml)
        self.assertIn("site?.path", qml)
        self.assertNotIn("Process", matching)
        self.assertNotIn(".running", matching)
        self.assertIn('if (normalizedQuery.length === 0)', matching)

    def test_qml_owns_refresh_debounce_state_and_serial_favicon_queue(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")

        for exposed in (
            "property bool ready",
            "property bool loading",
            "property string error",
            "property string profilePath",
            "property var sites",
            "property int revision",
        ):
            self.assertIn(exposed, qml)
        self.assertIn("id: rebuildDebounce", qml)
        self.assertIn("id: refreshTimer", qml)
        self.assertIn("placesMtime", qml)
        self.assertIn("lastBuildAt", qml)
        self.assertIn("mtimeChanged", qml)
        self.assertIn("intervalElapsed", qml)
        self.assertIn("id: faviconProcess", qml)
        self.assertIn("property var faviconQueue", qml)
        self.assertIn("if (faviconProcess.running", qml)
        self.assertIn("function requestFavicon", qml)
        self.assertIn("function faviconFor", qml)
        self.assertIn("function openPrivateWindow", qml)
        self.assertIn("privateBrowsingSupported", qml)
        self.assertIn("allowRemoteFavicons", qml)
        self.assertIn("google.com/s2/favicons", qml)
        self.assertIn("Component.onCompleted", qml)

    def test_refresh_guard_does_not_make_status_process_unreachable(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")
        refresh_body = qml.split("function checkForRefresh()", 1)[1].split(
            "function finishRefreshCheck()", 1
        )[0]

        self.assertEqual(refresh_body.count("return;"), 1)
        self.assertIn("statusProcess.generation = root.buildGeneration", refresh_body)
        self.assertIn("statusProcess.signature = root.configSignature", refresh_body)
        self.assertIn('statusProcess.command = root.buildCommand("status")', refresh_body)
        self.assertIn("statusProcess.running = true", refresh_body)
        self.assertLess(
            refresh_body.index("return;"),
            refresh_body.index("statusProcess.generation = root.buildGeneration"),
        )

    def test_build_failures_retry_with_backoff_without_ready_gate(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")
        retry_timer = qml.split("id: buildRetryTimer", 1)[1].split("Process {", 1)[0]

        self.assertIn("property int buildRetryAttempt", qml)
        self.assertIn("function scheduleBuildRetry", qml)
        self.assertIn("id: buildRetryTimer", qml)
        self.assertIn("onTriggered: root.startBuild", retry_timer)
        self.assertNotIn("root.ready", retry_timer)
        self.assertIn("Math.pow(2", qml)

    def test_build_results_are_signed_and_config_changes_clear_immediately(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")
        invalidation = qml.split("function invalidateForConfigChange", 1)[1].split(
            "function startBuild", 1
        )[0]

        self.assertIn("readonly property string configSignature", qml)
        for setting in (
            "root.enabled",
            "root.configuredProfilePath",
            "root.maxIndexedSites",
            "root.includeHistory",
            "root.useLocalFavicons",
        ):
            self.assertIn(setting, qml)
        self.assertIn("property int buildGeneration", qml)
        self.assertIn("property int generation", qml)
        self.assertIn("property string signature", qml)
        self.assertIn("property bool periodicRefresh", qml)
        self.assertIn("function invalidateForConfigChange", qml)
        self.assertIn("onConfigSignatureChanged: root.invalidateForConfigChange()", qml)
        self.assertIn("root.clearPublishedIndex()", invalidation)
        self.assertIn("buildProcess.generation !== root.buildGeneration", qml)
        self.assertIn("buildProcess.signature !== root.configSignature", qml)
        self.assertIn("buildProcess.periodicRefresh", qml)
        self.assertIn("&& buildProcess.hadReady", qml)

    def test_negative_favicon_cache_uses_backoff_and_resets_on_rebuild(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")

        self.assertIn("property var faviconFailures", qml)
        self.assertIn("faviconFailureBaseMs", qml)
        self.assertIn("retryAfter", qml)
        self.assertIn("Date.now() < failure.retryAfter", qml)
        self.assertIn("Math.pow(2", qml)
        self.assertIn("function resetFaviconFailures", qml)
        self.assertIn("delete queued[active.host]", qml)

    def test_open_tabs_refresh_from_sessionstore_mtime_out_of_process(self) -> None:
        qml = QML_PATH.read_text(encoding="utf-8")

        self.assertIn("property real sessionMtime", qml)
        self.assertIn("candidateSessionMtime", qml)
        self.assertIn("sessionMtimeChanged", qml)
        self.assertIn("sessionMtimeChanged || (intervalElapsed && mtimeChanged)", qml)
        self.assertIn("readonly property int openTabsRefreshMs: 60000", qml)
        self.assertIn("Math.min(root.openTabsRefreshMs, root.refreshIntervalMs)", qml)
        self.assertIn('if (site?.source === "open")', qml)


if __name__ == "__main__":
    unittest.main()
