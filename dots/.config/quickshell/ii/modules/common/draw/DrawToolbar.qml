pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The pen tray: colour, thickness, eraser, and whatever the host adds to the end.
 *
 * One row, wide targets, no menus. Everything here is reached mid-thought with a pen in
 * the other hand, and a control that needs a second tap to reveal itself is a control
 * that gets used once.
 *
 * The ink controls are shared; what happens to the drawing is not. A sheet floating over
 * a workspace can be saved to Notes, screenshotted or put away; a sketch inside a note is
 * simply finished or abandoned. So the host appends its own buttons through the default
 * slot rather than this growing a flag per host.
 */
Rectangle {
    id: root

    /**
     * Host buttons, appended after the shared controls.
     *
     * A named property rather than the default one: a `default property alias` also
     * captures the objects this file declares in its own body, which would put the
     * toolbar's own layout inside the slot it is trying to fill. Explicit at the call
     * site is worth more than the saved word anyway — these buttons are the host's half
     * of the toolbar, not incidental children.
     */
    property alias trailingContent: trailing.data

    property var palette: []
    property string currentColor: ""
    property real strokeWidth: 4
    property bool eraser: false
    property bool usePressure: true
    property bool pressureAvailable: false
    property bool canUndo: false
    property string statusText: ""

    /**
     * Whether the pen is down.
     *
     * The toolbar's own mode switch, and the reason it exists: without it the only way
     * out of drawing was a button that also put the toolbar away, so a sheet you had
     * stopped drawing on could never be drawn on again. Hosts that are always in drawing
     * mode — a sketch inside a note has nothing else to be — leave `showDrawToggle` off.
     */
    property bool drawing: true
    property bool showDrawToggle: false
    property bool showPressure: true

    signal colorPicked(string color)
    signal widthPicked(real width)
    signal drawToggled()
    signal eraserToggled()
    signal pressureToggled()
    signal undoRequested()
    signal clearRequested()

    implicitWidth: layout.implicitWidth + 28
    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer0

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 10

        // ── Mode ────────────────────────────────────────────────────────────
        DrawToolButton {
            visible: root.showDrawToggle
            symbol: "stylus_note"
            active: root.drawing
            tooltipText: root.drawing
                ? Translation.tr("Drawing — tap to let taps through again")
                : Translation.tr("Not drawing — tap to pick the pen back up")
            onTriggered: root.drawToggled()
        }

        Rectangle {
            visible: root.showDrawToggle
            Layout.preferredWidth: 1
            Layout.preferredHeight: Appearance.sizes.minimumTouchTarget * 0.5
            color: Appearance.colors.colOnLayer0
            opacity: 0.15
        }

        // ── Ink ─────────────────────────────────────────────────────────────
        Repeater {
            model: root.palette

            delegate: Rectangle {
                id: swatch
                required property string modelData
                readonly property bool current: !root.eraser && root.currentColor === swatch.modelData

                Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                radius: Appearance.rounding.full
                // The selected swatch is the one carrying a ring of the surface colour
                // rather than a border: this shell does not draw borders, and a gap
                // reads as selection just as well.
                color: Appearance.colors.colLayer1

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (swatch.current ? 0.62 : 0.78)
                    height: width
                    radius: Appearance.rounding.full
                    color: swatch.modelData

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                // A TapHandler rather than a MouseArea, for the same reason the tool
                // buttons have one: a MouseArea never sees a tablet event, and whether
                // one is synthesised into a mouse event depends on nobody else having
                // accepted it first. See DrawToolButton.
                TapHandler {
                    acceptedDevices: PointerDevice.AllDevices
                    onTapped: root.colorPicked(swatch.modelData)
                }
            }
        }

        // ── Thickness ───────────────────────────────────────────────────────
        StyledSlider {
            id: widthSlider
            Layout.preferredWidth: Appearance.sizes.minimumTouchTarget * 3
            from: 1
            to: 24
            value: root.strokeWidth
            onMoved: root.widthPicked(widthSlider.value)
        }

        Rectangle {
            // What the slider means, in the ink it will be drawn with.
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: Appearance.rounding.full
            color: "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: Math.max(2, Math.min(24, root.strokeWidth))
                height: width
                radius: Appearance.rounding.full
                color: root.eraser ? Appearance.colors.colSubtext : root.currentColor
            }
        }

        // ── Tools ───────────────────────────────────────────────────────────
        DrawToolButton {
            symbol: "ink_eraser"
            active: root.eraser
            tooltipText: Translation.tr("Eraser")
            onTriggered: root.eraserToggled()
        }

        DrawToolButton {
            visible: root.showPressure
            symbol: "stylus"
            active: root.usePressure
            // Greyed rather than hidden without a pen: the switch says the feature is
            // there and waiting for hardware, instead of the toolbar quietly changing
            // shape depending on what is plugged in.
            enabled: root.pressureAvailable
            tooltipText: root.pressureAvailable
                ? Translation.tr("Pen pressure")
                : Translation.tr("No pen detected — pressure needs a stylus")
            onTriggered: root.pressureToggled()
        }

        DrawToolButton {
            symbol: "undo"
            enabled: root.canUndo
            tooltipText: Translation.tr("Undo stroke")
            onTriggered: root.undoRequested()
        }

        DrawToolButton {
            symbol: "delete"
            enabled: root.canUndo
            tooltipText: Translation.tr("Rub the whole sheet out")
            onTriggered: root.clearRequested()
        }

        // ── What the host does with the drawing ─────────────────────────────
        RowLayout {
            id: trailing
            spacing: 10
        }
    }

    // Confirmation of a save, and the reason a save failed. Sits under the tray rather
    // than in it: the tray is a fixed set of controls and a line that comes and goes
    // inside it would move every one of them.
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 8
        visible: root.statusText.length > 0
        text: root.statusText
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer0
        style: Text.Outline
        styleColor: Appearance.colors.colLayer0
    }
}
