pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A picture in a note.
 *
 * Width is a *fraction* of the reading measure, not a pixel count: a note opened in a
 * narrower window would otherwise show an image cropped or overflowing, and the same note
 * on two monitors would disagree with itself. Dragging the right edge changes the
 * fraction, so the picture keeps its place in the text at any size.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    signal viewRequested(string path)

    readonly property string assetPath: root.block && root.editor
        ? NotesService.assetPath(root.editor.noteId, root.block.asset)
        : ""
    /// Zero means "as wide as it fits", which is what an image dropped in should do.
    /// A width being dragged comes from the editor rather than from the model, so the
    /// picture follows the pointer without the row being rebuilt under it.
    readonly property real widthFraction: {
        const live = root.editor && root.block ? root.editor.liveWidths[root.block.id] : undefined;
        if (live !== undefined)
            return live;
        return root.block && root.block.width > 0 ? root.block.width : 1;
    }

    readonly property real available: Math.max(120,
        Math.min(NotesMetrics.readingWidth, root.width - NotesMetrics.readingPadding * 2))

    /**
     * How wide the picture really is, taken once when it loads.
     *
     * Read as a binding on `image.implicitWidth` it went round in a circle — the frame's
     * width feeds the size the image decodes at, and the decoded size feeds the frame —
     * and Qt reported a binding loop for the width of every image in a note. A plain
     * property, written once on load, cannot loop.
     */
    property real naturalWidth: 0
    property real naturalHeight: 0

    implicitHeight: image.status === Image.Ready ? Math.ceil((frame.height + 22) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight : 0

    // A rounded container that clips, rather than a mask effect on the image: a
    // `MultiEffect` mask needs a texture provider, and a plain rectangle is not one.
    Rectangle {
        id: frame
        color: "transparent"
        radius: Appearance.rounding.normal
        clip: true
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        // Never wider than the picture actually is. A 320px screenshot stretched to the
        // reading measure is a blurred 320px screenshot, and the fraction is there to make
        // a picture *smaller* than the column, not to inflate it.
        width: Math.round(Math.min(root.available * root.widthFraction,
                                   Math.max(120, root.naturalWidth)))
        height: root.naturalWidth > 0 && root.naturalHeight > 0
            ? width * (root.naturalHeight / root.naturalWidth)
            : 0

        Image {
            id: image
            anchors.fill: parent
            source: root.assetPath.length > 0 ? `file://${root.assetPath}` : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            // Decoded at the size it is shown at rather than at whatever produced it.
            sourceSize.width: Math.max(320, Math.round(root.available * 2))

            onStatusChanged: {
                if (image.status !== Image.Ready)
                    return;
                root.naturalWidth = image.implicitWidth;
                root.naturalHeight = image.implicitHeight;
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.viewRequested(root.assetPath)
        }

        // The actions, over the picture and only while the pointer is on it. A row of
        // buttons under every image would be a page of buttons.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            implicitWidth: actions.implicitWidth + 8
            implicitHeight: 38
            radius: NotesMetrics.pillRadius(implicitHeight)
            color: Appearance.m3colors.m3surfaceContainerHighest
            opacity: hover.containsMouse || grip.containsMouse ? 0.95 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: actions
                anchors.centerIn: parent
                spacing: 0

                NotesIconButton {
                    symbol: "open_in_full"
                    size: 34
                    iconSize: 17
                    tooltipText: Translation.tr("View full size")
                    onTriggered: root.viewRequested(root.assetPath)
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

        /**
         * The resize grip.
         *
         * On the right edge, because the picture is anchored to the left margin like the
         * text is: dragging the left edge would move the image rather than resize it.
         */
        MouseArea {
            id: grip
            width: 16
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor

            property real pressFraction: 1
            property real pressX: 0

            onPressed: mouse => {
                grip.pressFraction = root.widthFraction;
                grip.pressX = grip.mapToItem(root, mouse.x, mouse.y).x;
            }

            onPositionChanged: mouse => {
                if (!grip.pressed)
                    return;
                const now = grip.mapToItem(root, mouse.x, mouse.y).x;
                const next = grip.pressFraction + (now - grip.pressX) / root.available;
                // A quarter is the floor: smaller than that and the picture is a thumbnail
                // nobody can read, with no way to grab its edge again.
                root.editor.setImageWidth(root.block.id, Math.max(0.25, Math.min(1, next)));
            }

            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: Math.min(parent.height * 0.4, 48)
                radius: width / 2
                color: Appearance.colors.colOnLayer0
                opacity: grip.containsMouse || grip.pressed ? 0.8 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
