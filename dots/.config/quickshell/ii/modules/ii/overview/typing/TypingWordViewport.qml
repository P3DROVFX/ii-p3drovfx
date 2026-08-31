pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

Item {
    id: root

    property var engine: null
    property var currentWordItem: null
    readonly property var allTargetWords: root.engine?.targetWords ?? []
    readonly property string typedCurrentWord: root.wordInput(root.engine?.currentWordIndex ?? 0)

    readonly property real estimatedLineHeight: Appearance.font.pixelSize.huge * 1.5 + wordFlow.spacing
    readonly property real scrollOffsetY: {
        if (!currentWordItem)
            return 0;
        const lineH = Math.max(1, currentWordItem.height + wordFlow.spacing);
        return Math.max(0, currentWordItem.y - lineH);
    }

    clip: true
    implicitHeight: Math.round(estimatedLineHeight * 3)

    function wordInput(index: int): string {
        return String(root.engine?.inputText ?? "").split(" ")[index] ?? "";
    }

    function charColor(target: string, typed: string, index: int): color {
        const typedCharacters = root.engine?.codePoints(typed) ?? [];
        const targetCharacters = root.engine?.codePoints(target) ?? [];
        if (index >= typedCharacters.length)
            return Appearance.colors.colSubtext;
        return typedCharacters[index] === targetCharacters[index]
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colError;
    }

    Flow {
        id: wordFlow
        width: parent.width
        y: -root.scrollOffsetY
        spacing: Appearance.sizes.elevationMargin / 2
        layoutDirection: root.engine?.languagePack?.rightToLeft ? Qt.RightToLeft : Qt.LeftToRight

        Behavior on y {
            enabled: Config.options.search.typingTest.smoothCaret
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Repeater {
            model: root.allTargetWords

            delegate: Item {
                id: wordItem
                required property string modelData
                required property int index
                readonly property string typed: root.wordInput(wordItem.index)
                readonly property bool isCurrent: wordItem.index === (root.engine?.currentWordIndex ?? -1)
                readonly property var targetChars: Array.from(wordItem.modelData)
                readonly property string extras: Array.from(wordItem.typed).slice(wordItem.targetChars.length).join("")
                implicitWidth: wordRow.implicitWidth
                implicitHeight: wordRow.implicitHeight

                onIsCurrentChanged: {
                    if (isCurrent)
                        root.currentWordItem = wordItem;
                }
                Component.onCompleted: {
                    if (isCurrent)
                        root.currentWordItem = wordItem;
                }

                Row {
                    id: wordRow
                    spacing: 0

                    Repeater {
                        model: wordItem.targetChars

                        delegate: Text {
                            id: charText
                            required property string modelData
                            required property int index
                            text: charText.modelData
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.Medium
                            color: root.charColor(wordItem.modelData, wordItem.typed, charText.index)
                        }
                    }

                    Text {
                        visible: wordItem.extras.length > 0
                        text: wordItem.extras
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colError
                    }
                }
            }
        }
    }

    TextMetrics {
        id: caretMetrics
        text: root.typedCurrentWord
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.huge
        font.weight: Font.Medium
    }

    Rectangle {
        id: caret
        visible: root.engine?.state === "ready" || root.engine?.state === "running"
        width: Math.max(2, Math.round(Appearance.sizes.elevationMargin / 5))
        height: Appearance.font.pixelSize.huge * 1.15
        x: (root.currentWordItem ? (wordFlow.x + root.currentWordItem.x) : 0) + caretMetrics.advanceWidth
        y: (root.currentWordItem ? (wordFlow.y + root.currentWordItem.y) : 0) + (Appearance.font.pixelSize.huge * 0.08)
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary

        Behavior on x {
            enabled: Config.options.search.typingTest.smoothCaret
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on y {
            enabled: Config.options.search.typingTest.smoothCaret
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }
}
