import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Pins on top, then the latest history. A click copies the entry again; on
 * hover a row offers pin/unpin and delete. Images show as thumbnails.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var pinned: Cliphist.pinnedEntries ?? []
    readonly property var history: (Cliphist.entries ?? []).filter(entry => !Cliphist.isPinned(entry)).slice(0, 8)
    property string copiedEntry: ""

    spacing: 3

    Timer {
        id: copiedTimer
        interval: 1400
        onTriggered: panel.copiedEntry = ""
    }

    component EntryRow: RippleButton {
        id: row
        property string entry
        property bool isPinned: false
        property bool first: false
        readonly property bool image: Cliphist.entryIsImage(row.entry)
        readonly property bool copied: panel.copiedEntry === row.entry
        Layout.fillWidth: true
        implicitHeight: 52
        buttonRadius: row.first ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
        colBackground: row.copied ? ClockStyle.colPrimaryContainer
            : row.isPinned ? ClockStyle.colTertiaryContainer : ClockStyle.colField
        colBackgroundHover: row.isPinned ? ClockStyle.colTertiaryContainerHover : ClockStyle.colFieldHover
        colRipple: ClockStyle.colSurfaceActive
        onClicked: {
            Cliphist.copy(row.entry);
            panel.copiedEntry = row.entry;
            copiedTimer.restart();
        }
        HoverHandler {
            id: rowHover
        }
        readonly property color colContent: row.copied ? ClockStyle.colOnPrimaryContainer
            : row.isPinned ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurface

        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 10

                MaterialSymbol {
                    visible: !row.image || row.copied
                    text: row.copied ? "check" : (panel.tile?.symbolOf(row.entry) ?? "notes")
                    iconSize: 18
                    fill: 1
                    color: row.colContent
                }
                // An image: its picture fitted in a small frame, then its size.
                Item {
                    visible: row.image && !row.copied
                    implicitWidth: 56
                    implicitHeight: 36
                    Loader {
                        anchors.centerIn: parent
                        active: row.image
                        sourceComponent: CliphistImage {
                            entry: row.entry
                            maxWidth: 56
                            maxHeight: 36
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.tile?.labelOf(row.entry) ?? ""
                    color: row.colContent
                    font.pixelSize: ClockStyle.textNormal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                ClockCardAction {
                    visible: rowHover.hovered || row.isPinned
                    implicitWidth: 30
                    implicitHeight: 30
                    symbol: "keep"
                    tip: row.isPinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                    colContent: row.colContent
                    onClicked: row.isPinned ? Cliphist.unpin(row.entry) : Cliphist.pin(row.entry)
                }
                ClockCardAction {
                    visible: rowHover.hovered
                    implicitWidth: 30
                    implicitHeight: 30
                    symbol: "delete"
                    tip: Translation.tr("Delete")
                    danger: true
                    onClicked: Cliphist.deleteEntry(row.entry)
                }
            }
        }
    }

    StyledText {
        Layout.leftMargin: 4
        visible: panel.pinned.length > 0
        text: Translation.tr("Pinned")
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }
    Repeater {
        model: panel.pinned
        delegate: EntryRow {
            required property string modelData
            required property int index
            entry: modelData
            isPinned: true
            first: index === 0
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: panel.pinned.length > 0 ? 6 : 0
        text: Translation.tr("Recent")
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }
    Repeater {
        model: panel.history
        delegate: EntryRow {
            required property string modelData
            required property int index
            entry: modelData
            first: index === 0
        }
    }
    Rectangle {
        Layout.fillWidth: true
        visible: panel.history.length === 0
        implicitHeight: 64
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("Nothing copied yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    ClockButton {
        Layout.fillWidth: true
        Layout.topMargin: 6
        symbol: "content_paste_search"
        label: Translation.tr("Open full history")
        onClicked: {
            panel.host?.closePanel();
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "search", "clipboardToggle"]);
        }
    }
}
