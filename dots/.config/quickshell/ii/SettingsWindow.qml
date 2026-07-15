pragma ComponentBehavior: Bound

//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import "modules/settings"
import "modules/settings/configs"

FloatingWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false

    property int currentPage: 0
    property real scrollPos: 0
    property int previousPage: 0
    property string lastSearch: ""
    property int lastSearchIndex: -1
    property int resultsCount: 0
    property string activeSearchQuery: ""

    property string pendingSectionHighlight: ""

    // ── Flat page list (order determines pageIndex) ──────────────────────
    property var pages: [
        // Group 1 – Look & Feel (indices 0..4)
        {
            name: Translation.tr("Colors & Themes"),
            icon: "palette",
            component: "modules/settings/configs/ColorsThemesConfig.qml"
        },
        {
            name: Translation.tr("Bar & Status Bar"),
            icon: "space_bar",
            component: "modules/settings/configs/BarConfig.qml"
        },
        {
            name: Translation.tr("Backgrounds"),
            icon: "wallpaper",
            component: "modules/settings/configs/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Interface & Fonts"),
            icon: "font_download",
            component: "modules/settings/configs/InterfaceFontsConfig.qml"
        },
        {
            name: Translation.tr("Presets"),
            icon: "auto_awesome",
            component: "modules/settings/configs/PresetsConfig.qml"
        },
        // Group 2 – Modules (indices 5..10)
        {
            name: Translation.tr("Sidebars & Panels"),
            icon: "side_navigation",
            component: "modules/settings/configs/SidebarsConfig.qml"
        },
        {
            name: Translation.tr("Dock"),
            icon: "dock_to_bottom",
            component: "modules/settings/configs/DockConfig.qml"
        },
        {
            name: Translation.tr("Workspaces"),
            icon: "workspaces",
            component: "modules/settings/configs/WorkspacesConfig.qml"
        },
        {
            name: Translation.tr("Overview Screen"),
            icon: "grid_view",
            component: "modules/settings/configs/OverviewConfig.qml"
        },
        {
            name: Translation.tr("Desktop Widgets"),
            icon: "widgets",
            component: "modules/settings/configs/WidgetsConfig.qml"
        },
        {
            name: Translation.tr("Dynamic Island"),
            icon: "water_drop",
            component: "modules/settings/configs/DynamicIslandConfig.qml"
        },
        // Group 3 – Tools & Overlays (indices 11..15)
        {
            name: Translation.tr("System Overlays"),
            icon: "picture_in_picture",
            component: "modules/settings/configs/OverlaysConfig.qml"
        },
        {
            name: Translation.tr("Region Selector"),
            icon: "screenshot_region",
            component: "modules/settings/configs/RegionSelectorConfig.qml"
        },
        {
            name: Translation.tr("App Search"),
            icon: "search",
            component: "modules/settings/configs/AppSearchConfig.qml"
        },
        {
            name: Translation.tr("Cheat Sheet"),
            icon: "help",
            component: "modules/settings/configs/CheatSheetConfig.qml"
        },
        {
            name: Translation.tr("Hyprland Rules"),
            icon: "rule",
            component: "modules/settings/configs/HyprlandRulesConfig.qml"
        },
        // Group 4 – System & Services (indices 16..20)
        {
            name: Translation.tr("Monitors"),
            icon: "monitor",
            component: "modules/settings/configs/MonitorsConfig.qml"
        },
        {
            name: Translation.tr("Core Services"),
            icon: "settings_suggest",
            component: "modules/settings/configs/CoreServicesConfig.qml"
        },
        {
            name: Translation.tr("Lock Screen"),
            icon: "lock",
            component: "modules/settings/configs/LockScreenConfig.qml"
        },
        {
            name: Translation.tr("About & Updates"),
            icon: "info",
            component: "modules/settings/configs/AboutConfig.qml"
        },
        {
            name: Translation.tr("User Profile"),
            icon: "account_circle",
            component: "modules/settings/configs/UserProfileConfig.qml"
        },
        {
            name: Translation.tr("Search Results"),
            icon: "search",
            component: "modules/settings/configs/SearchPage.qml"
        }
    ]

    // ── Grouped page list for Sidebar (references indices above) ─────────
    property var pageGroups: [
        {
            name: Translation.tr("Look & Feel"),
            pages: [0, 1, 2, 3, 4].map(i => ({
                        name: pages[i].name,
                        icon: pages[i].icon,
                        pageIndex: i
                    }))
        },
        {
            name: Translation.tr("Modules"),
            pages: [5, 6, 7, 8, 9, 10].map(i => ({
                        name: pages[i].name,
                        icon: pages[i].icon,
                        pageIndex: i
                    }))
        },
        {
            name: Translation.tr("Tools & Overlays"),
            pages: [11, 12, 13, 14, 15].map(i => ({
                        name: pages[i].name,
                        icon: pages[i].icon,
                        pageIndex: i
                    }))
        },
        {
            name: Translation.tr("System & Services"),
            pages: [16, 17, 18, 19].map(i => ({
                        name: pages[i].name,
                        icon: pages[i].icon,
                        pageIndex: i
                    }))
        }
    ]

    title: "illogical-impulse Settings"
    implicitWidth: 1100
    implicitHeight: 750
    minimumSize: Qt.size(750, 500)
    color: "transparent"

    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            root.visible = GlobalStates.settingsOpen;
            if (GlobalStates.settingsOpen) {
                settingsSearchBar.forceFocus();
                if (GlobalStates.settingsPendingPageName !== "") {
                    for (let i = 0; i < root.pages.length; i++) {
                        if (root.pages[i].component.indexOf(GlobalStates.settingsPendingPageName) !== -1) {
                            root.currentPage = i;
                            break;
                        }
                    }
                    GlobalStates.settingsPendingPageName = "";
                } else if (GlobalStates.settingsPendingPage >= 0) {
                    root.currentPage = GlobalStates.settingsPendingPage;
                    GlobalStates.settingsPendingPage = -1;
                }
            }
        }
    }

    onVisibleChanged: {
        if (!visible && GlobalStates.settingsOpen)
            GlobalStates.settingsOpen = false;
    }

    Component.onCompleted: {
        root.visible = GlobalStates.settingsOpen;
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Settings app always only sets one var at a time so delay isn't needed
        // Re-apply ignore alpha rule: Settings is lazy-loaded, so the rule fired
        // in Appearance.onIgnoreAlphaChanged before this window existed. Re-send
        // now that the xdg-toplevel is mapped and Hyprland can match it.
        var a = Appearance.ignoreAlpha;
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.window_rule({ match = { title = '^(illogical-impulse Settings)$' }, no_blur = false, ignorealpha = " + a + " })"]);
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.windowRounding
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        spacing: contentPadding
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: event => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        // ── Top Header Row (User Header + Search Bar) ─────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 56
            spacing: contentPadding

            UserHeader {
                id: userHeader
                Layout.preferredWidth: 230
                Layout.fillHeight: true
                isActive: root.currentPage === 20
                onClicked: root.currentPage = 20
            }

            SearchBar {
                id: settingsSearchBar
                Layout.fillWidth: true
                Layout.fillHeight: true

                lastSearchIndex: root.lastSearchIndex
                resultsCount: root.resultsCount

                onTextChanged: text => {
                    if (text === "") {
                        if (root.currentPage === 21) {
                            root.currentPage = root.previousPage;
                        }
                        root.activeSearchQuery = "";
                        root.resultsCount = 0;
                        root.lastSearchIndex = -1;
                    }
                }

                onAccepted: text => {
                    const result = SearchRegistry.getDynamicSearchResults(text);

                    if (result == null || result.length === 0) {
                        settingsSearchBar.shakeNoResults();
                        root.activeSearchQuery = "";
                        root.resultsCount = 0;
                        root.lastSearchIndex = -1;
                        if (root.currentPage === 21) {
                            root.currentPage = root.previousPage;
                        }
                        return;
                    }

                    let totalWidgets = 0;
                    for (let s of result) {
                        totalWidgets += s.items.length;
                        for (let sub of s.subsections) {
                            totalWidgets += sub.items.length;
                        }
                    }

                    root.resultsCount = totalWidgets;
                    root.lastSearchIndex = 0;

                    if (root.currentPage !== 21) {
                        root.previousPage = root.currentPage;
                    }
                    root.activeSearchQuery = text;
                    SearchRegistry.currentSearch = text;
                    root.currentPage = 21;
                }

                onCloseRequested: GlobalStates.settingsOpen = false
            }
        }

        RowLayout { // Window content with sidebar and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            // ── Sidebar v2 ────────────────────────────────────────────────
            Sidebar {
                id: sidebarV2
                z: 1
                Layout.fillHeight: true
                implicitWidth: 230

                currentPage: root.currentPage
                groups: root.pageGroups

                onPageSelected: idx => {
                    root.currentPage = idx;
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                radius: Appearance.rounding.windowRounding
                clip: true

                Loader {
                    id: pageLoader
                    width: parent.width
                    height: parent.height
                    opacity: 1.0
                    transformOrigin: Item.Left

                    active: Config.ready
                    asynchronous: true
                    Component.onCompleted: {
                        source = root.pages[root.currentPage].component;
                    }

                    property bool _waitingForLoad: false

                    onLoaded: {
                        if (root.pendingSectionHighlight !== "") {
                            pendingHighlightTimer.restart();
                        }
                        if (_waitingForLoad) {
                            _waitingForLoad = false;
                            pageLoadWaitTimer.stop();
                            switchAnimIncoming.start();
                        }
                    }

                    Timer {
                        id: pendingHighlightTimer
                        interval: 150
                        repeat: false
                        onTriggered: {
                            if (root.pendingSectionHighlight !== "") {
                                SearchRegistry.currentSearch = root.pendingSectionHighlight;
                                root.pendingSectionHighlight = "";
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnimOutgoing.complete();
                            switchAnimOutgoing.start();
                        }
                        function onScrollPosChanged() {
                            if (root.scrollPos == -1)
                                return;
                            scrollTimer.start();
                        }
                    }

                    Timer {
                        id: scrollTimer
                        interval: 250
                        onTriggered: {
                            pageLoader.item.contentY = root.scrollPos;
                            root.scrollPos = -1;
                        }
                    }

                    SequentialAnimation {
                        id: switchAnimOutgoing

                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                from: 1
                                to: 0
                                duration: 150
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "scale"
                                from: 1
                                to: 0.95
                                duration: 150
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "x"
                                from: 0
                                to: 120
                                duration: 150
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                            }
                        }
                        onFinished: {
                            pageLoader.source = root.pages[root.currentPage].component;
                            pageLoader.x = -120;
                            pageLoader._waitingForLoad = true;
                            pageLoadWaitTimer.start();
                        }
                    }

                    Timer {
                        id: pageLoadWaitTimer
                        interval: 16
                        repeat: true
                        property real _startTime: 0
                        onTriggered: {
                            if (!pageLoader._waitingForLoad) {
                                stop();
                                return;
                            }
                            if (pageLoader.status === Loader.Ready) {
                                pageLoader._waitingForLoad = false;
                                stop();
                                switchAnimIncoming.start();
                            } else if (Date.now() - _startTime > 2000) {
                                pageLoader._waitingForLoad = false;
                                stop();
                                switchAnimIncoming.start();
                            }
                        }
                        onRunningChanged: {
                            if (running) _startTime = Date.now();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnimIncoming

                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 400
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "scale"
                                from: 0.95
                                to: 1
                                duration: 400
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "x"
                                to: 0
                                duration: 400
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }
                        }
                    }
                } // closes Loader
            } // closes Rectangle (Content container)
        } // closes RowLayout (Window content)
    } // closes ColumnLayout
}
