pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A file attachment card in a note.
 *
 * Shows the filename, formatted size, mime icon or thumbnail, and location.
 * Allows opening with the default system application, copying to note assets,
 * or relocating if the original file was moved.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property string filePath: root.block ? String(root.block.path ?? "") : ""
    readonly property string fileName: {
        if (!root.filePath)
            return "";
        const parts = root.filePath.split("/");
        return parts[parts.length - 1] || root.filePath;
    }

    readonly property string extension: {
        const dot = root.fileName.lastIndexOf(".");
        return dot > 0 ? root.fileName.slice(dot + 1).toLowerCase() : "";
    }

    readonly property string fileIcon: {
        const ext = root.extension;
        if (["pdf"].includes(ext))
            return "picture_as_pdf";
        if (["mp4", "mkv", "webm", "avi", "mov"].includes(ext))
            return "movie";
        if (["mp3", "ogg", "flac", "wav", "m4a", "opus"].includes(ext))
            return "audio_file";
        if (["zip", "tar", "gz", "7z", "rar", "bz2", "xz"].includes(ext))
            return "folder_zip";
        if (["py", "js", "ts", "qml", "c", "cpp", "rs", "go", "json", "html", "css", "sh"].includes(ext))
            return "code";
        if (["txt", "md", "csv", "doc", "docx", "odt"].includes(ext))
            return "description";
        return "attach_file";
    }

    function formatBytes(bytes): string {
        const n = Number(bytes);
        if (!n || n <= 0)
            return "";
        if (n < 1024)
            return `${n} B`;
        if (n < 1024 * 1024)
            return `${(n / 1024).toFixed(1)} KB`;
        return `${(n / (1024 * 1024)).toFixed(1)} MB`;
    }

    readonly property string sizeText: root.block && root.block.size > 0
        ? root.formatBytes(root.block.size)
        : ""

    implicitHeight: Math.ceil((card.height + 16) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight

    // Probe to check if file exists and get size if size is 0
    Process {
        id: fileProbe
        command: ["bash", "-c", `[ -f "${root.filePath}" ] && stat -c %s "${root.filePath}" || echo "MISSING"`]
        stdout: StdioCollector {
            id: probeOut
            onStreamFinished: {
                const txt = probeOut.text.trim();
                if (txt === "MISSING") {
                    root.fileExists = false;
                } else {
                    root.fileExists = true;
                    const sz = parseInt(txt, 10);
                    if (sz > 0 && root.block && (!root.block.size || root.block.size === 0)) {
                        root.editor.apply([{
                            op: "update",
                            id: root.block.id,
                            patch: { size: sz }
                        }], false);
                    }
                }
            }
        }
    }

    property bool fileExists: true

    Component.onCompleted: {
        if (root.filePath)
            fileProbe.running = true;
    }

    // Relocate file picker
    Process {
        id: relocatePicker
        command: ["bash", "-c",
            `if command -v zenity >/dev/null; then
                 zenity --file-selection --title="Locate file" 2>/dev/null
             elif command -v kdialog >/dev/null; then
                 kdialog --getopenfilename "$HOME" 2>/dev/null
             fi`]
        stdout: StdioCollector {
            id: pickerOut
            onStreamFinished: {
                const path = pickerOut.text.trim();
                if (path && root.editor && root.block) {
                    root.editor.apply([{
                        op: "update",
                        id: root.block.id,
                        patch: { path: path }
                    }], false);
                    fileProbe.running = true;
                }
            }
        }
    }

    function copyToNote(): void {
        if (!root.filePath || !root.editor || !root.block || root.block.copied)
            return;
        NotesService.importAsset(root.editor.noteId, root.filePath);
    }

    Connections {
        target: NotesService
        function onAssetImported(noteId, name) {
            if (root.editor && noteId === root.editor.noteId && root.block && !root.block.copied) {
                const newPath = NotesService.assetPath(noteId, name);
                root.editor.apply([{
                    op: "update",
                    id: root.block.id,
                    patch: { path: newPath, copied: true }
                }], false);
            }
        }
    }

    Rectangle {
        id: card
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        width: Math.max(160, Math.min(NotesMetrics.readingWidth,
            root.width - NotesMetrics.readingPadding * 2))
        height: rowLayout.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerLowest
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Appearance.colors.colOnSurface
            opacity: cardHover.containsMouse ? 0.04 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.fileExists && root.filePath.length > 0)
                    Qt.openUrlExternally("file://" + root.filePath);
            }
        }

        RowLayout {
            id: rowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 12

            // ── File icon box ─────────────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: Appearance.rounding.small
                color: root.fileExists ? Appearance.m3colors.m3surfaceContainerHigh : Appearance.m3colors.m3errorContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.fileExists ? root.fileIcon : "warning"
                    iconSize: 22
                    color: root.fileExists ? Appearance.colors.colPrimary : Appearance.m3colors.m3onErrorContainer
                }
            }

            // ── File Info ─────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.fileName.length > 0 ? root.fileName : Translation.tr("Unknown file")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideMiddle
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: root.fileExists
                            ? (root.sizeText.length > 0 ? root.sizeText : root.filePath)
                            : Translation.tr("File not found")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.fileExists ? Appearance.colors.colSubtext : Appearance.m3colors.m3error
                        elide: Text.ElideMiddle
                    }

                    StyledText {
                        text: "· " + Translation.tr("Saved in note")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                        visible: root.block && root.block.copied === true
                    }
                }
            }

            // ── Actions ───────────────────────────────────────────────────────
            RowLayout {
                spacing: 4

                NotesIconButton {
                    symbol: "folder_open"
                    size: 32
                    iconSize: 18
                    tooltipText: Translation.tr("Locate file")
                    visible: !root.fileExists
                    onTriggered: relocatePicker.running = true
                }

                NotesIconButton {
                    symbol: "save_as"
                    size: 32
                    iconSize: 18
                    tooltipText: Translation.tr("Copy into note assets")
                    visible: root.fileExists && root.block && !root.block.copied
                    onTriggered: root.copyToNote()
                }

                NotesIconButton {
                    symbol: "content_copy"
                    size: 32
                    iconSize: 18
                    tooltipText: Translation.tr("Copy path")
                    onTriggered: {
                        if (root.filePath.length > 0)
                            Quickshell.exec(["wl-copy", root.filePath]);
                    }
                }

                NotesIconButton {
                    symbol: "delete"
                    size: 32
                    iconSize: 18
                    colIcon: Appearance.colors.colSubtext
                    tooltipText: Translation.tr("Remove block")
                    onTriggered: {
                        if (root.editor && root.block)
                            root.editor.removeBlock(root.block.id);
                    }
                }
            }
        }
    }
}
