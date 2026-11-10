import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UtilityFiles.js" as UtilityFiles

/**
 * Files in a panel as a grid of cards: the picture, the name and its age.
 * A click opens the file, a press that travels drags it out to any app.
 * `removable` adds a remove button on hover (the shelf).
 */
GridLayout {
    id: grid

    property var files: []          // [{ path, name, modified }]
    property int columnsWanted: 3
    property bool showAge: true
    property bool removable: false
    property bool imagesOnly: false
    signal removeRequested(string path)
    signal dragged(string path)

    readonly property date now: DateTime.clock.date

    columns: grid.columnsWanted
    columnSpacing: 6
    rowSpacing: 6

    Repeater {
        model: grid.files
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property string path: card.modelData.path ?? String(card.modelData)
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: thumbBox.height + (grid.imagesOnly ? 16 : 52)
            radius: ClockStyle.radiusNormal
            color: cardHover.hovered ? ClockStyle.colFieldHover : ClockStyle.colField

            HoverHandler {
                id: cardHover
            }

            FileThumb {
                id: thumbBox
                x: 8
                y: 8
                width: card.width - 16
                height: grid.imagesOnly ? Math.round(width * 0.62) : width * 0.72
                path: card.path
                radius: ClockStyle.radiusSmall
            }

            ColumnLayout {
                visible: !grid.imagesOnly
                anchors {
                    left: parent.left
                    right: parent.right
                    top: thumbBox.bottom
                    margins: 8
                    topMargin: 6
                }
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData.name ?? UtilityFiles.baseName(card.path)
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: grid.showAge && (card.modelData.modified ?? 0) > 0
                    text: UtilityFiles.age(card.modelData.modified ?? 0, grid.now.getTime(), s => Translation.tr(s))
                    color: ClockStyle.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
            }

            FileDragArea {
                anchors.fill: parent
                paths: [card.path]
                dragIcon: UtilityFiles.isImage(card.path) ? "image-x-generic" : "text-x-generic"
                onClicked: Quickshell.execDetached(["xdg-open", card.path])
                onDragFinished: grid.dragged(card.path)
            }

            ClockCardAction {
                visible: grid.removable && cardHover.hovered
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                implicitWidth: 28
                implicitHeight: 28
                symbol: "close"
                tip: Translation.tr("Remove")
                colContent: ClockStyle.colOnSurface
                onClicked: grid.removeRequested(card.path)
            }
        }
    }
}
