import QtQuick

import qs.modules.common

/// Picks the delegate for a block. A Loader rather than a DelegateChooser so the block
/// keeps its identity across a type change — the id survives `setType`, and so should the
/// row the caret is in.
Item {
    id: root

    required property var editor
    required property var block
    required property int blockIndex

    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    /**
     * Clicks that land on the row but not on the text.
     *
     * A row is taller than its line — the rhythm padding above and below, the gutter the
     * bullet sits in, the margin a callout draws around itself — and all of it belongs to
     * the paragraph. The text still takes its own clicks (a `TextEdit` accepts the press,
     * so a tap on the glyphs never reaches this handler) and so do the buttons inside the
     * row; what lands here is every dead pixel that used to do nothing at all.
     */
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: eventPoint => {
            const item = loader.item;
            if (!item || typeof item.placeCaret !== "function")
                return;
            const point = item.mapFromItem(root, eventPoint.position.x, eventPoint.position.y);
            item.placeCaret(point.x, point.y);
        }
    }

    Loader {
        id: loader
        width: parent.width
        sourceComponent: {
            if (root.block.type === "divider")
                return dividerComponent;
            if (root.block.type === "image")
                return imageComponent;
            if (root.block.type === "code")
                return codeComponent;
            if (root.block.type === "table")
                return tableComponent;
            if (root.block.type === "ink")
                return inkComponent;
            if (root.block.type === "linkPreview")
                return linkPreviewComponent;
            if (root.block.type === "fileLink")
                return fileLinkComponent;
            return textComponent;
        }

        onLoaded: {
            item.editor = Qt.binding(() => root.editor);
            item.block = Qt.binding(() => root.block);
            item.blockIndex = Qt.binding(() => root.blockIndex);
        }
    }

    Component {
        id: textComponent
        NoteTextBlock {}
    }

    Component {
        id: dividerComponent
        NoteDividerBlock {}
    }

    Component {
        id: inkComponent
        NoteInkBlock {}
    }

    Component {
        id: imageComponent
        NoteImageBlock {
            onViewRequested: path => root.editor.viewImage(path)
        }
    }

    Component {
        id: codeComponent
        NoteCodeBlock {}
    }

    Component {
        id: tableComponent
        NoteTableBlock {}
    }

    Component {
        id: linkPreviewComponent
        NoteLinkPreviewBlock {}
    }

    Component {
        id: fileLinkComponent
        NoteFileBlock {}
    }
}
