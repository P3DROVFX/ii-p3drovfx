#!/usr/bin/env python3
"""Static contracts for BrowserSites in the normal Search result pipeline."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def qml_object_containing(text: str, marker: str) -> str:
    """Return the balanced QML object whose declaration contains *marker*."""
    marker_index = text.index(marker)
    opening_brace = text.rfind("{", 0, marker_index)
    self_start = text.rfind("\n", 0, opening_brace) + 1
    depth = 0
    quote = ""
    escaped = False

    for index in range(opening_brace, len(text)):
        char = text[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ('"', "'"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[self_start : index + 1]

    raise AssertionError(f"Unbalanced QML object containing {marker!r}")


class BrowserSitesSearchIntegrationTests(unittest.TestCase):
    def test_launcher_observes_revision_and_builds_complete_site_results(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        factory = launcher.split("function createBrowserSiteResult", 1)[1].split(
            "function createAppResultObject", 1
        )[0]

        self.assertIn("readonly property int browserSitesRevision: BrowserSites.revision", launcher)
        self.assertIn("onBrowserSitesRevisionChanged: root._scheduleResultsUpdate()", launcher)
        self.assertIn('key: "site:" + url', factory)
        self.assertIn("name: title", factory)
        self.assertIn("const title = String(site?.title || site?.host || url)", factory)
        self.assertIn("comment: detail", factory)
        self.assertIn('siteSource === "open"', factory)
        self.assertIn('Translation.tr("Open tab")', factory)
        self.assertIn('verb: Translation.tr("Open")', factory)
        self.assertIn("pinnable: false", factory)
        self.assertIn("BrowserSites.faviconFor(site)", factory)
        self.assertIn("LauncherSearchResult.IconType.Image", factory)
        self.assertIn("LauncherSearchResult.IconType.Material", factory)
        self.assertIn('fallbackIconName: siteSource === "open"', factory)
        self.assertIn('? "tab"', factory)
        self.assertIn('siteSource === "favorite" ? "bookmark" : "history"', factory)
        self.assertIn("Qt.openUrlExternally(url)", factory)

    def test_indexed_favicon_is_used_directly_before_lazy_lookup(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        factory = launcher.split("function createBrowserSiteResult", 1)[1].split(
            "function createAppResultObject", 1
        )[0]

        self.assertIn('const indexedFavicon = String(site?.favicon ?? "")', factory)
        self.assertIn('indexedFavicon.startsWith("file://")', factory)
        self.assertIn("BrowserSites.faviconFor(site)", factory)

    def test_favorites_and_suggestions_are_distinct_internal_sections(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        model = source("modules/common/models/LauncherSearchResult.qml")
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")

        self.assertIn('property string siteSource: ""', model)
        self.assertIn('siteSource: properties.siteSource || ""', launcher)
        self.assertIn('siteSource: siteSource', launcher)
        self.assertIn('site?.source ?? (site?.bookmarked === true ? "favorite" : "suggested")', launcher)
        self.assertIn('id: "siteFavorites"', registry)
        self.assertIn('title: qsTr("Favorite sites")', registry)
        self.assertIn('id: "siteSuggestions"', registry)
        self.assertIn('title: qsTr("Suggested sites")', registry)
        self.assertIn('if (sectionId === "sites")', registry)
        self.assertIn('id: "siteTabs"', registry)
        self.assertIn('title: qsTr("Open tabs")', registry)
        self.assertIn('expanded.push("siteTabs", "siteFavorites", "siteSuggestions")', registry)
        self.assertIn('if (item?.siteSource === "open")', widget)
        self.assertIn('return "siteTabs"', widget)

    def test_site_actions_are_ordered_and_private_action_is_conditional(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        factory = launcher.split("function createBrowserSiteResult", 1)[1].split(
            "function createAppResultObject", 1
        )[0]

        copy_url = factory.index('name: Translation.tr("Copy URL")')
        copy_title = factory.index('name: Translation.tr("Copy title")')
        private = factory.index('name: Translation.tr("Open in private window")')
        self.assertLess(copy_url, copy_title)
        self.assertLess(copy_title, private)
        self.assertIn("if (BrowserSites.privateBrowsingSupported)", factory)
        self.assertIn("BrowserSites.openPrivateWindow(url)", factory)
        self.assertGreaterEqual(factory.count("Quickshell.clipboardText ="), 2)

    def test_sites_match_only_unprefixed_queries_and_follow_applications(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        compute = launcher.split("function _computeResults()", 1)[1].split(
            "function createResult", 1
        )[0]

        self.assertIn("const browserSiteSearchActive = !root.queryUsesPrefix(root.query)", compute)
        self.assertIn("BrowserSites.matchSites(root.query)", compute)
        self.assertIn("root.createBrowserSiteResult(site)", compute)
        apps = compute.index("result = result.concat(appResultObjects)")
        sites = compute.index("result = result.concat(browserSiteResultObjects)")
        settings = compute.index("result = result.concat(settingsResultObjects)")
        self.assertLess(apps, sites)
        self.assertLess(sites, settings)

    def test_registry_and_widget_route_sites_as_content_after_apps(self) -> None:
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")

        apps = registry.index('id: "apps"')
        sites = registry.index('id: "sites"')
        settings = registry.index('id: "settings"')
        self.assertLess(apps, sites)
        self.assertLess(sites, settings)
        self.assertIn('title: qsTr("Sites")', registry)
        self.assertIn('icon: "public"', registry)
        self.assertNotIn('order.indexOf("sites") === -1', registry)
        self.assertIn('if (key.startsWith("site:"))', widget)
        self.assertIn('sections: ["content", "files", "siteTabs", "siteFavorites", "siteSuggestions"]', widget)

    def test_config_schema_and_migration_add_sites_once_without_forcing_it_back(self) -> None:
        config = source("modules/common/Config.qml")
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        defaults = config.split("property JsonObject browserSites", 1)[1].split(
            "property list<var> aliases", 1
        )[0]
        migration = config.split("// v10 -> v11:", 1)[1].split(
            "raw.configVersion = root.currentConfigVersion", 1
        )[0]

        self.assertIn("readonly property int currentConfigVersion: 11", config)
        expected_defaults = {
            "enable": "property bool enable: true",
            "profilePath": 'property string profilePath: ""',
            "maxIndexedSites": "property int maxIndexedSites: 300",
            "maxResults": "property int maxResults: 6",
            "includeHistory": "property bool includeHistory: true",
            "useLocalFavicons": "property bool useLocalFavicons: true",
            "allowRemoteFavicons": "property bool allowRemoteFavicons: false",
            "refreshMinutes": "property int refreshMinutes: 10",
        }
        for field, declaration in expected_defaults.items():
            with self.subTest(field=field):
                self.assertIn(declaration, defaults)

        apps = config.index('{ "id": "apps" }', config.index("property list<var> sectionOrder"))
        sites = config.index('{ "id": "sites" }', apps)
        controls = config.index('{ "id": "controls" }', sites)
        self.assertLess(apps, sites)
        self.assertLess(sites, controls)

        self.assertIn("if (from < 11)", migration)
        self.assertIn("raw.search.browserSites === undefined", migration)
        self.assertIn("raw.search.browserSites = {", migration)
        for assignment in (
            "enable: true",
            'profilePath: ""',
            "maxIndexedSites: 300",
            "maxResults: 6",
            "includeHistory: true",
            "useLocalFavicons: true",
            "allowRemoteFavicons: false",
            "refreshMinutes: 10",
        ):
            with self.subTest(migration_default=assignment):
                self.assertIn(assignment, migration)
        self.assertIn('String(entry?.id ?? entry) === "sites"', migration)
        self.assertIn(
            "if (Array.isArray(sectionOrder) && sectionOrder.length > 0)",
            migration,
        )
        self.assertIn("if (!hasSites)", migration)
        self.assertIn(
            'const appsIndex = sectionOrder.findIndex(entry => String(entry?.id ?? entry) === "apps")',
            migration,
        )
        self.assertIn(
            'const settingsIndex = sectionOrder.findIndex(entry => String(entry?.id ?? entry) === "settings")',
            migration,
        )
        self.assertIn("const insertAt = appsIndex >= 0 ? appsIndex + 1", migration)
        self.assertIn(": (settingsIndex >= 0 ? settingsIndex : sectionOrder.length)", migration)
        insertion = 'sectionOrder.splice(insertAt, 0, { "id": "sites" })'
        self.assertEqual(migration.count(insertion), 1)
        self.assertNotIn('order.indexOf("sites") === -1', registry)

    def test_settings_exposes_complete_progressive_browser_sites_provider(self) -> None:
        settings = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        provider = settings.split('text: Translation.tr("Browser sites")', 1)[1].split(
            'text: Translation.tr("Calculator")', 1
        )[0]

        self.assertIn("checked: Config.options.search.browserSites.enable", provider)
        self.assertIn("onCheckedChanged: Config.options.search.browserSites.enable = checked", provider)
        self.assertIn("without typing a prefix", provider)
        self.assertIn("visible: Config.options.search.browserSites.enable", provider)
        self.assertIn("BrowserSites.loading", provider)
        self.assertIn("BrowserSites.ready", provider)
        self.assertIn("BrowserSites.error", provider)
        self.assertIn("BrowserSites.sites.length", provider)
        self.assertIn("BrowserSites.profilePath", provider)
        self.assertIn('placeholderText: Translation.tr("Auto-detect browser profile")', provider)
        self.assertIn("textField.onEditingFinished", provider)
        self.assertIn("Config.options.search.browserSites.profilePath", provider)
        for field in (
            "includeHistory",
            "useLocalFavicons",
            "allowRemoteFavicons",
            "maxIndexedSites",
            "maxResults",
            "refreshMinutes",
        ):
            with self.subTest(field=field):
                self.assertIn("Config.options.search.browserSites." + field, provider)
        self.assertIn("network", provider.lower())
        self.assertGreaterEqual(provider.count("StyledToolTip"), 3)
        for label in (
            'text: Translation.tr("History sites indexed")',
            'text: Translation.tr("Site results shown")',
            'text: Translation.tr("Refresh interval (minutes)")',
        ):
            with self.subTest(spinbox=label):
                self.assertIn(label, provider)
        self.assertIn("from: 0\n                        to: 5000", provider)
        self.assertIn("from: 1\n                        to: 20", provider)
        self.assertIn("from: 1\n                        to: 1440", provider)

    def test_search_provider_rows_are_not_nested_inside_content_subsections(self) -> None:
        settings = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        browser_index = qml_object_containing(
            settings, 'title: Translation.tr("Browser sites index")'
        )
        file_directory = qml_object_containing(
            settings, 'title: Translation.tr("Indexed directory")'
        )

        # ContentSubsection owns compound/status content. Interactive setting rows
        # stay in the provider layout so their own M3 surfaces and radii remain visible.
        for subsection in (browser_index, file_directory):
            with self.subTest(subsection=subsection.splitlines()[0].strip()):
                self.assertNotIn("ConfigSwitch {", subsection)
                self.assertNotIn("ConfigSpinBox {", subsection)

        provider = settings.split('text: Translation.tr("Browser sites")', 1)[1].split(
            'text: Translation.tr("Calculator")', 1
        )[0]
        for row_label in (
            'text: Translation.tr("Include browsing history")',
            'text: Translation.tr("Use local favicons")',
            'text: Translation.tr("Allow remote favicons")',
            'text: Translation.tr("Show files and folders without a prefix")',
            'text: Translation.tr("Hide image thumbnails")',
            'text: Translation.tr("Include hidden files and folders")',
        ):
            with self.subTest(row=row_label):
                self.assertIn(row_label, provider)

    def test_quicklink_app_handler_receives_the_expanded_url(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        opener = launcher.split("function openQuicklink", 1)[1].split(
            "function quicklinkFavicon", 1
        )[0]

        self.assertIn(
            'Quickshell.execDetached(["gtk-launch", openWith.slice(4), url])',
            opener,
        )

    def test_create_result_keeps_image_fallback_and_file_path(self) -> None:
        launcher = source("services/LauncherSearch.qml")
        create_result = launcher.split("function createResult(properties)", 1)[1].split(
            "function settingsIntegrationSearch", 1
        )[0]

        self.assertIn('filePath: properties.filePath || ""', create_result)
        self.assertIn('fallbackIconName: properties.fallbackIconName || ""', create_result)


if __name__ == "__main__":
    unittest.main()
