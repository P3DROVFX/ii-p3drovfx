pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The pen tray: colour, thickness, eraser, and what happens to the drawing.
 *
 * One row, wide targets, no menus. Everything here is reached mid-thought with a pen in
 * the other hand, and a control that needs a second tap to reveal itself is a control
 * that gets used once. The thickness slider is the only thing that is not a button, and
 * it is the width of three of them so it can be dragged without aiming.
 */
Rectangle {
    id: root

    property var palette: []
    property string currentColor: ""
    property real strokeWidth: 4
    property bool eraser: false
    property bool usePressure: true
    property bool pressureAvailable: false
    property bool canUndo: false
    property bool canSave: false
    property string statusText: ""

    signal colorPicked(string color)
    signal widthPicked(real width)
    signal eraserToggled()
    signal pressureToggled()
    signal undoRequested()
    signal clearRequested()
    signal saveRequested()
    signal keepRequested()
    signal closeRequested()

    implicitWidth: layout.implicitWidth + 28
    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer0

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 10

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

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.colorPicked(swatch.modelData)
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
        TabletLiveDrawToolButton {
            symbol: "ink_eraser"
            active: root.eraser
            tooltipText: Translation.tr("Eraser")
            onTriggered: root.eraserToggled()
        }

        TabletLiveDrawToolButton {
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

        TabletLiveDrawToolButton {
            symbol: "undo"
            enabled: root.canUndo
            tooltipText: Translation.tr("Undo stroke")
            onTriggered: root.undoRequested()
        }

        TabletLiveDrawToolButton {
            symbol: "delete"
            enabled: root.canUndo
            tooltipText: Translation.tr("Rub the whole sheet out")
            onTriggered: root.clearRequested()
        }

        // ── What happens to it ──────────────────────────────────────────────
        TabletLiveDrawToolButton {
            symbol: "note_add"
            enabled: root.canSave
            emphasised: true
            tooltipText: Translation.tr("Save to Notes")
            onTriggered: root.saveRequested()
        }

        TabletLiveDrawToolButton {
            symbol: "picture_in_picture"
            enabled: root.canSave
            tooltipText: Translation.tr("Leave it on this workspace")
            onTriggered: root.keepRequested()
        }

        TabletLiveDrawToolButton {
            symbol: "close"
            tooltipText: Translation.tr("Put the pen down")
            onTriggered: root.closeRequested()
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
