pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The drawer's inside: a search field over a grid of every installed app.
 *
 * The search field is not only an app filter. Typing also matches the shell's tool panels —
 * clipboard, emoji, translator, the file browser and the rest — and choosing one replaces
 * the grid with that panel, in place, the way Android's drawer search hands you a result
 * surface rather than opening a separate window. Escape backs out one level at a time:
 * tool -> grid -> closed.
 *
 * The tool panels themselves live in the ii family, so this file cannot import them. The
 * host component is injected by the composition root instead, which is the only place
 * allowed to reach across families. With nothing injected the drawer is still a complete
 * app drawer, minus the tools.
 */
Item {
    id: root

    /// Supplied by TabletFamily. See the note above on why this is injected.
    property Component toolHostComponent: null

    property real revealProgress: 1

    signal dismissRequested

    readonly property string query: searchField.text
    property string activeToolId: ""

    // ── Touch metrics ───────────────────────────────────────────────────────
    // Everything is derived from the screen so one layout serves a small tablet and a
    // large scaled display, the same way the shade does it.
    readonly property real outerMargin: Math.max(20, Math.min(56, Math.round(root.width * 0.04)))
    readonly property real searchHeight: Math.max(52, Math.min(68, Math.round(root.height * 0.062)))
    readonly property real tileWidth: Math.max(96, Math.min(148, Math.round(root.width / 8)))
    readonly property real tileHeight: Math.round(root.tileWidth * 1.18)
    readonly property real appIconSize: Math.round(root.tileWidth * 0.52)

    // ── Apps ────────────────────────────────────────────────────────────────
    readonly property var apps: {
        const q = root.query.trim();
        if (q.length === 0)
            return AppSearch.list;
        return AppSearch.fuzzyQuery(q);
    }

    // ── Tools ───────────────────────────────────────────────────────────────
    // Only what the user could actually open: a panel whose module is switched off is not
    // offered, exactly as the launcher does it.
    readonly property var matchingTools: {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0 || !root.toolHostComponent)
            return [];
        return SearchPanelRegistry.enabledPanels.filter(panel => {
            if (String(panel.label).toLowerCase().includes(q))
                return true;
            return (panel.keywords ?? []).some(keyword => String(keyword).toLowerCase().startsWith(q));
        });
    }

    function openTool(toolId) {
        root.activeToolId = toolId;
    }

    function closeTool() {
        root.activeToolId = "";
    }

    /// One step back. Returns false when there is nothing left to back out of, so the
    /// window above can close itself instead.
    function goBack() {
        if (root.activeToolId.length > 0) {
            root.closeTool();
            return true;
        }
        if (searchField.text.length > 0) {
            searchField.text = "";
            return true;
        }
        return false;
    }

    function activateTopResult() {
        if (root.activeToolId.length > 0)
            return;
        if (root.apps.length > 0) {
            root.apps[0].execute();
            root.dismissRequested();
            return;
        }
        if (root.matchingTools.length > 0)
            root.openTool(root.matchingTools[0].id);
    }

    function reset() {
        root.activeToolId = "";
        searchField.text = "";
        appGrid.contentY = 0;
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.outerMargin
        spacing: root.outerMargin * 0.6

        // Search bar. Android puts it at the top of the drawer and it keeps focus while
        // you scroll, so typing at any point filters without a second tap.
        Rectangle {
            id: searchBar
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(720, root.width * 0.6)
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: root.searchHeight
            radius: height / 2
            color: Appearance.colors.colLayer1

            opacity: root.revealProgress
            transform: Translate {
                y: -(1 - root.revealProgress) * root.searchHeight * 0.8
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 12
                spacing: 12

                MaterialSymbol {
                    text: root.activeToolId.length > 0 ? "arrow_back" : "search"
                    iconSize: Math.round(root.searchHeight * 0.42)
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        enabled: root.activeToolId.length > 0
                        onClicked: root.closeTool()
                    }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                    background: null
                    color: Appearance.colors.colOnLayer1
                    placeholderText: Translation.tr("Search apps and tools")
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.searchHeight * 0.30)
                    selectByMouse: true

                    Keys.onEscapePressed: {
                        if (!root.goBack())
                            root.dismissRequested();
                    }

                    // Enter takes the top result, the way Android's drawer search does. Apps
                    // win when there are any: someone typing a name wants that app, not a
                    // tool that happens to share a keyword. A query that matches no app but
                    // does match a tool opens the tool instead of doing nothing.
                    //
                    // onAccepted, not Keys.onReturnPressed: TextField consumes Return itself
                    // and turns it into this signal, so the Keys handler never sees it.
                    onAccepted: root.activateTopResult()
                }

                MaterialSymbol {
                    visible: searchField.text.length > 0
                    text: "close"
                    iconSize: Math.round(root.searchHeight * 0.40)
                    color: Appearance.colors.colOnLayer1

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -12
                        onClicked: searchField.text = ""
                    }
                }
            }
        }

        // Tool suggestions, between the field and the grid, like Android's result chips.
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: root.matchingTools.length > 0 ? toolRow.implicitHeight : 0
            visible: Layout.preferredHeight > 0
            contentWidth: toolRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Behavior on Layout.preferredHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            RowLayout {
                id: toolRow
                spacing: 10

                Repeater {
                    model: root.matchingTools

                    delegate: Rectangle {
                        id: toolChip
                        required property var modelData

                        implicitWidth: chipRow.implicitWidth + 32
                        implicitHeight: Math.max(44, Math.round(root.searchHeight * 0.78))
                        radius: height / 2
                        color: chipArea.pressed ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: toolChip.modelData.icon ?? "wand_stars"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: toolChip.modelData.label ?? toolChip.modelData.id
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            onClicked: root.openTool(toolChip.modelData.id)
                        }
                    }
                }
            }
        }

        // The body is either the app grid or, once a tool is chosen, that tool's panel.
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            // The grid arrives a beat after the search field, so the drawer reads as one
            // surface assembling rather than everything appearing at once.
            readonly property real bodyReveal: Math.max(0, Math.min(1, (root.revealProgress - 0.2) / 0.8))
            opacity: body.bodyReveal
            transform: Translate {
                // `body`, not `parent`: a Transform is not an Item and has no visual parent,
                // so `parent.bodyReveal` was undefined and translated the grid by NaN.
                y: (1 - body.bodyReveal) * 40
            }

            GridView {
                id: appGrid
                anchors.fill: parent
                visible: root.activeToolId.length === 0
                enabled: visible

                cellWidth: root.tileWidth
                cellHeight: root.tileHeight
                model: root.apps
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600

                delegate: Item {
                    id: appCell
                    required property var modelData
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    TabletAppTile {
                        anchors.centerIn: parent
                        width: appGrid.cellWidth - 8
                        height: appGrid.cellHeight - 8
                        entry: appCell.modelData
                        iconSize: root.appIconSize
                        onActivated: {
                            appCell.modelData.execute();
                            root.dismissRequested();
                        }
                    }
                }
            }

            // Outside the GridView: a child of a Flickable joins its scrolling content, so
            // an empty-state placeholder put in there would drift with the view.
            PagePlaceholder {
                anchors.fill: parent
                visible: appGrid.visible
                shown: root.apps.length === 0
                icon: "search_off"
                title: Translation.tr("No apps")
                description: Translation.tr("Nothing matches this search")
                sizeScale: 1.3
                descriptionHorizontalAlignment: Text.AlignHCenter
            }

            Loader {
                id: toolHost
                anchors.fill: parent
                active: root.activeToolId.length > 0 && root.toolHostComponent !== null
                visible: active
                sourceComponent: root.toolHostComponent

                onLoaded: toolHost.syncToPanel()

                function syncToPanel() {
                    if (!toolHost.item)
                        return;
                    toolHost.item.activePanelId = root.activeToolId;
                    toolHost.item.searchQuery = "";
                }

                Connections {
                    target: root
                    function onActiveToolIdChanged() {
                        toolHost.syncToPanel();
                    }
                }
            }
        }
    }
}
