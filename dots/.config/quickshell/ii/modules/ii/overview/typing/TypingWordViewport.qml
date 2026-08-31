pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The typing stage: a fixed window of wrapped target words with a caret.
 *
 * Line breaks are computed once per target (and per resize) instead of being
 * left to a Flow, so the viewport can render only the handful of lines around
 * the caret no matter how long the test is, and so a line never reflows under
 * the reader mid-word. Scrolling moves the whole block by exact line heights.
 */
Item {
    id: root

    required property var engine
    property real fontSize: Config.options.search.typingTest.fontSize
    property int visibleLines: Config.options.search.typingTest.visibleLines
    property string caretStyle: Config.options.search.typingTest.caretStyle
    property bool blindMode: Config.options.search.typingTest.blindMode
    property bool highlightCurrentWord: Config.options.search.typingTest.highlightCurrentWord
    property bool smoothMotion: Config.options.search.typingTest.smoothCaret

    readonly property real lineHeight: Math.round(root.fontSize * 1.62)
    readonly property real charWidth: Math.max(1, sizingMetrics.advanceWidth)
    readonly property var targetWords: root.engine?.targetWords ?? []
    readonly property int currentWordIndex: root.engine?.currentWordIndex ?? 0
    readonly property string typedCurrentWord: root.wordInput(root.currentWordIndex)

    /** [{ start, end }] word ranges, one per rendered line. */
    property var lines: []
    /** Word index → line index. */
    property var wordLine: []
    readonly property int currentLine: root.wordLine[root.currentWordIndex] ?? 0
    /** Keep the caret on the second line so there is always context above it. */
    readonly property int topLine: Math.max(0, Math.min(root.currentLine - 1,
        Math.max(0, root.lines.length - root.visibleLines)))

    // Half a line past the readable window, so the next row is visibly there
    // and the fade has something to dissolve rather than cutting a line in two.
    implicitHeight: Math.round(root.lineHeight * (root.visibleLines + 0.55))

    onTargetWordsChanged: root.rebuildLines()
    onWidthChanged: root.rebuildLines()
    onCharWidthChanged: root.rebuildLines()
    Component.onCompleted: root.rebuildLines()

    function wordInput(index: int): string {
        return String(root.engine?.inputText ?? "").split(" ")[index] ?? "";
    }

    /**
     * Greedy wrap by column count. Monospace makes a character budget exact,
     * and for fallback glyphs of another width it stays close enough that the
     * clipped viewport never shows a broken line.
     */
    function rebuildLines() {
        const words = root.targetWords;
        const columns = Math.max(8, Math.floor(root.width / root.charWidth));
        const lines = [];
        const wordLine = [];
        let start = 0;
        let used = 0;
        for (let index = 0; index < words.length; index++) {
            const length = Array.from(words[index]).length;
            const cost = used === 0 ? length : length + 1;
            if (used > 0 && used + cost > columns) {
                lines.push({ start: start, end: index });
                start = index;
                used = length;
            } else {
                used += cost;
            }
            wordLine[index] = lines.length;
        }
        if (words.length > start)
            lines.push({ start: start, end: words.length });
        root.lines = lines;
        root.wordLine = wordLine;
    }

    function charColor(target: string, typed: string, index: int): color {
        const typedCharacters = Array.from(typed);
        if (index >= typedCharacters.length)
            return Appearance.colors.colSubtext;
        if (root.blindMode)
            return Appearance.colors.colOnSurface;
        return typedCharacters[index] === Array.from(target)[index]
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colError;
    }

    TextMetrics {
        id: sizingMetrics
        text: "0"
        font.family: Appearance.font.family.monospace
        font.pixelSize: root.fontSize
        font.weight: Font.Medium
    }

    // The caret's horizontal position is measured, not assumed: a fallback
    // glyph for an accented or Cyrillic letter can be wider than the monospace
    // cell it replaces.
    TextMetrics {
        id: caretMetrics
        readonly property var line: root.lines[root.currentLine] ?? { start: 0, end: 0 }
        text: {
            const words = root.targetWords;
            let prefix = "";
            for (let index = caretMetrics.line.start; index < root.currentWordIndex && index < words.length; index++)
                prefix += String(words[index]) + " ";
            return prefix + root.typedCurrentWord;
        }
        font.family: Appearance.font.family.monospace
        font.pixelSize: root.fontSize
        font.weight: Font.Medium
    }

    Flickable {
        id: stage
        anchors.fill: parent
        clip: true
        interactive: false
        contentWidth: width
        contentHeight: Math.max(height, root.lines.length * root.lineHeight)
        contentY: root.topLine * root.lineHeight

        Behavior on contentY {
            enabled: root.smoothMotion
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Repeater {
            // One delegate per visible line plus one above and below, so a
            // 120-second test never renders more than a few dozen words.
            model: {
                const window = [];
                const first = Math.max(0, root.topLine - 1);
                const last = Math.min(root.lines.length, root.topLine + root.visibleLines + 1);
                for (let index = first; index < last; index++)
                    window.push(index);
                return window;
            }

            delegate: Item {
                id: lineItem
                required property int modelData
                readonly property var range: root.lines[lineItem.modelData] ?? { start: 0, end: 0 }

                y: lineItem.modelData * root.lineHeight
                width: stage.width
                height: root.lineHeight

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.charWidth
                    layoutDirection: root.engine?.languagePack?.rightToLeft ? Qt.RightToLeft : Qt.LeftToRight

                    Repeater {
                        model: Math.max(0, lineItem.range.end - lineItem.range.start)

                        delegate: Row {
                            id: wordItem
                            required property int index
                            readonly property int wordIndex: lineItem.range.start + wordItem.index
                            readonly property string word: String(root.targetWords[wordItem.wordIndex] ?? "")
                            readonly property string typed: root.wordInput(wordItem.wordIndex)
                            readonly property bool isCurrent: wordItem.wordIndex === root.currentWordIndex
                            readonly property string extras: Array.from(wordItem.typed).slice(Array.from(wordItem.word).length).join("")

                            spacing: 0
                            opacity: (!root.highlightCurrentWord || wordItem.isCurrent) ? 1 : 0.55

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            Repeater {
                                model: Array.from(wordItem.word)

                                delegate: StyledText {
                                    id: charText
                                    required property string modelData
                                    required property int index
                                    text: charText.modelData
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: root.fontSize
                                    font.weight: Font.Medium
                                    color: root.charColor(wordItem.word, wordItem.typed, charText.index)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Appearance.animation.elementMoveFast.type
                                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: wordItem.extras.length > 0
                                text: wordItem.extras
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: root.fontSize
                                font.weight: Font.Medium
                                color: root.blindMode ? Appearance.colors.colOnSurface : Appearance.colors.colError
                                opacity: root.blindMode ? 1 : 0.75
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: caret
            visible: root.caretStyle !== "off"
                && (root.engine?.state === "ready" || root.engine?.state === "running")
            width: root.caretStyle === "line" ? Math.max(2, Math.round(root.fontSize / 12)) : root.charWidth
            height: root.caretStyle === "underline" ? Math.max(2, Math.round(root.fontSize / 11)) : Math.round(root.fontSize * 1.18)
            x: caretMetrics.advanceWidth
            y: root.currentLine * root.lineHeight
                + (root.caretStyle === "underline"
                    ? Math.round((root.lineHeight + root.fontSize) / 2)
                    : Math.round((root.lineHeight - height) / 2))

            Behavior on x {
                enabled: root.smoothMotion
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            Behavior on y {
                enabled: root.smoothMotion
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.unsharpen
                color: Appearance.colors.colPrimary
                opacity: root.caretStyle === "block" ? 0.32 : 1
            }
        }
    }

    // The half line poking past the window goes out of focus and then out of
    // sight, instead of being sliced in half by the edge of the viewport.
    TypingStageFade {
        target: stage
        fadeSize: root.lineHeight * 0.95
        blurEdges: true
    }
}
