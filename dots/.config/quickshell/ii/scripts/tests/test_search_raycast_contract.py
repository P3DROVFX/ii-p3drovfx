#!/usr/bin/env python3
"""Regression contracts for the Raycast-style Overview Search architecture."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SearchRaycastContractTests(unittest.TestCase):
    def test_registry_is_the_single_catalog_for_hosted_panels(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        for panel_id in ("calendar", "tasks", "timers", "emojis", "screenshots", "windows", "settings", "keybinds", "commands", "gmail", "sports", "tools"):
            self.assertIn('id: "' + panel_id + '"', registry)
        self.assertGreaterEqual(registry.count("hosted: true"), 12)

    def test_every_new_panel_has_a_distinct_search_bar_identity(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        search_bar = source("modules/ii/overview/SearchBar.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        expected = {
            "calendar": ("calendar_month", "Arch"),
            "tasks": ("task_alt", "Cookie4Sided"),
            "timers": ("timer", "PuffyDiamond"),
            "emojis": ("add_reaction", "Sunny"),
            "screenshots": ("screenshot", "PixelCircle"),
            "windows": ("splitscreen", "Square"),
            "settings": ("tune", "Clover8Leaf"),
            "keybinds": ("keyboard", "PixelTriangle"),
            "commands": ("terminal", "Ghostish"),
            "gmail": ("mail", "Heart"),
            "sports": ("sports_soccer", "VerySunny"),
            "tools": ("wand_stars", "Burst"),
        }

        registry_lines = registry.splitlines()
        for panel_id, (icon, shape) in expected.items():
            panel_line = next(line for line in registry_lines if 'id: "' + panel_id + '"' in line)
            self.assertIn('searchIcon: "' + icon + '"', panel_line, panel_id)
            self.assertIn('searchShape: "' + shape + '"', panel_line, panel_id)
            self.assertIn("searchRotationStep:", panel_line, panel_id)

        self.assertEqual(len({identity[0] for identity in expected.values()}), len(expected))
        self.assertEqual(len({identity[1] for identity in expected.values()}), len(expected))
        self.assertIn("property var activePanel: null", search_bar)
        self.assertIn("root.activePanel?.searchShape", search_bar)
        self.assertIn("root.activePanel?.searchIcon", search_bar)
        self.assertIn("activePanel: root.activePanel", widget)

    def test_hosted_panel_uses_the_single_results_surface(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        self.assertIn("SearchPanelHost", widget)
        self.assertIn("activePanelUsesHost", widget)
        self.assertIn("Appearance.sizes.elevationMargin", widget)

    def test_hosted_panels_share_insets_without_repeated_chrome(self):
        scaffold = source("modules/ii/overview/SearchPanelScaffold.qml")
        self.assertIn("property bool showHeader: false", scaffold)
        self.assertIn("property bool showStatus: false", scaffold)
        self.assertIn("anchors.margins: root.contentMargin", scaffold)

        for panel in (
            "CalendarPanel.qml", "TasksPanel.qml", "TimersPanel.qml",
            "EmojiPanel.qml", "ScreenshotsPanel.qml",
            "WindowManagementPanel.qml", "SettingsTogglesPanel.qml",
            "KeybindsPanel.qml", "CommandsPanel.qml", "GmailPanel.qml",
            "SportsPanel.qml",
            "ToolsPanel.qml",
        ):
            self.assertIn(
                "SearchPanelScaffold",
                source("modules/ii/overview/" + panel),
            )

    def test_hosted_panel_geometry_and_overview_visibility_are_shared(self):
        config = source("modules/common/Config.qml")
        registry = source("modules/common/SearchPanelRegistry.qml")
        scaffold = source("modules/ii/overview/SearchPanelScaffold.qml")
        overview = source("modules/ii/overview/Overview.qml")
        self.assertIn("property int panelWidth: 860", config)
        self.assertIn("property int panelBodyHeight: 420", config)
        self.assertGreaterEqual(registry.count("Config.options.search.appearance.panelWidth"), 12)
        self.assertIn("minimumContentHeight", scaffold)
        self.assertIn("searchWidget?.isAnySpecialMode", overview)

    def test_hosted_panel_back_navigation_precedes_overview_close(self):
        search_bar = source("modules/ii/overview/SearchBar.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        self.assertIn("activePanelQueryEmpty", search_bar)
        self.assertIn("function exitActivePanel(): bool", widget)
        self.assertIn("return root.exitActivePanel()", widget)
        self.assertIn("activePanelMode: root.isAnySpecialMode", widget)

    def test_window_and_screenshot_panels_keep_real_context(self):
        states = source("GlobalStates.qml")
        screenshots = source("modules/ii/overview/ScreenshotsPanel.qml")
        self.assertIn("ToplevelManager.activeToplevel?.HyprlandToplevel?.address", states)
        self.assertNotIn("HyprlandData.activeWindow?.address", states)
        self.assertIn("function imageTitle(entry)", screenshots)
        self.assertIn("function imageMetadata(entry)", screenshots)
        self.assertIn("GlobalStates.overviewOpen = false", screenshots)

    def test_emoji_index_and_launcher_pages_avoid_known_runtime_regressions(self):
        emojis = source("services/Emojis.qml")
        self.assertIn("if (root.loaded || root.loading)", emojis)
        self.assertIn("entriesPrepared", emojis)
        self.assertIn("preparationTimer", emojis)
        self.assertIn("function ensurePrepared(): void", emojis)
        self.assertIn("structureTimer", emojis)
        self.assertNotIn("root.entries = root.list.map", emojis)
        self.assertIn("function queryEntries(", emojis)
        self.assertIn("property var entriesByCategory", emojis)
        self.assertNotIn("property list<var> entries", emojis)
        list_change = emojis.split("onListChanged:", 1)[1].split("function ensurePrepared", 1)[0]
        self.assertNotIn("preparationTimer.restart()", list_change)

        emoji_panel = source("modules/ii/overview/EmojiPanel.qml")
        self.assertIn("import qs.modules.common.functions", emoji_panel)
        self.assertIn("StyledComboBox", emoji_panel)
        self.assertIn("GridView", emoji_panel)
        self.assertIn("showStatus: true", emoji_panel)
        self.assertIn("Math.min(8", emoji_panel)
        self.assertIn("skinTone", emoji_panel)
        self.assertIn("toggled: root.selectedIndex === index", emoji_panel)
        self.assertIn("Appearance.rounding.verylarge", emoji_panel)
        self.assertIn("Layout.preferredWidth: root.headerPillWidth", emoji_panel)
        self.assertIn("property int loadedEntryLimit", emoji_panel)
        self.assertIn("property bool paginationReady: false", emoji_panel)
        self.assertIn("readonly property int pageSize: Math.max(1", emoji_panel)
        self.assertIn("if (root.paginationReady)", emoji_panel)
        self.assertIn("root.paginationReady = true;", emoji_panel)
        self.assertNotIn("property int loadedEntryLimit: pageSize", emoji_panel)
        self.assertIn("function loadMoreEntries(): void", emoji_panel)
        self.assertIn("onAtYEndChanged:", emoji_panel)
        self.assertIn("reuseItems: true", emoji_panel)
        self.assertIn("cacheBuffer: cellHeight", emoji_panel)
        self.assertIn("id: emojiPageModel", emoji_panel)
        self.assertIn("emojiPageModel.append", emoji_panel)
        self.assertIn("model: emojiPageModel", emoji_panel)
        self.assertIn("font.pixelSize: root.emojiGlyphSize", emoji_panel)

        launcher_files = (
            "modules/settings/configs/LauncherConfig.qml",
            "modules/settings/configs/widgets/LauncherModulesConfig.qml",
            "modules/settings/configs/widgets/LauncherQuicklinksConfig.qml",
            "modules/settings/configs/widgets/LauncherSnippetsConfig.qml",
            "modules/settings/configs/widgets/LauncherShortcutsConfig.qml",
            "modules/settings/configs/widgets/LauncherAppearanceConfig.qml",
        )
        for path in launcher_files:
            content = source(path)
            self.assertIn("import qs.services", content)
            self.assertNotIn("Appearance.sizes.normalIcon", content)

    def test_launcher_producers_are_local_and_guarded(self):
        launcher = source("services/LauncherSearch.qml")
        for function in ("favoriteResults", "snippetMatches", "processMatches", "toolEntries", "modeMatches", "bluetoothMatches", "fallbackResults"):
            self.assertIn("function " + function, launcher)
        self.assertIn("processConfirmKey", launcher)
        self.assertIn("_scheduleResultsUpdate", launcher)
        self.assertNotIn("XmlHttpRequest", launcher)
        self.assertIn("DevToolsRegistry.inlineMatches", launcher)
        self.assertIn("Config.options.search.modules.systemControls", launcher)
        shell_actions = source("modules/common/ShellActionRegistry.qml")
        for term in ('id: "notes"', 'notesOpen = true', 'notes", "notas'):
            self.assertIn(term, shell_actions)

    def test_daily_sports_and_timer_panels_have_stable_empty_surfaces(self):
        sports_service = source("services/SportsService.qml")
        sports_panel = source("modules/ii/overview/SportsPanel.qml")
        timers = source("modules/ii/overview/TimersPanel.qml")
        self.assertIn("function fetchSearchGamesForToday()", sports_service)
        self.assertIn("function searchLeagueEntries()", sports_service)
        self.assertIn("scoreboard?dates=${date}", sports_service)
        self.assertIn("property var searchGames", sports_service)
        self.assertIn("property bool enabled: barEnabled || dockEnabled || lockEnabled", sports_service)
        self.assertIn('Translation.tr("No games today")', sports_panel)
        self.assertIn("modelData.home?.logo", sports_panel)
        self.assertIn("modelData.away?.logo", sports_panel)
        self.assertIn("height: parent.height", sports_panel)
        self.assertIn("function navigateUp(): bool", timers)
        self.assertIn("function navigateDown(): bool", timers)
        self.assertIn("function secondaryActivateSelected(): bool", timers)
        self.assertIn("property int displayClockTick", timers)
        self.assertIn('(?:h|hr|hour|hours)', timers)
        self.assertIn("TimerService.addCountdown", timers)
        self.assertIn(
            "readonly property real timerCardHeight: Appearance.sizes.elevationMargin * 9",
            timers,
        )
        self.assertIn("cellHeight: root.timerCardHeight", timers)

        timer_service = source("services/TimerService.qml")
        self.assertIn("return countdown", timer_service)

    def test_screenshot_preview_uses_the_working_clipboard_wrapper(self):
        screenshots = source("modules/ii/overview/ScreenshotsPanel.qml")
        self.assertIn("CliphistImage", screenshots)
        self.assertIn("height: parent.height", screenshots)
        self.assertIn("bottomMargin: 0", screenshots)
        self.assertIn("Preparing preview", screenshots)

        wrapper = source("modules/common/widgets/CliphistImage.qml")
        self.assertIn("Qt.md5(root.entry)", wrapper)
        self.assertIn("readonly property real fitScale", wrapper)
        self.assertNotIn("Component.onDestruction", wrapper)

    def test_normal_results_are_deduplicated_and_grouped(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        launcher = source("services/LauncherSearch.qml")
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        self.assertIn("function organizeResults(results, limit)", widget)
        # Group names moved to the registry so Settings can list them too.
        self.assertIn('title: qsTr("Best match")', registry)
        self.assertIn('title: qsTr("Settings")', registry)
        self.assertIn("let hasApplications = false", widget)
        self.assertIn('key !== "panel:settings"', widget)
        # Section captions are model rows, not ListView.section delegates: Qt
        # positions section delegates outside the view transitions, which let
        # them snap over rows that were still animating.
        self.assertNotIn("section.property", widget)
        self.assertNotIn("section.delegate", widget)
        self.assertIn('key: "section:" + sectionId', widget)
        self.assertIn("isHeader: true", widget)
        self.assertIn("function moveSelection(step: int): bool", widget)
        # Rows must carry the original result, not a per-keystroke copy of it.
        self.assertNotIn("Object.assign({}, group.items", widget)
        self.assertIn("const seenKeys = new Set()", widget)
        self.assertIn("dynamicRoles: true", widget)
        self.assertIn("result.length === 0", launcher)

    def test_normal_search_has_category_filter_and_intentional_empty_state(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        search_bar = source("modules/ii/overview/SearchBar.qml")
        item = source("modules/ii/overview/SearchItem.qml")

        # Tab belongs to a visible category chip in plain Search. Hosted panels
        # keep their own Tab routing, and a specific category no longer needs
        # section captions repeating the chip's label.
        self.assertIn("property string resultCategoryId: \"all\"", widget)
        self.assertIn("function cycleResultCategory(step: int)", widget)
        category_block = widget.split("readonly property var resultCategoryDefinitions", 1)[1].split("readonly property var availableResultCategories", 1)[0]
        self.assertLess(category_block.index('id: "all"'), category_block.index('id: "apps"'))
        self.assertLess(category_block.index('id: "apps"'), category_block.index('id: "controls"'))
        self.assertLess(category_block.index('id: "controls"'), category_block.index('id: "tools"'))
        self.assertIn("showCategoryFilter: root.showNormalCategoryFilter", widget)
        self.assertIn("onCycleCategoryFilter: step => root.cycleResultCategory(step)", widget)
        self.assertIn("signal cycleCategoryFilter(int step)", search_bar)
        self.assertIn('root.resultCategoryId === "all" && groupCount > 1', widget)

        # No-match continuations are actions, not faux search results.
        self.assertIn("readonly property bool showEmptySearchState", widget)
        self.assertIn("id: emptySearchState", widget)
        self.assertIn("readonly property var emptyFallbackActions", widget)
        self.assertIn("function executeEmptyFallback(actionId: string)", widget)
        self.assertIn("Nothing found for %1", widget)
        self.assertIn("RippleButton", widget)
        self.assertIn("property bool isFallback: false", source("modules/common/models/LauncherSearchResult.qml"))
        self.assertIn('root.createSearchPanelResult(SearchPanelRegistry.byId("tasks"), true)', source("services/LauncherSearch.qml"))
        for fallback_id in ('id: "command"', 'id: "ai"', 'id: "web"'):
            self.assertIn(fallback_id, widget)

        # When real matches exist, the original command/AI/web continuations
        # remain available as the final section. With no real match the empty
        # state owns those same intentions as chips instead of duplicate rows.
        launcher = source("services/LauncherSearch.qml")
        self.assertIn("readonly property bool showContinuationRows", widget)
        self.assertIn("root.showContinuationRows", widget)
        self.assertIn("const showNormalContinuations", launcher)
        continuation_block = launcher.split("const showNormalContinuations", 1)[1].split("// Filter out duplicate", 1)[0]
        self.assertNotIn("result.length === 0", continuation_block)
        for result_name in ("commandResultObject", "aiAskResultObject", "webSearchResultObject"):
            self.assertIn("result.push(" + result_name + ")", continuation_block)

        # Captions recede, long distinguishing suffixes survive, and fuzzy
        # highlighting creates at most one rich-text emphasis run.
        self.assertIn("color: Appearance.colors.colOutline", widget)
        self.assertIn("readonly property real topGap", widget)
        self.assertIn("Appearance.sizes.elevationMargin * 0.4", widget)
        self.assertIn("spacing: 2", widget)
        self.assertIn("Text.ElideMiddle", item)
        highlight = item.split("function highlightContent(content, query)", 1)[1].split("property string displayContent", 1)[0]
        self.assertEqual(highlight.count("root.highlightPrefix"), 1)

    def test_always_list_apps_refreshes_the_idle_surface(self):
        config = source("modules/common/Config.qml")
        launcher = source("services/LauncherSearch.qml")
        dynamic_island = source("modules/ii/dynamicIsland/DynamicIslandPanel.qml")
        search_drop = source("modules/ii/topLayer/search/SearchDrop.qml")
        background = source("modules/ii/background/BackgroundWidgetsWindow.qml")

        # Opt-in by default, and once enabled it replaces every Overview grid
        # host with the application list instead of stacking both surfaces.
        self.assertIn("property bool alwaysListApps: false", config)
        for host in (dynamic_island, search_drop, background):
            self.assertIn("!Config.options.search.alwaysListApps", host)

        # The empty-query result set must be refreshed by every source that can
        # make it stale. Query edits alone are insufficient during first boot.
        self.assertIn("readonly property bool alwaysListAppsEnabled", launcher)
        self.assertIn("onAlwaysListAppsEnabledChanged:", launcher)
        self.assertIn("onOverviewEnabledChanged: root.enforceAlwaysListAppsOverviewPolicy()", launcher)
        app_list_handler = launcher.split("target: AppSearch", 1)[1].split("function createAppResultObject", 1)[0]
        self.assertIn("root._scheduleResultsUpdate()", app_list_handler)
        overview_handler = launcher.split("function onOverviewOpenChanged()", 1)[1].split("Component.onCompleted", 1)[0]
        self.assertIn("if (GlobalStates.overviewOpen)", overview_handler)
        self.assertIn("root._scheduleResultsUpdate()", overview_handler)

        widget = source("modules/ii/overview/SearchWidget.qml")
        suggestions_binding = widget.split("readonly property bool showSuggestionsPanel:", 1)[1].splitlines()[0]
        self.assertIn("!Config.options.search.alwaysListApps", suggestions_binding)

        # This is a configuration policy, not only a visibility trick: every
        # way of enabling the app list disables the persisted Overview option.
        self.assertIn("function enforceAlwaysListAppsOverviewPolicy()", launcher)
        policy_block = launcher.split("function enforceAlwaysListAppsOverviewPolicy()", 1)[1].split("Connections {", 1)[0]
        self.assertIn("Config.options.overview.enable = false", policy_block)

        overview_config = source("modules/settings/configs/OverviewConfig.qml")
        self.assertIn("readonly property bool overviewLockedByAppList", overview_config)
        self.assertIn("visible: page.overviewLockedByAppList", overview_config)
        self.assertIn("enabled: !page.overviewLockedByAppList", overview_config)
        self.assertIn("if (!page.overviewLockedByAppList)", overview_config)

        for settings_path in ("modules/settings/configs/LauncherConfig.qml", "modules/settings/configs/AppSearchConfig.qml"):
            settings_page = source(settings_path)
            self.assertIn("Config.options.overview.enable = false", settings_page)
            self.assertIn("visible: Config.options.search.alwaysListApps", settings_page)
            self.assertIn("Search now opens directly with applications", settings_page)

    def test_result_rows_cannot_outlive_their_model_row(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        # A `remove` transition keeps a delegate alive after its model row is
        # gone. Interrupt it — a burst of keystrokes, or the asynchronous file
        # results landing after the query settled — and the delegate is stranded
        # in the scene: no space reserved, still clickable.
        self.assertNotIn("remove: Transition", widget)
        # The view re-emits contentY and currentIndex while the model is being
        # mutated, and both handlers can ask for another page.
        self.assertIn("property bool applyingDiff: false", widget)
        self.assertIn("if (appResults.applyingDiff)", widget)
        self.assertIn("pageLoadTimer.restart()", widget)
        # Length invariant: nothing may survive past the end of the new rows.
        self.assertIn("while (resultModel.count > rows.length)", widget)

    def test_file_search_can_run_without_a_prefix_and_keeps_complete_matches(self):
        launcher = source("services/LauncherSearch.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        config = source("modules/common/Config.qml")

        # The toggle, preview limit, and threaded worker control the cost.
        self.assertIn("property bool inlineResults: false", config)
        self.assertIn("property int minimumQueryLength: 3", config)
        self.assertIn("property int threads: 4", config)

        # The walk must never sit on the keystroke path, and must never start
        # for a query that already belongs to a prefix or to the calculator.
        self.assertIn("fileSearchDebounce.restart()", launcher)
        self.assertIn("function fileSearchExpression(query: string): string", launcher)
        self.assertIn("root.queryUsesPrefix(query) || root.isMathQuery(query)", launcher)

        # A result cap before ranking silently drops relevant files. The normal
        # Search surface gets a preview slice only after the complete ranking.
        self.assertNotIn('"--max-results"', launcher)
        self.assertIn("root.allFileResults = root.rankFilePaths(lines, root._fileQuery, 0)", launcher)
        self.assertIn("root.fileResults = root.allFileResults.slice(0, limit)", launcher)
        self.assertIn('command.push("--threads", String(threads))', launcher)

        # A query is user text, not a regex: an unescaped bracket would make fd
        # exit with an error instead of results.
        self.assertIn("function searchPattern(expression)", launcher)
        self.assertIn('.join(".*")', launcher)

        # Files are their own result class, not "links & text". The group's name
        # and its default position now live in the registry, not in the widget.
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        self.assertIn('return "files"', widget)
        self.assertIn('id: "files"', registry)
        self.assertIn('title: qsTr("Files & folders")', registry)

    def test_file_results_can_be_browsed_in_full_and_folders_pinned_from_search(self):
        actions = source("modules/common/SearchResultActions.qml")
        launcher = source("services/LauncherSearch.qml")
        states = source("GlobalStates.qml")
        taskbar = source("services/TaskbarApps.qml")
        browser = source("modules/ii/overview/FileBrowserPanel.qml")

        # Search rows need the real absolute path, not their shortened display
        # name, when toggling a dock folder.
        self.assertIn("const folderPath = String(entry.filePath ?? itemName)", actions)
        self.assertIn("TaskbarApps.togglePinnedFile(folderPath)", actions)
        self.assertIn("function togglePinnedFile(path)", taskbar)

        # The short result list is only a preview. The complete ranked snapshot
        # is passed to the hosted File Browser by an ephemeral global intent.
        self.assertIn("property var allFileResults: []", launcher)
        self.assertIn("root.fileResults = root.allFileResults.slice", launcher)
        self.assertIn("GlobalStates.openFileBrowserResults", actions)
        self.assertIn("function openFileBrowserResults(paths, query, monitorName)", states)
        self.assertIn("property var fileBrowserSearchResults: []", states)
        self.assertIn("function consumeGlobalSearchResults", browser)
        self.assertIn("readonly property var displayedEntries", browser)
        self.assertIn('id: "pin-folder"', browser)
        self.assertIn("function togglePinnedFolder", browser)

    def test_result_group_priority_is_user_orderable(self):
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        config = source("modules/common/Config.qml")
        listview = source("modules/common/widgets/ConfigListView.qml")
        entry = source("modules/common/widgets/ConfigListViewEntry.qml")
        launcher_page = source("modules/settings/configs/LauncherConfig.qml")

        # One catalogue behind both the rendered groups and the Settings list,
        # instead of the two parallel switch statements this replaced.
        self.assertIn("function getAvailableComponents(usedIds: var): var", registry)
        self.assertIn("readonly property var activeOrder", registry)
        self.assertIn("readonly property var sectionOrder: SearchResultSectionRegistry.activeOrder", widget)
        self.assertIn("SearchResultSectionRegistry.getComponent(sectionId)", widget)

        # Files & folders ships last among the match groups.
        self.assertIn('{ "id": "files" },\n                    { "id": "continue" }', config)
        self.assertIn("property list<var> sectionOrder", config)

        # An emptied list must not mean "no results at all".
        self.assertIn("order.length > 0 ? order : root.defaultOrder", registry)
        # Promoting into a group the user removed would delete the row, not
        # highlight it.
        self.assertIn('root.sectionOrder.indexOf("best") !== -1', widget)

        # The bar's reorderable list, reused rather than duplicated.
        self.assertIn("property var infoProvider: null", listview)
        self.assertIn("property var normalizeEntry: null", listview)
        self.assertIn("function componentInfo(id)", listview)
        self.assertIn("root.componentInfo(modelData.id)", entry)
        self.assertIn("infoProvider: id => SearchResultSectionRegistry.getComponent(id)", launcher_page)

    def test_aliases_are_a_first_class_top_priority_result_group(self):
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        launcher = source("services/LauncherSearch.qml")
        model = source("modules/common/models/LauncherSearchResult.qml")
        config = source("modules/common/Config.qml")

        # Aliases are an explicit intent, independent of what they target. They
        # must not disappear with Applications, Content or More results.
        self.assertIn('id: "aliases"', registry)
        self.assertIn('title: qsTr("Aliases")', registry)
        self.assertLess(registry.index('id: "aliases"'), registry.index('id: "media"'))
        classifier = widget.split("function resultSectionId(item): string", 1)[1].split(
            "function sectionPresentation", 1
        )[0]
        self.assertIn('return "aliases"', classifier)
        self.assertLess(classifier.index("item?.isAlias"), classifier.index('key.startsWith("app:")'))
        self.assertIn("property bool isAlias: false", model)

        alias_block = launcher.split("// App/Folder/Command Aliases", 1)[1].split(
            "//////// Prioritized by type /////////", 1
        )[0]
        self.assertEqual(alias_block.count("isAlias: true"), 4)
        self.assertIn("readonly property var configuredAliases", launcher)
        self.assertIn("onConfiguredAliasesChanged: root._scheduleResultsUpdate()", launcher)
        self.assertIn("root.normalizedAlias(root.query)", launcher)
        self.assertNotIn('unique[i].type === Translation.tr("App Alias")', widget)

        # Existing v11 orders are authoritative and omit the new id, so merely
        # adding it to the catalogue would still leave every current user without
        # aliases. The schema migration prepends it once and the shipped order
        # starts with the same group.
        self.assertIn("readonly property int currentConfigVersion: 13", config)
        self.assertIn("if (from < 12)", config)
        self.assertIn('sectionOrder.unshift({ "id": "aliases" })', config)
        default_order = config.split("property list<var> sectionOrder: [", 1)[1].split(
            "]", 1
        )[0]
        self.assertTrue(default_order.lstrip().startswith('{ "id": "aliases" }'))

    def test_quicklinks_and_text_snippets_have_independent_result_priority(self):
        registry = source("modules/common/SearchResultSectionRegistry.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        config = source("modules/common/Config.qml")

        self.assertIn('id: "quicklinks"', registry)
        self.assertIn('title: qsTr("Quick links")', registry)
        self.assertIn('id: "textSnippets"', registry)
        self.assertIn('title: qsTr("Text snippets")', registry)
        self.assertNotIn('id: "content"', registry)

        classifier = widget.split("function resultSectionId(item): string", 1)[1].split(
            "function sectionPresentation", 1
        )[0]
        self.assertIn('return "quicklinks"', classifier)
        self.assertIn('return "textSnippets"', classifier)
        self.assertIn('return "files"', classifier)
        self.assertLess(classifier.index('return "files"'), classifier.index('return "quicklinks"'))
        self.assertIn('key.startsWith("tool:") || key.startsWith("win:")', classifier)

        category_block = widget.split("readonly property var resultCategoryDefinitions", 1)[1].split(
            "readonly property var availableResultCategories", 1
        )[0]
        self.assertIn('sections: ["quicklinks", "textSnippets", "files",', category_block)
        self.assertNotIn('sections: ["content",', category_block)
        self.assertNotIn('key.startsWith("quicklink:")', widget.split("// Applications are always", 1)[1].split("const buckets", 1)[0])

        # v12 stored the two producers as one `content` position. Replacing that
        # entry in place preserves the user's surrounding order and whether the
        # old group had been disabled.
        self.assertIn("readonly property int currentConfigVersion: 13", config)
        self.assertIn("if (from < 13)", config)
        self.assertIn('sectionOrder.splice(contentIndex, 1, { "id": "quicklinks" }, { "id": "textSnippets" })', config)
        default_order = config.split("property list<var> sectionOrder: [", 1)[1].split(
            "]", 1
        )[0]
        self.assertIn('{ "id": "quicklinks" }', default_order)
        self.assertIn('{ "id": "textSnippets" }', default_order)
        self.assertIn('{ "id": "media" }', default_order)
        self.assertNotIn('{ "id": "content" }', default_order)

    def test_suggestions_execute_current_app_and_alias_schemas(self):
        suggestions = source("modules/ii/overview/SuggestionsPanel.qml")
        launcher = source("services/LauncherSearch.qml")

        self.assertNotIn(".launch()", suggestions)
        self.assertNotIn("alias.command", suggestions)
        self.assertIn("LauncherSearch.launchApplication", suggestions)
        self.assertIn("LauncherSearch.aliasAvailable", suggestions)
        self.assertIn("LauncherSearch.executeAlias", suggestions)
        self.assertIn("mappedAliases.length > 0", suggestions)
        self.assertIn("function launchApplication(app): bool", launcher)
        self.assertIn("function aliasAvailable(entry): bool", launcher)
        self.assertIn("function executeAlias(entry): bool", launcher)

    def test_every_file_row_has_an_icon_and_no_row_sized_preview(self):
        launcher = source("services/LauncherSearch.qml")
        item = source("modules/ii/overview/SearchItem.qml")
        model = source("modules/common/models/LauncherSearchResult.qml")

        # A row's height is fixed, so a preview sized in its own right drew past
        # the row and over its neighbours.
        self.assertNotIn("FileSearchImage", item)
        self.assertNotIn("imagePath: root.filePath", item)

        # An image is its own icon; everything else gets a symbol, and there is
        # always a fallback so no slot can end up empty.
        self.assertIn("readonly property var fileIconsByExtension", launcher)
        self.assertIn("function fileResultPreview(path: string, isDirectory: bool): string", launcher)
        self.assertIn('?? "draft"', launcher)
        self.assertIn("property string fallbackIconName", model)
        self.assertIn("fallbackIconName: root.fileResultIcon(displayName, isDirectory)", launcher)
        self.assertIn("root.fallbackIconName.length > 0 ? root.fallbackIconName", item)

        # Decoding a wallpaper at full resolution to paint 32 pixels is the
        # difference between a thumbnail and a memory leak.
        self.assertIn("sourceSize.width: 64", item)
        self.assertIn("ClippingRectangle", item)

    def test_typo_tolerant_matching_is_a_gated_last_tier(self):
        myers = source("modules/common/functions/myers.js")
        bitwise = source("modules/common/functions/BitwiseFuzzy.qml")
        keymap = source("modules/common/functions/KeymapTranslation.qml")
        appsearch = source("services/AppSearch.qml")
        launcher = source("services/LauncherSearch.qml")
        config = source("modules/common/Config.qml")

        # Bit-parallel Myers, with the 30-bit word the signed-int JS engine needs.
        self.assertIn("const WORD_SIZE = 30", myers)
        self.assertIn("function _distSingle(peq, m, text, n)", myers)
        self.assertIn("function _distMulti(Peq, m, words, text, n)", myers)
        # Whole-string edit distance buries the one word a query aims at.
        self.assertIn("function scoreBestNormalized(prepared, normText)", myers)
        self.assertIn("function search(prepared, candidates, opts)", bitwise)
        self.assertIn("function translateAll(text: string): var", keymap)
        self.assertIn("function transliterate(text: string): string", keymap)

        # Off by default, and the tier that can match something unintended runs
        # only when the precise passes between them found nothing.
        self.assertIn("property bool enable: false", config)
        self.assertIn("property bool keyboardLayouts: true", config)
        self.assertIn("function matchApplications(query: string): var", launcher)
        self.assertIn("if (primary.length > 0)\n            return primary;", launcher)
        self.assertIn("if (typosEnabled && extra.length === 0)", launcher)
        self.assertIn("function typoQuery(search: string): var", appsearch)

    def test_review_part_three_fixes_are_in_place(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        item = source("modules/ii/overview/SearchItem.qml")
        router = source("modules/ii/overview/SearchKeyRouter.qml")
        appsearch = source("services/AppSearch.qml")
        launcher = source("services/LauncherSearch.qml")

        # 3.1 — fuzzysort accepts any subsequence without a floor.
        self.assertIn("function trimFuzzyResults(results: var): var", appsearch)
        self.assertIn("threshold: root.fuzzyThreshold", appsearch)
        # 3.2 — a lone group's caption names nothing.
        self.assertIn('const showCaptions = root.resultCategoryId === "all" && groupCount > 1', widget)
        # 3.4 — reaching the last group a row at a time costs ten keystrokes.
        self.assertIn("function sectionJump(step: int): bool", widget)
        self.assertIn('case "sectionNext":', router)
        # 3.5 — one tag pair for the first contiguous run, not confetti across
        # every later fuzzy-match island.
        highlight = item.split("function highlightContent(content, query)", 1)[1].split("property string displayContent", 1)[0]
        self.assertEqual(highlight.count("root.highlightPrefix"), 1)
        # 3.6 — app rows depend on the entry, not on the keystroke.
        self.assertIn("property var appResultCache", launcher)
        # 3.7 — row durations have to follow the animation multiplier.
        self.assertIn("function scaledDuration(milliseconds: int): int", item)
        self.assertNotIn("duration: 250", item)
        # 3.8 — alwaysRunToEnd on a Flickable's own contentY.
        self.assertNotIn("alwaysRunToEnd: true\n                            duration: Appearance.animation.scroll", widget)
        # 3.9 / 3.10 — shaders that ran on the frames that could least afford them.
        self.assertNotIn("MultiEffect", widget)
        self.assertIn("root.activePanelUsesHost || root.isAiMode || root.showSuggestionsPanel", widget)

    def test_close_animation_does_not_collapse_the_widget_mid_exit(self):
        widget = source("modules/ii/overview/SearchWidget.qml")

        # Closing clears the query and the rows, which collapses the container
        # back to the bare field. Left alone that ran while the window was
        # already sliding out — two motions stacked, so a close with results on
        # screen looked faster and harsher than a close with an empty field.
        self.assertIn("property bool exiting: false", widget)
        self.assertIn("root.exitHeight = searchWidgetContent.height", widget)
        # The freeze has to be taken before the handlers that clear the query,
        # which sit on the same signal.
        self.assertIn("root.exiting ? root.exitHeight : searchWidgetContent.height", widget)
        self.assertIn("root.exiting ? root.exitHeight : implicitHeight", widget)
        # And released on the way back in, so a fast reopen is not stuck frozen.
        self.assertIn("exitHoldTimer.stop();\n                root.exiting = false;", widget)

    def test_best_match_row_is_the_row_the_cursor_lands_on(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        hero = source("modules/ii/overview/SearchBestMatch.qml")
        bar = source("modules/ii/overview/SearchBar.qml")
        config = source("modules/common/Config.qml")
        launcher_page = source("modules/settings/configs/LauncherConfig.qml")

        self.assertIn("property bool enable: false", config)
        self.assertIn("property int secondaryActions: 4", config)
        # The action set is shared with the Ctrl+K panel rather than being the
        # result's own `actions`, which most desktop entries never define.
        actions = source("modules/common/SearchResultActions.qml")
        item = source("modules/ii/overview/SearchItem.qml")
        self.assertIn("function build(entry: var, callbacks: var): var", actions)
        self.assertIn("SearchResultActions.build(root.entry", item)
        self.assertIn("SearchResultActions.build(root.entry", hero)
        # A result's own actions outrank the launcher's housekeeping ones for
        # the few slots the row can show.
        self.assertLess(actions.index("const entryActions = entry.actions"),
                        actions.index('Translation.tr("Pin to Dock")'))
        self.assertIn("property bool uniformList: true", config)
        self.assertIn("Config.options.search.bestMatch.enable = checked", launcher_page)

        # Promotion picks the first emitted row, so what Enter does and what the
        # prominent row shows can never disagree.
        self.assertIn("rows[i].isHero = true", widget)
        self.assertIn("const heroActive = root.bestMatchActive && query.length > 0", widget)
        # And the captions the prominent row replaces go away with it.
        self.assertIn("!(heroActive && root.bestMatchUniformList)", widget)
        self.assertIn('if (resultDelegate.modelData.isHero === true)', widget)

        # Actions that used to exist only behind Ctrl+K are on the row, and
        # reachable without the mouse.
        self.assertIn("readonly property var secondaryActions", hero)
        self.assertIn("function runSecondary(index: int)", hero)
        # A RowLayout cannot shrink children below their implicit width, so the
        # chips ran off the panel. They wrap instead, and a single overlong
        # action name elides rather than widening the row past it.
        self.assertIn("Flow {", hero)
        self.assertNotIn("Item {\n                Layout.fillWidth: true\n            }", hero)
        self.assertIn("Layout.maximumWidth: 150", hero)
        self.assertIn("Layout.preferredHeight: actionFlow.implicitHeight", hero)
        self.assertIn("event.key >= Qt.Key_1 && event.key <= Qt.Key_9", bar)
        self.assertIn("signal runSecondaryAction(int index)", bar)
        # The panel stays the home of the complete set.
        self.assertIn('keys: ["Ctrl", "K"]', hero)

    def test_collapsed_search_does_not_reserve_hidden_result_margins(self):
        widget = source("modules/ii/overview/SearchWidget.qml")
        self.assertIn("implicitHeight: !resultsActive", widget)
        self.assertIn("? 0", widget)
        self.assertIn("rowSpacing: 0", widget)
        self.assertIn("topMargin: 0", widget)
        # The corner blends across the container's own (already animated) height
        # instead of snapping on a flag, so a still-tall panel never wears the
        # collapsed pill radius mid-collapse.
        self.assertIn("const pill = Appearance.rounding.verylarge", widget)
        self.assertIn("const panel = Appearance.rounding.windowRounding", widget)
        self.assertIn("cornerBlendDistance", widget)
        self.assertNotIn("radius: root.showResults", widget)
        self.assertNotIn("Behavior on radius", widget)
        self.assertIn("showIdleNowPlaying", widget)
        self.assertNotIn('searchingText === "" && LauncherSearch.results.length > 0', widget)
        self.assertIn("Layout.bottomMargin: root.isAiMode ? 0 : verticalPadding", widget)
        # ListView margins are viewport decoration, not content. When the model
        # is empty they must not create a results surface of their own.
        self.assertIn("appResults.count === 0", widget)
        results_surface_height = widget.split("id: appResultsSurface", 1)[1].split(
            "Behavior on opacity", 1
        )[0]
        self.assertIn("appResults.measuredContentExtent", results_surface_height)
        self.assertNotIn("appResults.contentHeight", results_surface_height)
        self.assertIn("function updateMeasuredContentExtent()", widget)
        self.assertIn("id: resultsExtentSyncTimer", widget)
        self.assertIn("onContentHeightChanged: resultsExtentSyncTimer.restart()", widget)
        # Opening clears the local ListModel. An already-running MPRIS player
        # must hydrate it again; otherwise resultsActive reserves only the
        # ListView's bottom margin and the collapsed pill grows by 10px.
        self.assertIn(
            "if (root.alwaysListAppsMode || root.showIdleNowPlaying)", widget
        )
        results_changed = widget.split("function onResultsChanged()", 1)[1].split(
            "model: ListModel", 1
        )[0]
        self.assertIn(
            "const nextRows = root.processResults(LauncherSearch.results);",
            results_changed,
        )
        self.assertIn("nextRows.length === 0", results_changed)
        self.assertIn("appResults.applyResultDiff(nextRows)", results_changed)

    def test_calendar_has_upcoming_agenda_and_real_create_form(self):
        panel = source("modules/ii/overview/CalendarPanel.qml")
        form = source("modules/ii/overview/calendar/CalendarCreateForm.qml")
        google = source("services/GoogleCalendarService.qml")
        self.assertIn("property bool upcomingMode: true", panel)
        self.assertIn("CalendarCreateForm", panel)
        self.assertIn("function submitFields(fields): bool", panel)
        for field in ("titleField", "startDateField", "startTimeField", "endDateField", "endTimeField", "locationField", "allDayButton"):
            self.assertIn("id: " + field, form)
        self.assertNotIn("property bool checked", form)
        self.assertIn("allDayButton.toggled", form)
        self.assertIn('mutationState = "success"', google)
        self.assertIn('root.syncing = false;\n                    root.mutationState = "success"', google)
        self.assertIn("Qt.callLater(root.refresh)", google)

    def test_calendar_create_form_has_persistent_labels_and_clear_actions(self):
        form = source("modules/ii/overview/calendar/CalendarCreateForm.qml")

        self.assertIn("component LabeledField", form)
        self.assertIn("component CompactField", form)
        self.assertIn("property bool validationAttempted: false", form)
        for label in (
            "Event title",
            "Starts",
            "Ends",
            "Date",
            "Time",
            "Location",
            "All-day event",
        ):
            self.assertIn('Translation.tr("' + label + '")', form)
        self.assertIn("MaterialShapeWrappedMaterialSymbol", form)
        self.assertIn("id: createEventButton", form)
        self.assertIn("RippleButtonWithIcon", form)
        self.assertIn("KeyNavigation.tab", form)
        # StyledToolTip inherits QtQuick.Controls.ToolTip and has no placement
        # property named `side`; using it makes the whole form type unavailable.
        self.assertNotIn("side: Tooltip", form)

    def test_calendar_children_import_translation_and_quick_create_uses_a_signal(self):
        calendar_dir = ROOT / "modules/ii/overview/calendar"
        translated_components = [
            path
            for path in calendar_dir.glob("*.qml")
            if "Translation.tr" in path.read_text(encoding="utf-8")
        ]
        self.assertGreater(len(translated_components), 0)
        for path in translated_components:
            self.assertIn(
                "import qs.services",
                path.read_text(encoding="utf-8"),
                path.name,
            )

        quick_create = source("modules/ii/overview/calendar/CalendarQuickCreate.qml")
        panel = source("modules/ii/overview/CalendarPanel.qml")
        self.assertNotIn("property var onCreate", quick_create)
        self.assertIn("signal createRequested()", quick_create)
        self.assertIn("root.createRequested()", quick_create)
        self.assertIn("onCreateRequested: root.createFromQuery()", panel)
        self.assertIn("hints: root.createPageOpen", panel)
        self.assertIn('{ label: Translation.tr("Back"), keys: ["Esc"] }', panel)

    def test_alias_catalog_covers_every_public_search_panel_and_wraps_all_rows(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        aliases = source("modules/settings/configs/widgets/LauncherAliasesConfig.qml")
        legacy = source("modules/settings/configs/AppSearchConfig.qml")
        launcher = source("services/LauncherSearch.qml")

        public_panels = (
            "clipboard",
            "fileBrowser",
            "bluetooth",
            "translator",
            "mediaDownloader",
            "materialSymbols",
            "ai",
            "calendar",
            "tasks",
            "timers",
            "emojis",
            "screenshots",
            "windows",
            "settings",
            "keybinds",
            "commands",
            "gmail",
            "sports",
            "tools",
        )
        for panel_id in public_panels:
            self.assertIn('id: "' + panel_id + '"', registry)

        registered_files = {
            line.split('source: "', 1)[1].split('"', 1)[0]
            for line in registry.splitlines()
            if 'source: "' in line and 'Panel.qml"' in line
        }
        panel_directory = ROOT / "modules/ii/overview"
        public_files = {
            path.name
            for path in panel_directory.glob("*Panel.qml")
            if path.name not in {"SearchPanelHost.qml", "SuggestionsPanel.qml"}
        }
        self.assertEqual(public_files, registered_files)

        self.assertIn("root.panels.filter(panel => panel.aliasable !== false)", registry)
        for page in (aliases, legacy):
            self.assertIn("SearchPanelRegistry.aliasTargets.concat([", page)
            self.assertIn("id: builtinFlow", page)
            self.assertIn("Layout.preferredHeight: builtinFlow.implicitHeight", page)
            self.assertIn("modelData.enabled === false", page)
        self.assertNotIn('{ "id": "emojis", "name": Translation.tr("Emoji Picker")', aliases)
        self.assertIn('if (panel.id === "ai")', launcher)
        self.assertIn("return panel.enabled()", launcher)

    def test_window_panel_targets_live_open_windows(self):
        panel = source("modules/ii/overview/WindowManagementPanel.qml")
        self.assertIn("HyprlandData.windowList", panel)
        self.assertIn("HyprlandData.activeWorkspace", panel)
        self.assertIn("targetAddress", panel)
        self.assertIn("targetStrip", panel)
        self.assertIn("WindowActionRegistry.execute", panel)

    def test_window_target_chip_sizes_its_image_through_the_layout(self):
        panel = source("modules/ii/overview/WindowManagementPanel.qml")
        target_chip = panel.split("id: targetChipContent", 1)[1].split("StyledText {", 1)[0]

        # StyledImage inherits Image, whose implicit dimensions are read-only.
        # The target strip is a RowLayout, so it must receive an explicit layout
        # size rather than attempting to overwrite Image.implicitHeight.
        self.assertIn("Layout.preferredWidth: Appearance.font.pixelSize.normal", target_chip)
        self.assertIn("Layout.preferredHeight: Appearance.font.pixelSize.normal", target_chip)
        self.assertNotIn("implicitHeight:", target_chip)

    def test_window_action_cards_fit_their_grid_cells_without_stacked_hints(self):
        panel = source("modules/ii/overview/WindowManagementPanel.qml")
        action_grid = panel.split("id: actionGrid", 1)[1].split("ColumnLayout {\n                    anchors.centerIn", 1)[0]

        self.assertIn(
            "readonly property real actionCardHeight: Appearance.sizes.elevationMargin * 5.5",
            panel,
        )
        self.assertIn("cellHeight: root.actionCardHeight", action_grid)
        self.assertIn("RowLayout {", action_grid)
        self.assertNotIn("ColumnLayout {", action_grid)
        self.assertIn("modelData.keyHint.length === 0", action_grid)

    def test_generators_have_a_panel_preview_and_feedback(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        panel = source("modules/ii/overview/ToolsPanel.qml")
        devtools_registry = source("modules/common/DevToolsRegistry.qml")
        launcher = source("services/LauncherSearch.qml")
        self.assertIn('id: "tools"', registry)
        for tool_id in ("uuid", "password", "lorem", "base64", "json_formatter"):
            self.assertIn('id: "' + tool_id + '"', devtools_registry)
        self.assertIn("outputText", panel)
        self.assertIn("Copied to clipboard", panel)
        self.assertIn("feedbackText", launcher)

    def test_settings_pages_are_discoverable_and_close_search_before_opening(self):
        registry = source("modules/common/SettingsPageRegistry.qml")
        panel = source("modules/ii/overview/SettingsTogglesPanel.qml")
        launcher = source("services/LauncherSearch.qml")
        for page in ("LauncherModulesConfig.qml", "LauncherQuicklinksConfig.qml", "LauncherSnippetsConfig.qml", "LauncherShortcutsConfig.qml", "LauncherAppearanceConfig.qml", "LauncherDataConfig.qml"):
            self.assertIn(page, registry)
        self.assertIn("function humanizeSubPage(path)", panel)
        self.assertIn("GlobalStates.overviewOpen = false", panel)
        settings_result = launcher.split("function createSettingsResultObject", 1)[1].split("function createSettingsPanelResultObject", 1)[0]
        self.assertIn("GlobalStates.overviewOpen = false", settings_result)

    def test_settings_panel_preserves_filter_and_has_expressive_recovery_states(self):
        states = source("GlobalStates.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        panel = source("modules/ii/overview/SettingsTogglesPanel.qml")
        launcher = source("services/LauncherSearch.qml")
        card = source("services/ai/blocks/AiSettingResultCard.qml")

        self.assertIn("property string searchPendingPanelQuery", states)
        self.assertIn("consumePendingSearchPanelQuery", states)
        self.assertIn("consumePendingSearchPanelQuery", widget)
        self.assertIn('openSearchPanel("settings", "", queryText)', launcher)
        self.assertIn("StackLayout", panel)
        self.assertIn("MaterialShape", panel)
        self.assertIn("requestSetSearchQuery", panel)
        self.assertIn("expressiveStyle: true", panel)
        self.assertNotIn("implicitHeight: childrenRect.height", panel)
        self.assertIn("property bool expressiveStyle: false", card)
        self.assertIn("readonly property bool canEditInline", card)
        self.assertIn("readonly property string settingIcon", card)
        self.assertIn("text: root.settingIcon", card)
        self.assertIn("root.setting?.hasUi === true", card)

    def test_settings_panel_is_compact_tonal_and_keyboard_complete(self):
        panel = source("modules/ii/overview/SettingsTogglesPanel.qml")
        card = source("services/ai/blocks/AiSettingResultCard.qml")

        self.assertIn("function secondaryActivateSelected(): bool", panel)
        self.assertIn("id: sectionCountShape", panel)
        self.assertIn("id: sectionButtonContent", panel)
        self.assertNotIn("implicitHeight: Appearance.sizes.elevationMargin * 7", panel)
        self.assertIn("readonly property color selectedSurfaceColor: Appearance.colors.colPrimaryContainer", card)
        self.assertIn("readonly property color selectedAccentColor: Appearance.colors.colPrimary", card)
        self.assertIn("id: openSettingsButton", card)
        self.assertIn('text: Translation.tr("Open")', card)
        self.assertIn('actionId: "secondary"', card)
        self.assertIn("ConfiguredKeyHint", card)
        self.assertIn("if (root.compact && root.expressiveStyle)", card)

    def test_every_new_panel_exposes_item_level_keyboard_hints(self):
        configured_hint = source("modules/common/widgets/ConfiguredKeyHint.qml")
        hint_bar = source("modules/common/widgets/KeyHintBar.qml")
        self.assertIn("property string actionId", configured_hint)
        self.assertIn("Config.options.search.keybindings", configured_hint)
        self.assertIn("fallbackKeys", configured_hint)
        self.assertIn("ConfiguredKeyHint", hint_bar)

        paths = (
            "modules/ii/overview/calendar/CalendarEventBlock.qml",
            "modules/ii/overview/TasksPanel.qml",
            "modules/ii/overview/TimersPanel.qml",
            "modules/ii/overview/EmojiPanel.qml",
            "modules/ii/overview/ScreenshotsPanel.qml",
            "modules/ii/overview/WindowManagementPanel.qml",
            "modules/ii/overview/SettingsTogglesPanel.qml",
            "modules/ii/overview/KeybindsPanel.qml",
            "modules/ii/overview/CommandsPanel.qml",
            "modules/ii/overview/GmailPanel.qml",
            "modules/ii/overview/SportsPanel.qml",
            "modules/ii/overview/ToolsPanel.qml",
        )
        for path in paths:
            self.assertIn("ConfiguredKeyHint", source(path), path)

    def test_sports_score_column_stays_geometrically_centered(self):
        panel = source("modules/ii/overview/SportsPanel.qml")
        self.assertIn("readonly property real columnWidth", panel)
        self.assertEqual(panel.count("Layout.preferredWidth: gameContent.columnWidth"), 3)

    def test_generator_selection_hint_does_not_resize_or_hover_scale_card(self):
        panel = source("modules/ii/overview/ToolsPanel.qml")
        self.assertIn("scale: down ? 0.98 : 1.0", panel)
        self.assertIn("anchors.bottom: parent.bottom", panel)
        self.assertIn("anchors.right: parent.right", panel)

    def test_new_search_surfaces_do_not_introduce_borders(self):
        paths = (
            "modules/ii/overview/CalendarPanel.qml",
            "modules/ii/overview/calendar/CalendarCreateForm.qml",
            "modules/ii/overview/TasksPanel.qml",
            "modules/ii/overview/TimersPanel.qml",
            "modules/ii/overview/EmojiPanel.qml",
            "modules/ii/overview/ScreenshotsPanel.qml",
            "modules/ii/overview/WindowManagementPanel.qml",
            "modules/ii/overview/SettingsTogglesPanel.qml",
            "modules/ii/overview/CommandsPanel.qml",
            "modules/ii/overview/GmailPanel.qml",
            "modules/ii/overview/SportsPanel.qml",
            "modules/ii/overview/ToolsPanel.qml",
        )
        for path in paths:
            self.assertNotIn("border.", source(path), path)

    def test_launcher_module_settings_explain_exact_search_terms(self):
        switch = source("modules/common/widgets/ConfigSwitch.qml")
        modules = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        self.assertIn('property string description: ""', switch)
        for term in ("calendar", "window", "screenshot", "generator", "uuid", "password", "lorem"):
            self.assertIn(term, modules.lower())

    def test_persistence_uses_explicit_list_types(self):
        config = source("modules/common/Config.qml")
        persistent = source("modules/common/Persistent.qml")
        self.assertIn("property list<var> keybindings", config)
        self.assertIn("property list<string> actions", config)
        self.assertIn("property list<string> recentQueries", persistent)
        self.assertIn("property list<string> pinnedEntries", persistent)
        self.assertIn("property list<var> panelUsage", persistent)
        self.assertIn("property list<var> historySeen", persistent)

    def test_clipboard_retention_is_configurable_and_preserves_pins(self):
        config = source("modules/common/Config.qml")
        settings = source("modules/settings/configs/ClipboardConfig.qml")
        cliphist = source("services/Cliphist.qml")
        self.assertIn("property JsonObject autoDelete", config)
        self.assertIn("retentionDays", config)
        self.assertIn("Delete clipboard history automatically", settings)
        self.assertIn("function synchronizeRetention()", cliphist)
        self.assertIn("!root.isPinned(entry)", cliphist)
        self.assertIn("function wipeUnpinned()", cliphist)
        self.assertIn("function wipeUnpinnedOnShutdown()", cliphist)
        self.assertIn("onAboutToQuit", cliphist)

    def test_shortcuts_are_local_and_processes_stay_in_user_scope(self):
        search_bar = source("modules/ii/overview/SearchBar.qml")
        resources = source("services/ResourceUsage.qml")
        self.assertIn("configuredShortcut", search_bar)
        self.assertIn("matchesShortcut", search_bar)
        self.assertIn('ps -u \\"$(id -u)\\"', resources)
        self.assertIn("pid=,comm=,pcpu=,pmem=", resources)
        self.assertIn('"kill", "-TERM"', source("services/LauncherSearch.qml"))

    def test_quicklinks_support_custom_images_and_generic_panel_routing(self):
        result_model = source("modules/common/models/LauncherSearchResult.qml")
        quicklinks = source("modules/settings/configs/widgets/LauncherQuicklinksConfig.qml")
        launcher = source("services/LauncherSearch.qml")
        item = source("modules/ii/overview/SearchItem.qml")
        states = source("GlobalStates.qml")
        overview = source("modules/ii/overview/Overview.qml")
        self.assertIn("System, Image, None", result_model)
        self.assertIn("iconPathDraft", quicklinks)
        self.assertIn("FileDialog", quicklinks)
        self.assertIn("link?.iconPath", launcher)
        self.assertIn("function quicklinkFavicon(url)", launcher)
        self.assertIn("fetchFavicons", quicklinks)
        self.assertIn("LauncherSearchResult.IconType.Image", item)
        self.assertIn('source: visible ? root.iconName : ""', item)
    def test_search_now_playing_redesign_contract(self):
        now_playing = source("modules/ii/overview/SearchNowPlaying.qml")
        search_item = source("modules/ii/overview/SearchItem.qml")
        search_widget = source("modules/ii/overview/SearchWidget.qml")
        launcher = source("services/LauncherSearch.qml")
        result_model = source("modules/common/models/LauncherSearchResult.qml")
        config = source("modules/common/Config.qml")
        app_search_config = source("modules/settings/configs/AppSearchConfig.qml")

        # 1. SearchNowPlaying component checks
        self.assertIn("vignetteMask", now_playing)
        self.assertIn("artBlurredUnderlay", now_playing)
        self.assertIn("artExpanded", now_playing)
        self.assertIn("property bool artDownloaded: false", now_playing)
        self.assertIn("readonly property bool supportsHorizontalNavigation: true", now_playing)
        self.assertIn("function navigateLeft(): bool", now_playing)
        self.assertIn("function navigateRight(): bool", now_playing)
        self.assertIn("function activate(): bool", now_playing)
        self.assertIn("ColorQuantizer", now_playing)
        self.assertIn('text: root.isPlaying ? "pause" : "play_arrow"', now_playing)

        # 2. SearchItem decoupling checks
        self.assertNotIn("isNowPlaying", search_item)
        self.assertNotIn("nowPlayingLoader", search_item)
        self.assertNotIn("artDownloaded", search_item)
        self.assertNotIn("Directories.coverArt", search_item)

        # 3. Model & Service checks
        for prop in ("trackTitle", "trackArtist", "trackAlbum", "trackArtUrl", "isPlaying", "playerIdentity", "canGoPrevious", "canGoNext", "canTogglePlaying"):
            self.assertIn(f"property string {prop}" if "track" in prop or prop == "playerIdentity" else f"property bool {prop}", result_model)
            self.assertIn(f"{prop}:", launcher)

        # 4. SearchWidget routing
        self.assertIn('resultDelegate.modelData.modelRef?.key === "mpris:now-playing"', search_widget)
        self.assertIn("id: nowPlayingRow", search_widget)
        self.assertIn("SearchNowPlaying", search_widget)

        # 5. Config structure
        self.assertIn("property JsonObject nowPlaying: JsonObject {", config)
        self.assertIn("property bool enable: true", config)
        self.assertIn("property bool showInlineControls: true", config)
        self.assertIn("property bool tintFromArtwork: false", config)
        self.assertIn("property bool showPlayerName: true", config)
        self.assertIn("Config.options.search.nowPlaying?.enable", app_search_config)

    def test_search_appearance_settings_drive_the_rendered_surface(self):
        appearance_config = source("modules/settings/configs/widgets/LauncherAppearanceConfig.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")

        # Centered Search has a persisted vertical placement control, and it is
        # unavailable while the center positioning mode itself is inactive.
        self.assertIn('text: Translation.tr("Centered search vertical position")', appearance_config)
        self.assertIn("Config.options.search.centerVerticalRatio = value / 100", appearance_config)
        self.assertIn('checked: Config.options.search.positionStyle === "center"', appearance_config)

        # Search surface background uses the consistent surface container color
        # for both search results and all hosted panels.
        self.assertIn("Appearance.colors.colBackgroundSurfaceContainer", widget)

        # The max-height control limits the normal result list as a complete
        # Search surface (bar plus results) and applies live after a slider edit.
        self.assertIn("readonly property real normalSearchChromeHeight", widget)
        self.assertIn("Config.options.search.baseHeight", widget)
        self.assertIn("onMaxResultsHeightChanged", widget)
        self.assertNotIn("readonly property real maxResultsHeight: 600", widget)


if __name__ == "__main__":
    unittest.main()
