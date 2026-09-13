pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * A snippet, in its own panel.
 *
 * Monospaced, on a surface of its own, and it does **not** take part in the block
 * shortcuts: inside code, `# ` is a comment, `- ` is a flag and `---` is a separator, and
 * a paragraph that converted itself while somebody pasted a diff would be unusable.
 * Enter inserts a newline here rather than splitting the block, for the same reason.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    implicitHeight: Math.ceil((panel.height + 16) / NotesMetrics.paperLineHeight) * NotesMetrics.paperLineHeight

    Rectangle {
        id: panel
        x: NotesMetrics.readingPadding
        y: Math.round((root.implicitHeight - height) / 2)
        width: Math.max(160, Math.min(NotesMetrics.readingWidth,
            root.width - NotesMetrics.readingPadding * 2))
        height: content.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerLowest
        // Nothing draws past the slab. Code does not wrap, so a long command has to be
        // clipped and scrolled rather than painted across the page.
        clip: true

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // The language, typed rather than picked from a list: the list is long,
                // people already know the word, and a wrong guess is one keystroke to fix.
                StyledTextInput {
                    id: languageField
                    Layout.preferredWidth: 110
                    text: root.block ? root.block.language : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    onEditingFinished: root.editor.apply(
                        [{ op: "update", id: root.block.id, patch: { language: languageField.text } }], false)
                }

                StyledText {
                    text: Translation.tr("language")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    visible: languageField.text.length === 0
                }

                Item {
                    Layout.fillWidth: true
                }

                NotesIconButton {
                    symbol: "content_copy"
                    size: 32
                    iconSize: 16
                    tooltipText: Translation.tr("Copy the snippet")
                    onTriggered: Quickshell.execDetached(["wl-copy", "--", codeText.text])
                }

                NotesIconButton {
                    symbol: "delete"
                    size: 32
                    iconSize: 16
                    tooltipText: Translation.tr("Remove this block")
                    onTriggered: root.editor.removeBlock(root.block.id)
                }
            }

            /**
             * The code, and room to move along it.
             *
             * Lines are not wrapped — a wrapped shell command is a lie about where its
             * newlines are — so the long ones have to go somewhere. They go sideways,
             * inside this, and the caret drags the view along with it.
             */
            Flickable {
                id: codeScroll
                Layout.fillWidth: true
                Layout.preferredHeight: codeText.implicitHeight
                contentWidth: Math.max(width, codeText.implicitWidth)
                contentHeight: codeText.implicitHeight
                clip: true
                interactive: contentWidth > width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: codeText
                width: Math.max(codeScroll.width, implicitWidth)
                text: root.block ? root.block.text : ""
                wrapMode: TextEdit.NoWrap

                onCursorRectangleChanged: {
                    const caret = codeText.cursorRectangle;
                    if (caret.x < codeScroll.contentX)
                        codeScroll.contentX = Math.max(0, caret.x - 12);
                    else if (caret.x + 24 > codeScroll.contentX + codeScroll.width)
                        codeScroll.contentX = caret.x + 24 - codeScroll.width;
                }
                selectByMouse: true
                textFormat: TextEdit.PlainText
                renderType: Text.NativeRendering
                color: Appearance.colors.colOnLayer0
                font {
                    family: Appearance.font.family.monospace
                    pixelSize: Appearance.font.pixelSize.small
                }
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer

                onActiveFocusChanged: {
                    if (activeFocus) {
                        root.editor.activeBlockId = root.block.id;
                        root.editor.activeTextEdit = codeText;
                    } else {
                        if (root.editor && root.editor.activeTextEdit === codeText)
                            root.editor.activeTextEdit = null;
                        root.commit();
                    }
                }

                onTextChanged: saveDebounce.restart()

                Keys.onPressed: event => {
                    // Backspace out of an empty snippet returns to a paragraph, which is
                    // the only way out of a block that swallows Enter.
                    if (event.key === Qt.Key_Backspace && codeText.length === 0) {
                        root.editor.setType(root.block.id, "text", {});
                        event.accepted = true;
                    }
                }
            }
            }
        }
    }

    function commit(): void {
        if (!root.block || !root.editor || codeText.text === root.block.text)
            return;
        root.editor.commitText(root.block.id, codeText.text);
    }

    Timer {
        id: saveDebounce
        interval: 400
        onTriggered: root.commit()
    }
}
