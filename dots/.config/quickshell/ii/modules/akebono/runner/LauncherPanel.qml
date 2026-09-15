pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.akebono
import qs.modules.akebono.shelf.widgets.controlPanel
import qs.modules.lunae.overview
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets

Item {
    id: panel
    clip: true

    signal requestClose()
    signal rightClicked(var entry, real sceneX, real sceneY)

    property string selectedSection: LauncherSearch.pinnedSection
    readonly property int railWidth: 170

    function focusSearch(): void {
        if (GlobalStates.desktopRunnerPendingQuery !== "") {
            searchInput.text = GlobalStates.desktopRunnerPendingQuery;
            GlobalStates.desktopRunnerPendingQuery = "";
        }
        searchInput.forceActiveFocus();
    }
    function resetQuery(): void {
        searchInput.text = "";
        LauncherSearch.query = "";
        panel.selectSection(LauncherSearch.pinnedSection);
    }
    function selectSection(key: string): void {
        panel.selectedSection = key;
        LauncherSearch.activeCategory = LauncherSearch.categoryForSection(key);
    }

    readonly property bool hasQuery: LauncherSearch.query !== ""
    readonly property bool glyphMode: panel.hasQuery && LauncherSearch.isGlyphQuery(LauncherSearch.query)
    readonly property var glyphList: panel.glyphMode ? LauncherSearch.glyphEntries(LauncherSearch.query, null) : []
    readonly property var sections: LauncherSearch.sections
    readonly property var gridApps: LauncherSearch.entriesForSection(panel.selectedSection)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 12

            UserProfileAvatar {
                implicitWidth: 38
                implicitHeight: 38
                avatarShape: Config.options.sidebar?.dashboardHeader?.avatarShape
                    ?? Config.options.userProfile?.avatarShape
            }
            StyledText {
                text: SystemInfo.username
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
                Layout.maximumWidth: 160
            }

            Item { Layout.fillWidth: true }

            Squircle {
                Layout.preferredWidth: 440
                Layout.preferredHeight: 36
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.small

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }

                    ToolbarTextField {
                        id: searchInput
                        Layout.fillWidth: true
                        colBackground: "transparent"
                        placeholderText: "Search apps, math, emojis..."
                        font.pixelSize: Appearance.font.pixelSize.large
                        onTextChanged: LauncherSearch.query = text
                        onAccepted: {
                            if (LauncherSearch.results.length > 0)
                                LauncherSearch.results[0].execute();
                            panel.requestClose();
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                panel.requestClose();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                if (!panel.hasQuery) {
                                    appGrid.currentIndex = 0;
                                    appGrid.forceActiveFocus();
                                } else if (panel.glyphMode) {
                                    glyphGrid.currentIndex = 0;
                                    glyphGrid.forceActiveFocus();
                                } else if (resultsList.count > 0) {
                                    resultsList.currentIndex = 0;
                                    resultsList.forceActiveFocus();
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Item {
                id: railHost
                Layout.preferredWidth: panel.railWidth
                Layout.fillHeight: true
                visible: !panel.glyphMode
                clip: true

                readonly property int selectedIndex: panel.sections.findIndex(s => s.key === panel.selectedSection)

                Squircle {
                    id: activeIndicator
                    z: 0
                    color: Appearance.colors.colSecondaryContainer
                    radius: Appearance.rounding.small
                    smoothing: AkebonoAppearance.squircleSmoothing

                    property Item targetItem: null
                    x: targetItem ? targetItem.x : 0
                    y: targetItem ? targetItem.y - sectionList.contentY : 0
                    width: targetItem ? targetItem.width : 0
                    height: targetItem ? targetItem.height : 0
                    visible: targetItem !== null

                    Timer {
                        interval: 0
                        running: true
                        onTriggered: activeIndicator.targetItem = Qt.binding(() => sectionList.itemAtIndex(railHost.selectedIndex))
                    }
                    Behavior on y {
                        enabled: !sectionList.moving
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                ListView {
                    id: sectionList
                    z: 1
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: panel.sections

                    delegate: Item {
                        id: secBtn
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: 36
                        readonly property bool active: panel.selectedSection === secBtn.modelData.key

                        Squircle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            smoothing: AkebonoAppearance.squircleSmoothing
                            color: Appearance.colors.colLayer2Hover
                            visible: tabMouse.containsMouse && !secBtn.active
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            MaterialSymbol {
                                text: secBtn.modelData.icon
                                iconSize: 18
                                fill: secBtn.active ? 1 : 0
                                color: secBtn.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: secBtn.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: secBtn.active ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                                color: secBtn.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.selectSection(secBtn.modelData.key)
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                visible: !panel.glyphMode
                color: Appearance.colors.colOutlineVariant
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                GridView {
                    id: appGrid
                    anchors.fill: parent
                    clip: true
                    visible: opacity > 0
                    opacity: panel.hasQuery ? 0 : 1
                    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 84)))
                    cellHeight: 88
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 120

                    property int shown: 0
                    readonly property var allApps: panel.gridApps
                    onAllAppsChanged: { appGrid.shown = 0; chunkTimer.restart(); }
                    Component.onCompleted: chunkTimer.restart()
                    model: appGrid.allApps.slice(0, appGrid.shown)

                    Timer {
                        id: chunkTimer
                        interval: 16
                        repeat: true
                        onTriggered: {
                            appGrid.shown = Math.min(appGrid.shown + 24, appGrid.allApps.length);
                            if (appGrid.shown >= appGrid.allApps.length)
                                chunkTimer.stop();
                        }
                    }

                    ScrollBar.vertical: StyledScrollBar {}

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            const cols = Math.max(1, Math.round(appGrid.width / appGrid.cellWidth));
                            if (appGrid.currentIndex < cols) {
                                searchInput.forceActiveFocus();
                                event.accepted = true;
                            }
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            appGrid.currentItem?.modelData?.execute();
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace || (event.text && event.text.length > 0)) {
                            searchInput.forceActiveFocus();
                            if (event.key === Qt.Key_Backspace)
                                searchInput.text = searchInput.text.slice(0, -1);
                            else if (event.text)
                                searchInput.text += event.text;
                            event.accepted = true;
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    delegate: AppTile {
                        id: tileWrap
                        required property var modelData
                        appEntry: tileWrap.modelData
                        width: appGrid.cellWidth
                        height: appGrid.cellHeight
                        highlighted: appGrid.activeFocus && tileWrap.GridView.isCurrentItem

                        onActivated: {
                            tileWrap.modelData.execute();
                            panel.requestClose();
                        }
                        onRightClicked: (entry, sceneX, sceneY) => panel.rightClicked(entry, sceneX, sceneY)
                    }
                }

                GlyphGrid {
                    id: glyphGrid
                    anchors.fill: parent
                    visible: opacity > 0
                    opacity: panel.glyphMode ? 1 : 0
                    entries: panel.glyphList
                    listMode: LauncherSearch.glyphListMode(LauncherSearch.query, null)

                    onChosen: glyph => {
                        Quickshell.clipboardText = glyph;
                        panel.requestClose();
                    }
                    onDismissRequested: panel.requestClose()
                    onTopEdgeReached: searchInput.forceActiveFocus()
                    onBackspaceRequested: {
                        searchInput.forceActiveFocus();
                        searchInput.text = searchInput.text.slice(0, -1);
                    }
                    onTextTyped: text => {
                        searchInput.forceActiveFocus();
                        searchInput.text += text;
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                ListView {
                    id: resultsList
                    anchors.fill: parent
                    visible: opacity > 0
                    opacity: panel.hasQuery && !panel.glyphMode ? 1 : 0
                    clip: true
                    spacing: 2
                    highlightMoveDuration: 100
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: StyledScrollBar {}

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    model: ScriptModel {
                        id: resultModel
                        objectProp: "key"
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            resultModel.values = LauncherSearch.results.slice(0, 50);
                            resultsList.currentIndex = 0;
                        }
                    }

                    delegate: SearchItem {
                        required property var modelData
                        width: resultsList.width
                        entry: modelData
                        query: LauncherSearch.query
                        onRightClicked: (entry, mouseX, mouseY) => panel.rightClicked(entry, mouseX, mouseY)
                    }

                    KeyNavigation.up: searchInput

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const it = resultsList.itemAtIndex(resultsList.currentIndex);
                            if (it && it.clicked) it.clicked();
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace ||
                            (event.text && event.text.length > 0)) {
                            searchInput.forceActiveFocus();
                            if (event.key === Qt.Key_Backspace)
                                searchInput.text = searchInput.text.slice(0, -1);
                            else if (event.text)
                                searchInput.text += event.text;
                            event.accepted = true;
                        }
                    }

                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 4

            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "settings"
                onClicked: {
                    GlobalStates.settingsOpen = true;
                    panel.requestClose();
                }
            }
            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "refresh"
                onClicked: Quickshell.reload(true)
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "lock"
                onClicked: {
                    panel.requestClose();
                    Session.lock();
                }
            }
            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "bedtime"
                onClicked: {
                    panel.requestClose();
                    Session.suspend();
                }
            }
            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "logout"
                onClicked: {
                    panel.requestClose();
                    Session.logout();
                }
            }
            ActionButton {
                size: 36
                iconSize: 20
                flat: true
                icon: "power_settings_new"
                danger: true
                onClicked: {
                    panel.requestClose();
                    GlobalStates.sessionOpen = true;
                }
            }
        }
    }

}
