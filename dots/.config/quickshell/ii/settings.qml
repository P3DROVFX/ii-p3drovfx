//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

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

ApplicationWindow {
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

    // ── Flat page list (order determines pageIndex) ──────────────────────
    // pageIndex is the position in this array; used by Sidebar + Loader.
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
        // Group 2 – Modules (indices 5..9)
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
        // Group 3 – Tools & Overlays (indices 10..13)
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
        // Group 4 – System & Services (indices 14..18)
        {
            name: Translation.tr("Hyprland Rules"),
            icon: "rule",
            component: "modules/settings/configs/HyprlandRulesConfig.qml"
        },
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
            pages: [
                {
                    name: pages[0].name,
                    icon: pages[0].icon,
                    pageIndex: 0
                },
                {
                    name: pages[1].name,
                    icon: pages[1].icon,
                    pageIndex: 1
                },
                {
                    name: pages[2].name,
                    icon: pages[2].icon,
                    pageIndex: 2
                },
                {
                    name: pages[3].name,
                    icon: pages[3].icon,
                    pageIndex: 3
                },
                {
                    name: pages[4].name,
                    icon: pages[4].icon,
                    pageIndex: 4
                }
            ]
        },
        {
            name: Translation.tr("Modules"),
            pages: [
                {
                    name: pages[5].name,
                    icon: pages[5].icon,
                    pageIndex: 5
                },
                {
                    name: pages[6].name,
                    icon: pages[6].icon,
                    pageIndex: 6
                },
                {
                    name: pages[7].name,
                    icon: pages[7].icon,
                    pageIndex: 7
                },
                {
                    name: pages[8].name,
                    icon: pages[8].icon,
                    pageIndex: 8
                },
                {
                    name: pages[9].name,
                    icon: pages[9].icon,
                    pageIndex: 9
                }
            ]
        },
        {
            name: Translation.tr("Tools & Overlays"),
            pages: [
                {
                    name: pages[10].name,
                    icon: pages[10].icon,
                    pageIndex: 10
                },
                {
                    name: pages[11].name,
                    icon: pages[11].icon,
                    pageIndex: 11
                },
                {
                    name: pages[12].name,
                    icon: pages[12].icon,
                    pageIndex: 12
                },
                {
                    name: pages[13].name,
                    icon: pages[13].icon,
                    pageIndex: 13
                }
            ]
        },
        {
            name: Translation.tr("System & Services"),
            pages: [
                {
                    name: pages[14].name,
                    icon: pages[14].icon,
                    pageIndex: 14
                },
                {
                    name: pages[15].name,
                    icon: pages[15].icon,
                    pageIndex: 15
                },
                {
                    name: pages[16].name,
                    icon: pages[16].icon,
                    pageIndex: 16
                },
                {
                    name: pages[17].name,
                    icon: pages[17].icon,
                    pageIndex: 17
                },
                {
                    name: pages[18].name,
                    icon: pages[18].icon,
                    pageIndex: 18
                }
            ]
        }
    ]

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 0; // Settings app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

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
                isActive: root.currentPage === 19
                onClicked: root.currentPage = 19
            }

            SearchBar {
                id: settingsSearchBar
                Layout.fillWidth: true
                Layout.fillHeight: true

                lastSearchIndex: root.lastSearchIndex
                resultsCount: root.resultsCount

                onTextChanged: text => {
                    if (text === "") {
                        if (root.currentPage === 20) {
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
                        if (root.currentPage === 20) {
                            root.currentPage = root.previousPage;
                        }
                        return;
                    }

                    // Count total toggles found instead of just sections
                    let totalWidgets = 0;
                    for (let s of result) {
                        totalWidgets += s.items.length;
                        for (let sub of s.subsections) {
                            totalWidgets += sub.items.length;
                        }
                    }

                    root.resultsCount = totalWidgets;
                    root.lastSearchIndex = 0;
                    
                    if (root.currentPage !== 20) {
                        root.previousPage = root.currentPage;
                    }
                    root.activeSearchQuery = text;
                    SearchRegistry.currentSearch = text;
                    root.currentPage = 20;
                }

                onCloseRequested: root.close()
            }
        }

        RowLayout { // Window content with sidebar and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding

            // ── New Sidebar v2 ────────────────────────────────────────────
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

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
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
                        id: switchAnim

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
                        PropertyAction {
                            target: pageLoader
                            property: "source"
                            value: root.pages[root.currentPage].component
                        }
                        PropertyAction {
                            target: pageLoader
                            property: "x"
                            value: -120
                        }
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
                    } // closes SequentialAnimation
                } // closes Loader
            } // closes Rectangle (Content container)
        } // closes RowLayout (Window content)
    } // closes ColumnLayout
} // closes ApplicationWindow
