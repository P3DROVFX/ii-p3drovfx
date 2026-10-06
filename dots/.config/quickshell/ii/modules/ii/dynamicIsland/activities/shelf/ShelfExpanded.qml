pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.dock.utilities
import qs.modules.ii.clock.components
import "../../../dock/utilities/UtilityFiles.js" as UtilityFiles

/**
 * Drop shelf expanded inside the dynamic island auxiliary bubble.
 * Uses the exact backend, components, and design from the dock drop shelf widget.
 */
Item {
    id: root

    // Host contract properties expected by AuxiliaryBubble
    property bool inBubbleCard: false
    property bool isExpanded: false

    readonly property var items: Persistent.ready ? Array.from(Persistent.states.dockUtilities.shelf ?? []) : []
    readonly property int count: root.items.length

    // Adapter for ShelfPanel host contract
    readonly property var tile: QtObject {
        readonly property var items: root.items
        readonly property int count: root.count
        readonly property string newest: root.count > 0 ? root.items[root.count - 1] : ""
        function dropFiles(urls) {
            Persistent.states.dockUtilities.shelf = UtilityFiles.dedupe(root.items.concat(urls));
        }
        function remove(path) {
            Persistent.states.dockUtilities.shelf = root.items.filter(item => item !== path);
        }
        function clear() {
            Persistent.states.dockUtilities.shelf = [];
        }
        function exportPaths() {
            return root.items;
        }
    }

    readonly property real preferredExpandedWidth: 380
    readonly property real preferredExpandedHeight: Math.min(480, contentColumn.implicitHeight + 24)

    // Keep bubble open during active dragging
    readonly property bool holdsOpen: GlobalStates.fileDragActive

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            if (drop.hasUrls) {
                root.tile.dropFiles(drop.urls);
                drop.accept(Qt.CopyAction);
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ── Header Plate (Dock Popup Style) ──────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colSurfaceContainerHighest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "shelves"
                        iconSize: 22
                        color: Appearance.colors.colTertiary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Shelf")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.count === 0
                            ? Translation.tr("Drop files here")
                            : (root.count === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(root.count))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    visible: root.count > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    colRipple: Appearance.colors.colSurfaceContainerHighest
                    onClicked: root.tile.clear()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "clear_all"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // ── ShelfPanel Body (Same as dock popup) ─────────────────────────────
        Flickable {
            Layout.fillWidth: true
            implicitHeight: Math.min(380, shelfPanel.implicitHeight)
            contentHeight: shelfPanel.implicitHeight
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ShelfPanel {
                id: shelfPanel
                width: parent.width
                host: ({ tile: root.tile })
            }
        }
    }
}
