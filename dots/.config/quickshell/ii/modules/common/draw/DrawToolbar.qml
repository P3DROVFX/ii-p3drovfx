pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

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
    /// Host items before the shared controls — a grip, where the host lets the tray move.
    property alias leadingContent: leading.data

    /**
     * Folded down to the pen, undo and the way back out.
     *
     * For drawing over something that is being recorded or shared: the full tray is as
     * wide as a dock and sits in every frame of the video, while the folded one is three
     * buttons. Off unless the host offers it (`collapsible`).
     */
    property bool collapsible: false
    property bool collapsed: false
    signal collapseToggled()

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
    // Opaque tones, not the layer tokens: those are translucent under a transparency
    // theme and lean on the compositor blurring what is behind them, and this tray floats
    // over arbitrary applications on a layer nothing blurs. Translucent, it was a ghost
    // over a white page.
    color: Appearance.m3colors.m3surfaceContainer

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 10

        RowLayout {
            id: leading
            spacing: 0
            visible: leading.children.length > 0
        }

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
            visible: root.showDrawToggle && !root.collapsed
            Layout.preferredWidth: 1
            Layout.preferredHeight: Appearance.sizes.minimumTouchTarget * 0.5
            color: Appearance.colors.colOnSurface
            opacity: 0.15
        }

        // ── Ink ─────────────────────────────────────────────────────────────
        Repeater {
            model: root.collapsed ? [] : root.palette

            delegate: Item {
                id: swatch
                required property string modelData
                readonly property bool current: !root.eraser && root.currentColor === swatch.modelData

                Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                Layout.preferredHeight: Appearance.sizes.minimumTouchTarget

                // The chosen ink is the rounded square carrying a check; the rest are
                // circles. The shape is the selection — no ring, no border.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (swatch.current ? 0.8 : (swatchTap.pressed ? 0.62 : 0.7))
                    height: width
                    radius: swatch.current ? Appearance.rounding.small : width / 2
                    color: swatch.modelData

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: swatch.current
                        text: "check"
                        iconSize: Appearance.font.pixelSize.large
                        color: ColorUtils.getContrastingTextColor(swatch.modelData)
                    }
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                // A TapHandler rather than a MouseArea, and here it takes every device:
                // a swatch has no MouseArea to double with, and a handler is the only
                // thing that sees a tablet event at all. See DrawToolButton.
                TapHandler {
                    id: swatchTap
                    acceptedDevices: PointerDevice.AllDevices
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.colorPicked(swatch.modelData)
                }
            }
        }

        // ── Thickness ───────────────────────────────────────────────────────
        StyledSlider {
            id: widthSlider
            visible: !root.collapsed
            Layout.preferredWidth: Appearance.sizes.minimumTouchTarget * 3
            from: 1
            to: 24
            value: root.strokeWidth
            // The toolbar is the lowest surface; the default track colour sits on the
            // same tone as it in some schemes and the unfilled part vanished.
            trackColor: Appearance.m3colors.m3surfaceContainerHighest
            usePercentTooltip: false
            onMoved: root.widthPicked(widthSlider.value)
        }

        Rectangle {
            // What the slider means, in the ink it will be drawn with.
            visible: !root.collapsed
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
            visible: !root.collapsed
            symbol: "ink_eraser"
            active: root.eraser
            tooltipText: Translation.tr("Eraser")
            onTriggered: root.eraserToggled()
        }

        DrawToolButton {
            visible: root.showPressure && !root.collapsed
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
            visible: !root.collapsed
            symbol: "delete"
            enabled: root.canUndo
            tooltipText: Translation.tr("Rub the whole sheet out")
            onTriggered: root.clearRequested()
        }

        // ── What the host does with the drawing ─────────────────────────────
        RowLayout {
            id: trailing
            visible: !root.collapsed
            spacing: 10
        }

        DrawToolButton {
            visible: root.collapsible
            symbol: root.collapsed ? "expand_content" : "collapse_content"
            tooltipText: root.collapsed
                ? Translation.tr("Show every tool")
                : Translation.tr("Fold the toolbar down to the pen")
            onTriggered: root.collapseToggled()
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
        color: Appearance.colors.colOnSurface
        style: Text.Outline
        styleColor: Appearance.m3colors.m3surfaceContainer
    }
}
