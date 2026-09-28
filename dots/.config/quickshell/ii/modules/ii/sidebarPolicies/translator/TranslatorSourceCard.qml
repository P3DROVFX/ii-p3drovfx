import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * What the user writes: a pane with the text in the rounded title face, sized from its
 * length the way a messages composer shrinks as the text grows, and the card's small
 * actions tinted with its own content colour.
 */
Rectangle {
    id: root

    property alias textArea: inputTextArea
    property int textSize: Appearance.font.pixelSize.huge
    property string sourceName: ""

    signal swapRequested()
    signal inputChanged()

    readonly property color colContent: ClockStyle.colOnSurface
    readonly property bool hasText: inputTextArea.text.length > 0

    // One step further up than the Clock's panes: on the sidebar's layer-0 slab a
    // layer-1 pane barely separates from the background.
    color: ClockStyle.colSurfaceHigh
    radius: ClockStyle.radiusCard

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.cardPadding - 4
        }
        spacing: ClockStyle.gapSmall

        // ── Header ──────────────────────────────────────────────────────
        // Mirrors the translation pane's, so side by side the two tops line up.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: ClockStyle.gapTiny
            spacing: ClockStyle.gapSmall + 2

            MaterialShapeWrappedMaterialSymbol {
                text: "edit_note"
                iconSize: 20
                padding: 10
                // Focus morphs the shape (clover → sunny) instead of turning it.
                shape: inputTextArea.activeFocus ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Clover4Leaf
                color: ClockStyle.colSecondaryContainer
                colSymbol: ClockStyle.colOnSecondaryContainer
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Original")
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: root.colContent
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.sourceName
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }
        }

        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: inputTextArea.implicitHeight

            StyledTextArea {
                id: inputTextArea
                width: flick.width
                // Fill the pane so a click anywhere in it lands in the text.
                height: Math.max(implicitHeight, flick.height)
                padding: 0
                placeholderText: activeFocus ? Translation.tr("Translate text") : Translation.tr("Type / to translate")
                placeholderTextColor: ColorUtils.applyAlpha(root.colContent, 0.45)
                wrapMode: TextEdit.Wrap
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: root.textSize
                color: root.colContent
                background: null
                onTextChanged: root.inputChanged()

                // Keep the caret in view while typing past the pane.
                onCursorRectangleChanged: {
                    const r = inputTextArea.cursorRectangle;
                    if (r.y < flick.contentY)
                        flick.contentY = r.y;
                    else if (r.y + r.height > flick.contentY + flick.height)
                        flick.contentY = r.y + r.height - flick.height;
                }

                // The TextEdit consumes Enter (inserting a newline) before the event
                // can bubble to the tab, so the swap shortcut is caught here first.
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => {
                    if ((event.modifiers & Qt.ControlModifier) !== 0
                            && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                        root.swapRequested();
                        event.accepted = true;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: root.hasText ? Translation.tr("%1 characters").arg(inputTextArea.text.length) : Translation.tr("Ctrl+Enter swaps languages")
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.DemiBold
                color: ClockStyle.colSubtext
                elide: Text.ElideRight
            }

            ClockCardAction {
                symbol: "close"
                tip: Translation.tr("Clear")
                colContent: root.colContent
                visible: root.hasText
                onClicked: {
                    inputTextArea.text = "";
                    inputTextArea.forceActiveFocus();
                }
            }

            ClockCardAction {
                symbol: "content_paste"
                tip: Translation.tr("Paste")
                colContent: root.colContent
                onClicked: {
                    inputTextArea.text = Quickshell.clipboardText;
                    inputTextArea.cursorPosition = inputTextArea.length;
                    inputTextArea.forceActiveFocus();
                }
            }
        }
    }
}
