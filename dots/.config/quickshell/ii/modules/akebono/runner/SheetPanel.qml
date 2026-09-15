pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.lunae.overview
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: panel

    signal requestClose()
    signal rightClicked(entry: var, sceneX: real, sceneY: real)

    readonly property bool hasQuery: LauncherSearch.query !== ""
    readonly property bool glyphMode: panel.hasQuery && LauncherSearch.isGlyphQuery(LauncherSearch.query)
    readonly property var glyphList: panel.glyphMode ? LauncherSearch.glyphEntries(LauncherSearch.query, null) : []
    readonly property bool browsingAll: LauncherSearch.activeCategory === ""
    readonly property var pinnedEntries: LauncherSearch.pinnedEntries
    readonly property bool pinnedShown: !panel.hasQuery && panel.browsingAll && panel.pinnedEntries.length > 0

    readonly property int searchHeight: Math.round(Appearance.font.pixelSize.larger * 2.8)
    readonly property int chipHeight: Math.round(Appearance.font.pixelSize.normal * 2.3)

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
        LauncherSearch.activeCategory = "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Squircle {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.searchHeight
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            smoothing: AkebonoAppearance.squircleSmoothing

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 14
                spacing: 10

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSubtext
                }

                ToolbarTextField {
                    id: searchInput
                    Layout.fillWidth: true
                    colBackground: "transparent"
                    font.pixelSize: Appearance.font.pixelSize.large
                    placeholderText: Translation.tr("Search apps, math, emojis...")

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
                            if (panel.glyphMode) {
                                glyphGrid.currentIndex = 0;
                                glyphGrid.forceActiveFocus();
                            } else if (panel.hasQuery) {
                                resultsList.currentIndex = 0;
                                resultsList.forceActiveFocus();
                            } else {
                                appGrid.currentIndex = 0;
                                appGrid.forceActiveFocus();
                            }
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        ListView {
            id: chipRow
            Layout.fillWidth: true
            Layout.preferredHeight: panel.chipHeight
            visible: !panel.hasQuery
            orientation: Qt.Horizontal
            spacing: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: LauncherSearch.sections.filter(section => section.key !== LauncherSearch.pinnedSection)

            delegate: Squircle {
                id: chip
                required property var modelData
                readonly property bool selected: LauncherSearch.categoryForSection(chip.modelData.key) === LauncherSearch.activeCategory

                implicitWidth: chipLabel.implicitWidth + 30
                height: chipRow.height
                radius: height / 2
                smoothing: AkebonoAppearance.squircleSmoothing
                color: chip.selected ? Appearance.colors.colPrimaryContainer
                    : chipMouse.containsMouse ? Appearance.colors.colLayer2Hover
                    : Appearance.colors.colLayer1

                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: chip.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LauncherSearch.activeCategory = LauncherSearch.categoryForSection(chip.modelData.key)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property real cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 84)))
            readonly property int cellHeight: 92
            readonly property int iconSize: 44

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: !panel.hasQuery

                ListView {
                    id: pinnedRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: body.cellHeight
                    visible: panel.pinnedShown
                    orientation: Qt.Horizontal
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: panel.pinnedEntries

                    delegate: AppTile {
                        id: pinnedTile
                        required property var modelData
                        appEntry: pinnedTile.modelData
                        width: body.cellWidth
                        height: body.cellHeight
                        iconSize: body.iconSize

                        onActivated: {
                            pinnedTile.modelData.execute();
                            panel.requestClose();
                        }
                        onRightClicked: (entry, sceneX, sceneY) => panel.rightClicked(entry, sceneX, sceneY)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    visible: panel.pinnedShown
                    color: Appearance.colors.colOutlineVariant
                }

                GridView {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: body.cellWidth
                    cellHeight: body.cellHeight
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 120
                    model: LauncherSearch.entriesForSection(LauncherSearch.activeCategory || LauncherSearch.allSection)

                    ScrollBar.vertical: StyledScrollBar {}

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && appGrid.currentIndex < Math.max(1, Math.round(appGrid.width / appGrid.cellWidth))) {
                            searchInput.forceActiveFocus();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            appGrid.currentItem?.appEntry?.execute();
                            panel.requestClose();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backspace) {
                            searchInput.forceActiveFocus();
                            searchInput.text = searchInput.text.slice(0, -1);
                            event.accepted = true;
                        } else if (event.text && event.text.length > 0) {
                            searchInput.forceActiveFocus();
                            searchInput.text += event.text;
                            event.accepted = true;
                        }
                    }

                    delegate: AppTile {
                        id: gridTile
                        required property var modelData
                        appEntry: gridTile.modelData
                        width: appGrid.cellWidth
                        height: appGrid.cellHeight
                        iconSize: body.iconSize
                        highlighted: appGrid.activeFocus && gridTile.GridView.isCurrentItem

                        onActivated: {
                            gridTile.modelData.execute();
                            panel.requestClose();
                        }
                        onRightClicked: (entry, sceneX, sceneY) => panel.rightClicked(entry, sceneX, sceneY)
                    }
                }
            }

            GlyphGrid {
                id: glyphGrid
                anchors.fill: parent
                visible: panel.glyphMode
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
            }

            ListView {
                id: resultsList
                anchors.fill: parent
                visible: panel.hasQuery && !panel.glyphMode
                clip: true
                spacing: 2
                highlightMoveDuration: 100
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: StyledScrollBar {}

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

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panel.requestClose();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        const item = resultsList.itemAtIndex(resultsList.currentIndex);
                        if (item && item.clicked)
                            item.clicked();
                        panel.requestClose();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        searchInput.forceActiveFocus();
                        searchInput.text = searchInput.text.slice(0, -1);
                        event.accepted = true;
                    } else if (event.text && event.text.length > 0) {
                        searchInput.forceActiveFocus();
                        searchInput.text += event.text;
                        event.accepted = true;
                    }
                }

                KeyNavigation.up: searchInput

                delegate: SearchItem {
                    id: resultRow
                    required property var modelData
                    width: resultsList.width
                    entry: resultRow.modelData
                    query: LauncherSearch.query
                    onRightClicked: (entry, sceneX, sceneY) => panel.rightClicked(entry, sceneX, sceneY)
                }

                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
