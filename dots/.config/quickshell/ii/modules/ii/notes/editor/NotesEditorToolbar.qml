import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * The formatting bar, floating at the foot of the page.
 *
 * Contextual rather than complete: it shows what the block under the caret can become, and
 * the buttons reflect what it already is. A fixed bar of thirty controls, most of them
 * inert for the block you are in, is a bar people learn to ignore.
 */
Rectangle {
    id: root

    property var editor: null
    readonly property var block: root.editor ? root.editor.activeBlock : null
    readonly property string blockType: root.block ? root.block.type : ""
    readonly property string listStyle: root.block && root.block.style ? root.block.style : ""

    visible: root.block !== null
    implicitWidth: layout.implicitWidth + 16
    implicitHeight: 52
    radius: NotesMetrics.pillRadius(root.implicitHeight)
    color: Appearance.m3colors.m3surfaceContainerHighest

    function setType(type, props) {
        if (!root.block)
            return;
        root.editor.setType(root.block.id, type, props ?? {});
    }

    /// Clicking the type a block already is puts it back to a paragraph, so every button
    /// is its own undo and nothing is a one-way door.
    function toggleType(type, props, matches) {
        if (matches)
            root.setType("text", {});
        else
            root.setType(type, props);
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 2

        NotesIconButton {
            symbol: "format_h1"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Heading 1")
            colIcon: root.blockType === "heading" && root.block.level === 1
                ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("heading", { level: 1 },
                root.blockType === "heading" && root.block.level === 1)
        }

        NotesIconButton {
            symbol: "format_h2"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Heading 2")
            colIcon: root.blockType === "heading" && root.block.level === 2
                ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("heading", { level: 2 },
                root.blockType === "heading" && root.block.level === 2)
        }

        // Air between the groups, not a rule: the app separates things with space and
        // shape everywhere else, and these hairlines were the only lines in it.
        Item {
            Layout.preferredWidth: 12
        }

        NotesIconButton {
            symbol: "format_list_bulleted"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Bulleted list")
            colIcon: root.listStyle === "bullet" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("list", { style: "bullet" }, root.listStyle === "bullet")
        }

        NotesIconButton {
            symbol: "format_list_numbered"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Numbered list")
            colIcon: root.listStyle === "number" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("list", { style: "number" }, root.listStyle === "number")
        }

        NotesIconButton {
            symbol: "checklist"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Checklist")
            colIcon: root.listStyle === "checkbox" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("list", { style: "checkbox" }, root.listStyle === "checkbox")
        }

        NotesIconButton {
            symbol: "format_quote"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Quote")
            colIcon: root.blockType === "quote" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("quote", {}, root.blockType === "quote")
        }

        NotesIconButton {
            symbol: "info"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Callout")
            colIcon: root.blockType === "callout" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("callout", { tone: "info" }, root.blockType === "callout")
        }

        // Air between the groups, not a rule: the app separates things with space and
        // shape everywhere else, and these hairlines were the only lines in it.
        Item {
            Layout.preferredWidth: 12
        }

        NotesIconButton {
            symbol: "format_indent_decrease"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Outdent")
            enabled: root.block !== null && (root.block.indent ?? 0) > 0
            onTriggered: root.editor.indent(root.block.id, -1)
        }

        NotesIconButton {
            symbol: "format_indent_increase"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Indent")
            enabled: root.block !== null && root.block.indent !== undefined
            onTriggered: root.editor.indent(root.block.id, 1)
        }

        NotesIconButton {
            symbol: "horizontal_rule"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Divider")
            onTriggered: root.setType("divider", {})
        }

        // Air between the groups, not a rule: the app separates things with space and
        // shape everywhere else, and these hairlines were the only lines in it.
        Item {
            Layout.preferredWidth: 12
        }

        // Inserting, rather than converting: a snippet and a table are not what the
        // paragraph you are in should *become*, they are things that go after it.
        NotesIconButton {
            symbol: "code"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Code snippet")
            colIcon: root.blockType === "code" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleType("code", {}, root.blockType === "code")
        }

        NotesIconButton {
            symbol: "table"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Table")
            onTriggered: root.editor.insertBlock("table", { columns: 3, rows: [["", "", ""], ["", "", ""]] })
        }

        NotesIconButton {
            symbol: "image"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Insert a picture")
            onTriggered: root.editor.pickImage()
        }

        NotesIconButton {
            symbol: "attach_file"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Attach a file")
            onTriggered: root.editor.pickFile()
        }

        NotesIconButton {
            symbol: "draw"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Draw")
            onTriggered: root.editor.insertInk()
        }

        // Air between the groups, not a rule: the app separates things with space and
        // shape everywhere else, and these hairlines were the only lines in it.
        Item {
            Layout.preferredWidth: 12
        }

        NotesIconButton {
            symbol: "undo"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Undo")
            enabled: root.editor !== null && root.editor.undoStack.length > 0
            onTriggered: root.editor.undo()
        }

        NotesIconButton {
            symbol: "redo"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Redo")
            enabled: root.editor !== null && root.editor.redoStack.length > 0
            onTriggered: root.editor.redo()
        }

        Item {
            visible: Number(Config.options?.policies?.ai ?? 1) !== 0
            Layout.preferredWidth: 12
        }

        NotesIconButton {
            visible: Number(Config.options?.policies?.ai ?? 1) !== 0
            symbol: "auto_awesome"
            size: 42
            iconSize: 21
            tooltipText: Translation.tr("Ask the AI")
            colIcon: Appearance.colors.colTertiary
            onTriggered: {
                if (root.editor)
                    root.editor.openAiMenu();
            }
        }

        NotesIconButton {
            symbol: DictationService.recording ? "mic" : "mic_none"
            size: 42
            iconSize: 21
            tooltipText: DictationService.recording ? Translation.tr("Stop dictation") : Translation.tr("Voice dictation")
            colIcon: DictationService.recording ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
            onTriggered: DictationService.toggle()
        }
    }
}
