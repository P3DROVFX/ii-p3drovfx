import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/** The shelf's files: take one by dragging it, or all of them from the strip on top. */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var items: panel.tile?.items ?? []
    // What the grid lists: the phone's recents, then the shelf's own files.
    readonly property var entries: FileShelf.entries
    readonly property bool removeAfterDrag: Config.options?.dock?.utilities?.shelf?.removeAfterDrag ?? false

    spacing: 8

    // Drag everything at once.
    Rectangle {
        Layout.fillWidth: true
        visible: panel.items.length > 1
        implicitHeight: 52
        radius: ClockStyle.radiusLarge
        color: allDrag.containsMouse ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryContainer
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: "drag_pan"
                iconSize: 20
                color: ClockStyle.colOnPrimaryContainer
            }
            StyledText {
                text: Translation.tr("Drag all %1 items").arg(panel.items.length)
                color: ClockStyle.colOnPrimaryContainer
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
            }
        }
        FileDragArea {
            id: allDrag
            anchors.fill: parent
            paths: panel.items
            onDragFinished: if (panel.removeAfterDrag) panel.tile?.clear()
        }
    }

    Component.onCompleted: FileShelf.watchPhone(true)
    Component.onDestruction: FileShelf.watchPhone(false)

    FileGrid {
        Layout.fillWidth: true
        visible: panel.entries.length > 0
        files: panel.entries.map(path => ({ path: path, name: FileShelf.name(path), modified: 0 }))
        showAge: false
        removable: true
        onRemoveRequested: path => panel.tile?.remove(path)
        onDragged: path => {
            if (panel.removeAfterDrag)
                panel.tile?.remove(path);
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.entries.length === 0
        implicitHeight: 96
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "shelves"
                iconSize: 20
                padding: 8
                shape: MaterialShape.Shape.Cookie7Sided
                color: ClockStyle.colSecondaryContainer
                colSymbol: ClockStyle.colOnSecondaryContainer
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Drop files on the shelf to keep them here")
                color: ClockStyle.colOnSurfaceVariant
                font.pixelSize: ClockStyle.textSmall
            }
        }
    }

    ClockButton {
        Layout.fillWidth: true
        visible: panel.items.length > 0
        symbol: "clear_all"
        label: Translation.tr("Clear shelf")
        danger: true
        onClicked: panel.tile?.clear()
    }
}
