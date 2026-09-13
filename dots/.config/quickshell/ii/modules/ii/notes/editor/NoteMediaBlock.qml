import QtQuick

import qs.services
import qs.modules.common
import qs.modules.ii.notes

/**
 * A block that shows a file: a drawing, a picture.
 *
 * Read-only here. Editing a drawing is the ink surface's job and editing a picture is the
 * image block's, both of which come later — but the note has to *show* what it holds from
 * the moment the editor replaces the reader, or every migrated sketch would open blank.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property string assetPath: root.block && root.editor
        ? NotesService.assetPath(root.editor.noteId, root.block.asset)
        : ""

    implicitHeight: image.status === Image.Ready ? Math.ceil((image.height + 20) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight : 0

    Image {
        id: image
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        readonly property real available: Math.max(80,
            Math.min(NotesMetrics.readingWidth, root.width - NotesMetrics.readingPadding * 2))
        width: Math.min(available, implicitWidth)
        height: implicitWidth > 0 ? width * (implicitHeight / implicitWidth) : 0
        source: root.assetPath.length > 0 ? `file://${root.assetPath}` : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        // Decoded at the size it is shown at rather than at whatever the pen produced.
        sourceSize.width: 1240
    }
}
