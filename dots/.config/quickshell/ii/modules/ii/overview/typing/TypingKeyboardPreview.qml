pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * A keyboard drawn under the words, showing which key comes next and flashing
 * the one that was just pressed.
 *
 * Two boards live here. The default one is a flat three-row picture of a
 * layout the user picked, the way Monkeytype presents it. The other is the
 * keyboard actually on the desk, read from its own firmware by VialKeyboard —
 * split, staggered and rotated as it really is, with its layers labelled.
 *
 * It is a hint surface. The layer chips are the only thing here that can be
 * clicked, and they take no keyboard focus, so the test never loses the
 * keystrokes it exists to measure.
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
    /** Room the board may take before it is scaled down. 0 means unlimited. */
    property real maxWidth: 0

    readonly property bool vialMode: root.layoutId === TypingKeyboardLayouts.liveLayoutId
    readonly property var rows: TypingKeyboardLayouts.rowsFor(root.layoutId)
    readonly property real rowHeight: root.keySize + root.keySpacing

    /**
     * Pixels per key unit for the real board.
     *
     * A split keyboard is far wider than the three rows it replaces — the Corne
     * is 16 units across — so the unit shrinks to whatever the panel can give
     * it rather than pushing the board off the sides.
     */
    readonly property real vialUnit: {
        const natural = root.keySize + root.keySpacing;
        if (root.maxWidth <= 0 || VialKeyboard.unitWidth <= 0)
            return natural;
        return Math.min(natural, root.maxWidth / VialKeyboard.unitWidth);
    }

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

    implicitWidth: root.vialMode ? vialLoader.implicitWidth : classicLoader.implicitWidth
    implicitHeight: root.vialMode ? vialLoader.implicitHeight : classicLoader.implicitHeight

    // Reading the keyboard is a round trip to the hardware, so it waits until
    // there is a surface that would show it.
    onVialModeChanged: if (root.vialMode) VialKeyboard.ensureLoaded()
    Component.onCompleted: if (root.vialMode) VialKeyboard.ensureLoaded()

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

    /** Shared so both boards light up, and fade, in exactly the same way. */
    component PreviewKey: KeyboardKey {
        id: previewKey
        property bool isNext: false
        property bool isPressed: false

        // KeyboardKey draws its raised edge as an outer rectangle behind the
        // face. With no edge to draw, the two rounded rectangles are the same
        // size and their antialiased corners fringe against each other — so
        // the one behind must not paint at all.
        borderWidth: 0
        extraBottomBorderWidth: 0
        borderColor: "transparent"
        borderRadius: Appearance.rounding.verysmall
        pixelSize: Appearance.font.pixelSize.small
        keyColor: previewKey.isPressed ? Appearance.colors.colPrimary
            : (previewKey.isNext ? Appearance.colors.colPrimaryContainer : root.restingKey)
        textColor: previewKey.isPressed ? Appearance.colors.colOnPrimary
            : (previewKey.isNext ? Appearance.colors.colOnPrimaryContainer : root.restingText)

        Behavior on keyColor {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    Loader {
        id: classicLoader
        anchors.centerIn: parent
        active: !root.vialMode
        visible: active
        sourceComponent: classicBoard
    }

    Loader {
        id: vialLoader
        anchors.centerIn: parent
        active: root.vialMode
        visible: active
        sourceComponent: vialBoard
    }

    Component {
        id: classicBoard

        ColumnLayout {
            id: keyRows
            spacing: root.keySpacing

            Repeater {
                model: root.rows

                delegate: RowLayout {
                    required property var modelData
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.keySpacing

                    Repeater {
                        model: parent.modelData

                        delegate: PreviewKey {
                            required property string modelData
                            isNext: root.highlightNext && root.nextChar.length > 0
                                && modelData === root.nextChar
                            isPressed: root.pressedChar.length > 0 && modelData === root.pressedChar
                            key: modelData
                            implicitWidth: root.keySize
                            implicitHeight: root.keySize
                        }
                    }
                }
            }

            PreviewKey {
                Layout.alignment: Qt.AlignHCenter
                isNext: root.highlightNext && root.nextChar === " "
                isPressed: root.pressedChar === " "
                key: TypingKeyboardLayouts.labelFor(root.layoutId)
                pixelSize: Appearance.font.pixelSize.smaller
                implicitWidth: root.keySize * 7
                implicitHeight: root.keySize
            }
        }
    }

    Component {
        id: vialBoard

        ColumnLayout {
            spacing: root.keySpacing * 2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: !VialKeyboard.ready
                text: VialKeyboard.loading ? Translation.tr("Reading the keyboard…")
                    : Translation.tr("No Vial keyboard is readable. Plug it in, or pick another layout.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.restingText
            }

            Item {
                id: board
                Layout.alignment: Qt.AlignHCenter
                visible: VialKeyboard.ready
                implicitWidth: VialKeyboard.unitWidth * root.vialUnit
                implicitHeight: VialKeyboard.unitHeight * root.vialUnit

                Repeater {
                    model: VialKeyboard.ready ? VialKeyboard.keys : []

                    delegate: PreviewKey {
                        id: vialKey
                        required property int index
                        required property var modelData

                        readonly property var entry: VialKeyboard.activeLabels[vialKey.index] ?? null
                        readonly property string keyChar: vialKey.entry?.char ?? ""

                        isNext: root.highlightNext && root.nextChar.length > 0
                            && vialKey.keyChar === root.nextChar
                        isPressed: root.pressedChar.length > 0 && vialKey.keyChar === root.pressedChar
                        key: vialKey.entry?.label ?? ""

                        x: vialKey.modelData.x * root.vialUnit
                        y: vialKey.modelData.y * root.vialUnit
                        width: vialKey.modelData.w * root.vialUnit - root.keySpacing
                        height: vialKey.modelData.h * root.vialUnit - root.keySpacing

                        // These caps are the size the hardware says, not the
                        // size of what is written on them, so the label is
                        // fitted to the cap. Guessing from the label's length
                        // was not enough: "RShift" still hung over the edge.
                        fitText: true
                        horizontalPadding: 3
                        verticalPadding: 2
                        pixelSize: Appearance.font.pixelSize.small
                        // A key the layer does not define falls through to the
                        // one below, which is what will fire — shown, but faded,
                        // so it never reads as belonging to this layer.
                        opacity: vialKey.entry?.inherited ? 0.45 : 1

                        // KLE turns a thumb cluster by an angle about a point
                        // out on the board, not about the key's own centre.
                        transform: Rotation {
                            angle: vialKey.modelData.r
                            origin.x: (vialKey.modelData.rx - vialKey.modelData.x) * root.vialUnit
                            origin.y: (vialKey.modelData.ry - vialKey.modelData.y) * root.vialUnit
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: VialKeyboard.ready && VialKeyboard.layerCount > 1
                spacing: root.keySpacing

                Repeater {
                    model: VialKeyboard.ready ? VialKeyboard.layerCount : 0

                    delegate: Rectangle {
                        id: chip
                        required property int index
                        readonly property bool selected: VialKeyboard.activeLayer === chip.index

                        implicitWidth: 30
                        implicitHeight: 22
                        radius: Appearance.rounding.full
                        color: chip.selected ? Appearance.colors.colPrimary
                            : (chipArea.containsMouse ? Appearance.colors.colLayer1Hover : root.restingKey)

                        StyledText {
                            anchors.centerIn: parent
                            text: `L${chip.index}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: chip.selected ? Appearance.colors.colOnPrimary : root.restingText
                        }

                        // Deliberately a bare MouseArea: anything focusable here
                        // would take keystrokes away from the test itself.
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: VialKeyboard.setLayer(chip.index)
                        }

                        Behavior on color {
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
    }
}
