pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The pen tray: what the pen is doing, the ink, the thickness, the edits, and whatever
 * the host adds to the end.
 *
 * A Material 3 Expressive floating toolbar. The groups are told apart by what they are
 * made of rather than by lines between them: the mode is a word set in the title face
 * with its state in small capitals under it, the inks sit on a pill of their own, the
 * thickness is a number in tall condensed digits, and the edits are one connected
 * button group whose inner corners press flat. One row, wide targets, no menus —
 * everything here is reached mid-thought with a pen in the other hand.
 *
 * The ink controls are shared; what happens to the drawing is not. A sheet floating over
 * a workspace can be saved, screenshotted or put away; a sketch inside a note is simply
 * finished or abandoned. So the host appends its own buttons (`trailingContent`).
 */
Rectangle {
    id: root

    /**
     * Host buttons, appended after the shared controls.
     *
     * A named property rather than the default one: a `default property alias` also
     * captures the objects this file declares in its own body, which would put the
     * toolbar's own layout inside the slot it is trying to fill.
     */
    property alias trailingContent: trailing.data
    /// Host items before the shared controls — a grip, where the host lets the tray move.
    property alias leadingContent: leading.data

    property var palette: []
    property string currentColor: ""
    property real strokeWidth: 4
    property bool eraser: false
    property bool usePressure: true
    property bool pressureAvailable: false
    property bool canUndo: false
    property bool canRedo: false
    property bool showRedo: false
    property bool canClear: root.canUndo
    property string statusText: ""

    /**
     * Whether the pen is down.
     *
     * The toolbar's own mode switch: without it the only way out of drawing was a button
     * that also put the toolbar away. Hosts that are always drawing — a sketch inside a
     * note has nothing else to be — leave `showDrawToggle` off.
     */
    property bool drawing: true
    property bool showDrawToggle: false
    property bool showPressure: true

    /// The mode, said in words: a title ("Draw") over its state ("Pen up"). Empty hides it.
    property string title: ""
    property string subtitle: ""

    /**
     * Folded down to the pen, undo and the way back out.
     *
     * For drawing over something that is being recorded or shared: the full tray is as
     * wide as a dock and sits in every frame of the video, while the folded one is a
     * handful of buttons. Off unless the host offers it (`collapsible`).
     */
    property bool collapsible: false
    property bool collapsed: false

    /// The host's settings popup: a button that opens it, lit while it is open.
    property bool showSettings: false
    property bool settingsOpen: false

    /// The way out, last in the row.
    property bool showClose: false

    /// Narrow screens: the words and the thickness digits go first.
    property bool dense: false

    signal colorPicked(string color)
    signal widthPicked(real width)
    signal drawToggled()
    signal eraserToggled()
    signal pressureToggled()
    signal undoRequested()
    signal redoRequested()
    signal clearRequested()
    signal collapseToggled()
    signal settingsToggled()
    signal closeRequested()

    readonly property real padding: 8
    readonly property real target: Appearance.sizes.minimumTouchTarget
    readonly property bool full: !root.collapsed

    implicitWidth: layout.implicitWidth + root.padding * 2 + 6
    implicitHeight: layout.implicitHeight + root.padding * 2
    radius: Appearance.rounding.full
    // Opaque tones, not the layer tokens: those are translucent under a transparency
    // theme and lean on the compositor blurring what is behind them, and this tray floats
    // over arbitrary applications on a layer nothing blurs.
    color: Appearance.m3colors.m3surfaceContainer

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 10

        RowLayout {
            id: leading
            Layout.fillWidth: false
            spacing: 0
            visible: leading.children.length > 0
        }

        // ── Mode ────────────────────────────────────────────────────────────
        // The pen as the largest control, round while up, a rounded square while down:
        // the shape is the state.
        DrawToolButton {
            visible: root.showDrawToggle
            size: root.target + 4
            symbol: root.drawing ? "stylus_note" : "arrow_selector_tool"
            active: root.drawing
            tooltipText: root.drawing
                ? Translation.tr("Drawing — click to let clicks through to the apps")
                : Translation.tr("Clicks go through — click to pick the pen back up")
            shortcut: "Tab"
            onTriggered: root.drawToggled()
        }

        ColumnLayout {
            visible: root.title.length > 0 && root.full && !root.dense
            Layout.fillWidth: false
            Layout.preferredWidth: Math.max(titleText.implicitWidth, stateText.implicitWidth)
            spacing: -2

            StyledText {
                id: titleText
                text: root.title
                color: Appearance.colors.colOnSurface
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
            }

            StyledText {
                id: stateText
                text: root.eraser ? Translation.tr("Eraser") : root.subtitle
                color: root.drawing ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        // ── Ink ─────────────────────────────────────────────────────────────
        // On a pill of their own, one step up the surface ladder.
        Rectangle {
            visible: root.full && root.palette.length > 0
            Layout.fillWidth: false
            implicitWidth: inks.implicitWidth + 8
            implicitHeight: root.target
            radius: Appearance.rounding.full
            color: Appearance.m3colors.m3surfaceContainerHigh

            Row {
                id: inks
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                    model: root.full ? root.palette : []

                    delegate: Item {
                        id: swatch
                        required property string modelData
                        required property int index
                        readonly property bool current: !root.eraser && root.currentColor === swatch.modelData

                        width: root.target - 8
                        height: root.target - 8

                        // The chosen ink is the rounded square carrying a check; the rest
                        // are circles. The shape is the selection — no ring, no border.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * (swatch.current ? 0.86 : (swatchTap.pressed ? 0.6 : (swatchHover.hovered ? 0.76 : 0.68)))
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
                                iconSize: Appearance.font.pixelSize.normal
                                color: ColorUtils.getContrastingTextColor(swatch.modelData)
                            }
                        }

                        HoverHandler {
                            id: swatchHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        // A TapHandler rather than a MouseArea, and here it takes every
                        // device: a handler is the only thing that sees a tablet event.
                        // See DrawToolButton.
                        TapHandler {
                            id: swatchTap
                            acceptedDevices: PointerDevice.AllDevices
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: root.colorPicked(swatch.modelData)
                        }

                        StyledToolTip {
                            requireOverlay: false
                            extraVisibleCondition: swatchHover.hovered
                            text: Translation.tr("Ink %1").arg(swatch.modelData.toUpperCase()) + (swatch.index < 9 ? `  ·  ${swatch.index + 1}` : "")
                        }
                    }
                }
            }
        }

        // ── Thickness ───────────────────────────────────────────────────────
        // The number in tall condensed digits, the slider beside it.
        RowLayout {
            visible: root.full
            Layout.fillWidth: false
            spacing: 6

            StyledSlider {
                id: widthSlider
                Layout.preferredWidth: root.target * 2.4
                from: 1
                to: 24
                stepSize: 1
                focusPolicy: Qt.NoFocus
                value: root.strokeWidth
                // The default track sits on the same tone as this surface in some schemes.
                trackColor: ColorUtils.mix(Appearance.m3colors.m3surfaceContainer, Appearance.m3colors.m3onSurface, 0.82)
                usePercentTooltip: false
                onMoved: root.widthPicked(widthSlider.value)

                StyledToolTip {
                    requireOverlay: false
                    extraVisibleCondition: widthSlider.hovered && !widthSlider.pressed
                    text: Translation.tr("Thickness") + "  ·  [ ]"
                }
            }

            Row {
                visible: !root.dense
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    anchors.baseline: unit.baseline
                    text: Math.round(root.strokeWidth)
                    color: root.eraser ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnSurface
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: Math.round(root.target * 0.62)
                    font.features: ({ "tnum": 1 })
                    width: Math.round(root.target * 0.5)
                    horizontalAlignment: Text.AlignRight
                }

                StyledText {
                    id: unit
                    text: "PX"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 0.6
                }
            }
        }

        // ── Edits ───────────────────────────────────────────────────────────
        // One connected group: outer corners round, inner corners pressed flat, the
        // pressed button rounding out as it is pushed (RippleButton.useDynamicRadius).
        RowLayout {
            Layout.fillWidth: false
            spacing: 2

            DrawToolButton {
                visible: root.full
                useDynamicRadius: true
                symbol: "ink_eraser"
                active: root.eraser
                tooltipText: root.eraser ? Translation.tr("Back to the pen") : Translation.tr("Eraser")
                shortcut: "E"
                onTriggered: root.eraserToggled()
            }

            DrawToolButton {
                useDynamicRadius: true
                symbol: "undo"
                enabled: root.canUndo
                tooltipText: Translation.tr("Undo")
                shortcut: "Ctrl+Z"
                onTriggered: root.undoRequested()
            }

            DrawToolButton {
                visible: root.showRedo && root.full
                useDynamicRadius: true
                symbol: "redo"
                enabled: root.canRedo
                tooltipText: Translation.tr("Redo")
                shortcut: "Ctrl+Shift+Z"
                onTriggered: root.redoRequested()
            }

            DrawToolButton {
                visible: root.full
                useDynamicRadius: true
                symbol: "delete_sweep"
                enabled: root.canClear
                tooltipText: Translation.tr("Clear this screen")
                shortcut: "Del"
                onTriggered: root.clearRequested()
            }
        }

        DrawToolButton {
            visible: root.showPressure && root.full
            symbol: "stylus"
            active: root.usePressure
            // Greyed rather than hidden without a pen: the switch says the feature is
            // there and waiting for hardware.
            enabled: root.pressureAvailable
            tooltipText: root.pressureAvailable
                ? Translation.tr("Pen pressure")
                : Translation.tr("No pen detected — pressure needs a stylus")
            onTriggered: root.pressureToggled()
        }

        // ── What the host does with the drawing ─────────────────────────────
        RowLayout {
            id: trailing
            Layout.fillWidth: false
            visible: root.full && trailing.children.length > 0
            spacing: 2
        }

        // ── The tray itself ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: false
            spacing: 2
            visible: root.showSettings || root.collapsible || root.showClose

            DrawToolButton {
                visible: root.showSettings && root.full
                useDynamicRadius: true
                symbol: "tune"
                active: root.settingsOpen
                tooltipText: Translation.tr("Drawing settings")
                onTriggered: root.settingsToggled()
            }

            DrawToolButton {
                visible: root.collapsible
                useDynamicRadius: true
                symbol: root.collapsed ? "expand_content" : "collapse_content"
                tooltipText: root.collapsed
                    ? Translation.tr("Show every tool")
                    : Translation.tr("Fold the toolbar down to the pen")
                shortcut: "C"
                onTriggered: root.collapseToggled()
            }

            DrawToolButton {
                visible: root.showClose
                useDynamicRadius: true
                symbol: "close"
                tooltipText: Translation.tr("Put the toolbar away and leave the drawing")
                shortcut: "Esc"
                onTriggered: root.closeRequested()
            }
        }
    }

    // Confirmation of a save, and the reason a save failed. Sits under the tray rather
    // than in it: a line that comes and goes inside the tray would move every control.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 6
        visible: root.statusText.length > 0
        implicitWidth: status.implicitWidth + 20
        implicitHeight: status.implicitHeight + 8
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3inverseSurface

        StyledText {
            id: status
            anchors.centerIn: parent
            text: root.statusText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance.m3colors.m3inverseOnSurface
        }
    }
}
