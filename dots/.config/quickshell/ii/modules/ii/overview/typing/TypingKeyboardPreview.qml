pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A flat keyboard drawn under the words, showing which key comes next and
 * flashing the one that was just pressed. It is a hint surface, not a control:
 * nothing here is clickable, so it never competes for the panel's focus.
 */
Item {
    id: root

    property string layoutId: Config.options.search.typingTest.keyboard.layout
    property bool highlightNext: Config.options.search.typingTest.keyboard.highlightNextKey
    /** The character the test expects next, lowercased by the caller. */
    property string nextChar: ""
    property string pressedChar: ""
    property real keySize: 32
    property real keySpacing: 5

    readonly property var rows: TypingKeyboardLayouts.rowsFor(root.layoutId)
    readonly property real rowHeight: root.keySize + root.keySpacing

    /**
     * A tint of the foreground, not a surface token.
     *
     * `colSurfaceContainerHigh` and friends are solved overlays: they are the
     * colour you paint *over an opaque* `m3surfaceContainer` to land on the
     * target tone. The launcher's own background is transparentized, so over it
     * the solved colour composites against the wallpaper instead and clamps to
     * a flat grey that belongs to no theme. A fixed low alpha of the on-surface
     * colour composites correctly over anything behind the panel.
     */
    readonly property color restingKey: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
    readonly property color restingText: Appearance.colors.colOnSurfaceVariant

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    /** Clears the flash so a held key does not stay lit after the keystroke. */
    Timer {
        id: flashTimer
        interval: 120
        onTriggered: root.pressedChar = ""
    }

    function flash(character: string) {
        root.pressedChar = String(character ?? "").toLowerCase();
        flashTimer.restart();
    }

    ColumnLayout {
        id: keyRows
        anchors.centerIn: parent
        spacing: root.keySpacing

        Repeater {
            model: root.rows

            delegate: RowLayout {
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                spacing: root.keySpacing

                Repeater {
                    model: parent.modelData

                    delegate: KeyboardKey {
                        id: keyCap
                        required property string modelData
                        readonly property bool isNext: root.highlightNext && root.nextChar.length > 0
                            && keyCap.modelData === root.nextChar
                        readonly property bool isPressed: root.pressedChar.length > 0
                            && keyCap.modelData === root.pressedChar

                        key: keyCap.modelData
                        // KeyboardKey draws its raised edge as an outer rectangle
                        // behind the face. With no edge to draw, the two rounded
                        // rectangles are the same size and their antialiased
                        // corners fringe against each other — so the one behind
                        // must not paint at all.
                        borderWidth: 0
                        extraBottomBorderWidth: 0
                        borderColor: "transparent"
                        borderRadius: Appearance.rounding.verysmall
                        pixelSize: Appearance.font.pixelSize.small
                        implicitWidth: root.keySize
                        implicitHeight: root.keySize
                        keyColor: keyCap.isPressed ? Appearance.colors.colPrimary
                            : (keyCap.isNext ? Appearance.colors.colPrimaryContainer : root.restingKey)
                        textColor: keyCap.isPressed ? Appearance.colors.colOnPrimary
                            : (keyCap.isNext ? Appearance.colors.colOnPrimaryContainer : root.restingText)

                        Behavior on keyColor {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }
                }
            }
        }

        KeyboardKey {
            id: spaceKey
            readonly property bool isNext: root.highlightNext && root.nextChar === " "
            readonly property bool isPressed: root.pressedChar === " "

            Layout.alignment: Qt.AlignHCenter
            key: TypingKeyboardLayouts.labelFor(root.layoutId)
            borderWidth: 0
            extraBottomBorderWidth: 0
            borderColor: "transparent"
            borderRadius: Appearance.rounding.verysmall
            pixelSize: Appearance.font.pixelSize.smaller
            implicitWidth: root.keySize * 7
            implicitHeight: root.keySize
            keyColor: spaceKey.isPressed ? Appearance.colors.colPrimary
                : (spaceKey.isNext ? Appearance.colors.colPrimaryContainer : root.restingKey)
            textColor: spaceKey.isPressed ? Appearance.colors.colOnPrimary
                : (spaceKey.isNext ? Appearance.colors.colOnPrimaryContainer : root.restingText)

            Behavior on keyColor {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }
}
