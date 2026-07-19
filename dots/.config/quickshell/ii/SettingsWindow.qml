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

    // ── Flat page list, derived from SettingsPageRegistry ────────────────
    // Pages are addressed by stable `id`, not index — use pageIndexById().
    property var pages: SettingsPageRegistry.pages.map(p => ({
                id: p.id,
                name: Translation.tr(p.name),
                icon: p.icon,
                component: p.component,
                hidden: p.hidden === true
            }))

    // Hidden pages sit at the end of the list; nav pages come first.
    readonly property int navPageCount: pages.filter(p => !p.hidden).length

    function pageIndexById(id) {
        return SettingsPageRegistry.pageIndexById(id);
    }

    function cycleNavPage(delta) {
        if (root.currentPage >= root.navPageCount) {
            root.currentPage = delta > 0 ? 0 : root.navPageCount - 1;
            return;
        }
        root.currentPage = (root.currentPage + delta + root.navPageCount) % root.navPageCount;
    }

    // ── Grouped page list for Sidebar ────────────────────────────────────
    property var pageGroups: SettingsPageRegistry.groups.map(g => ({
                id: g.id,
                name: Translation.tr(g.name),
                pages: g.pageIds.map(id => {
                    const i = SettingsPageRegistry.pageIndexById(id);
                    return {
                        name: Translation.tr(SettingsPageRegistry.pages[i].name),
                        icon: SettingsPageRegistry.pages[i].icon,
                        pageIndex: i
                    };
                })
            }))

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
                    // Accepts a page id ("coreServices") or a component file name
                    for (let i = 0; i < root.pages.length; i++) {
                        if (root.pages[i].id === GlobalStates.settingsPendingPageName || root.pages[i].component.indexOf(GlobalStates.settingsPendingPageName) !== -1) {
                            root.currentPage = i;
                            break;
                        }
                    }
                    GlobalStates.settingsPendingPageName = "";
                } else if (GlobalStates.settingsPendingPage >= 0) {
                    // Deprecated: index-based deep link — use settingsPendingPageName
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
        radius: Appearance.windowRounding
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
            // Cycling only covers nav pages — hidden pages (profile, search
            // results) are reachable through their own entry points.
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.navPageCount - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(Math.min(root.currentPage, root.navPageCount) - 1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.cycleNavPage(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.cycleNavPage(-1);
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
                isActive: root.currentPage === root.pageIndexById("profile")
                onClicked: root.currentPage = root.pageIndexById("profile")
            }

            SearchBar {
                id: settingsSearchBar
                Layout.fillWidth: true
                Layout.fillHeight: true

                lastSearchIndex: root.lastSearchIndex
                resultsCount: root.resultsCount

                onTextChanged: text => {
                    if (text === "") {
                        if (root.currentPage === root.pageIndexById("search")) {
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
                        if (root.currentPage === root.pageIndexById("search")) {
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

                    if (root.currentPage !== root.pageIndexById("search")) {
                        root.previousPage = root.currentPage;
                    }
                    root.activeSearchQuery = text;
                    SearchRegistry.currentSearch = text;
                    root.currentPage = root.pageIndexById("search");
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
                radius: Appearance.windowRounding
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
