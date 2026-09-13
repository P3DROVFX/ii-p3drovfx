pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A drawing in a note.
 *
 * Shows the picture, because that is what the store keeps for every surface to display,
 * and offers the way back into it. Editing happens on the ink sheet rather than here: a
 * drawing needs the whole page, a tray of tools and room to zoom, none of which fits in a
 * block sitting between two paragraphs.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property string assetPath: root.block && root.editor
        ? NotesService.assetPath(root.editor.noteId, root.block.asset)
        : ""
    /// Whether the vector strokes were kept. One made before that, or filed in from the
    /// tablet's live draw, has only the picture — it can still be drawn on, just not undone.
    readonly property bool hasStrokes: root.block && String(root.block.strokes ?? "").length > 0

    readonly property real available: Math.max(160,
        Math.min(NotesMetrics.readingWidth, root.width - NotesMetrics.readingPadding * 2))

    implicitHeight: Math.ceil((frame.height + 22) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight

    Rectangle {
        id: frame
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        width: root.available
        height: root.block && root.block.aspect > 0
            ? width / root.block.aspect
            : (image.implicitWidth > 0 ? width * (image.implicitHeight / image.implicitWidth) : 160)
        radius: Appearance.rounding.normal
        // No fill. The drawing is ink on transparency, so it belongs on the note's own
        // page — a slab behind it put every sketch in a black box.
        color: "transparent"
        clip: true

        Image {
            id: image
            anchors.fill: parent
            anchors.margins: 1
            source: root.assetPath.length > 0 ? `file://${root.assetPath}` : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            sourceSize.width: Math.max(480, Math.round(root.available * 2))
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onDoubleClicked: root.editor.editInk(root.block.id)
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            implicitWidth: actions.implicitWidth + 8
            implicitHeight: 38
            radius: NotesMetrics.pillRadius(implicitHeight)
            color: Appearance.m3colors.m3surfaceContainerHighest
            opacity: hover.containsMouse ? 0.95 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: actions
                anchors.centerIn: parent
                spacing: 0

                NotesIconButton {
                    symbol: "draw"
                    size: 34
                    iconSize: 17
                    tooltipText: root.hasStrokes
                        ? Translation.tr("Keep drawing")
                        : Translation.tr("Draw on this")
                    onTriggered: root.editor.editInk(root.block.id)
                }

                NotesIconButton {
                    symbol: "delete"
                    size: 34
                    iconSize: 17
                    tooltipText: Translation.tr("Remove from the note")
                    onTriggered: root.editor.removeBlock(root.block.id)
                }
            }
        }
    }
}
