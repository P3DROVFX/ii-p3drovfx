pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The pen tray: what the pen is doing, the tool, the ink, the thickness, the edits, the
 * presenting modes, and whatever the host adds to the end.
 *
 * A Material 3 Expressive floating toolbar. The groups are told apart by what they are
 * made of rather than by lines between them: the mode is a word set in the title face
 * with its state in small capitals under it, the inks sit on a pill of their own, the
 * thickness is a number in tall condensed digits, and the tools, the edits and the modes
 * are connected button groups whose inner corners press flat.
 *
 * It runs either way: a row along the bottom, or a column when the host docks it to a
 * screen edge (`vertical`). And it gives way on narrow screens by measuring itself, not
 * by guessing: `widthAt(level)` is what each level of compaction would take, so the host
 * picks the first that fits — the words and the digits go first (level 1), then the inks
 * fold into one swatch that opens them (level 2).
 *
 * The ink controls are shared with the Notes sketch editor, which sets none of the
 * `show*` flags and gets the plain pen tray it always had.
 */
Rectangle {
    id: root

    /// Host buttons, appended after the shared controls.
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

    /// Whether the pen is down. Hosts that are always drawing leave `showDrawToggle` off.
    property bool drawing: true
    property bool showDrawToggle: false
    property bool showPressure: true

    /// The mode, said in words: a title ("Draw") over its state. Empty hides it.
    property string title: ""
    property string subtitle: ""

    // ── Tools and modes (live draw) ─────────────────────────────────────────
    property bool showTools: false
    /// pen, highlighter, laser, line, arrow, rect, ellipse
    property string tool: "pen"
    /// The shape the shape button stands for while another tool is picked.
    property string shapeTool: "arrow"
    property bool showPresent: false
    property bool boardOn: false
    property bool spotlightOn: false
    property bool zoomOn: false
    property bool showShare: false
    property bool canShare: root.canClear

    /// Folded down to the pen, undo and the way back out. See LiveDrawWindow.
    property bool collapsible: false
    property bool collapsed: false

    property bool showSettings: false
    property bool settingsOpen: false
    property bool showClose: false

    /// A column instead of a row: the host docked the tray to a screen edge.
    property bool vertical: false
    /// 0: everything. 1: no words, no digits. 2: the inks folded into one swatch.
    property int level: 0

    signal colorPicked(string color)
    signal widthPicked(real width)
    signal drawToggled()
    signal eraserToggled()
    signal pressureToggled()
    signal undoRequested()
    signal redoRequested()
    signal clearRequested()
    signal collapseToggled()
    signal settingsToggled(Item anchor)
    signal closeRequested()
    signal toolPicked(string tool)
    signal shapeMenuRequested(Item anchor)
    signal inkMenuRequested(Item anchor)
    signal shareRequested(Item anchor)
    signal boardToggled()
    signal spotlightToggled()
    signal zoomToggled()

    readonly property real padding: 8
    /// Buttons are a step smaller standing up: a column of full-size targets is taller
    /// than a 1080p screen.
    readonly property real target: root.vertical ? Appearance.sizes.minimumTouchTarget - 8 : Appearance.sizes.minimumTouchTarget
    readonly property bool full: !root.collapsed
    readonly property real chrome: root.padding * 2 + 6
    readonly property real gap: 10

    readonly property var shapeSymbols: ({
        "line": "horizontal_rule",
        "arrow": "arrow_outward",
        "rect": "rectangle",
        "ellipse": "circle"
    })
    readonly property var toolNames: ({
        "pen": Translation.tr("Pen"),
        "highlighter": Translation.tr("Highlighter"),
        "laser": Translation.tr("Laser pointer"),
        "line": Translation.tr("Line"),
        "arrow": Translation.tr("Arrow"),
        "rect": Translation.tr("Rectangle"),
        "ellipse": Translation.tr("Ellipse")
    })

    /**
     * The width the row takes at a level of compaction. Summed from the groups'
     * implicit widths, which do not change with the level (an invisible item keeps its
     * implicit size), so the host can pick a level from this without a binding loop.
     */
    function widthAt(lvl) {
        if (root.vertical || root.collapsed)
            return 0;
        const parts = [leading, modeButton, toolsGroup, editsGroup, presentGroup, shareButton, trailing, endGroup];
        let total = 0;
        let count = 0;
        for (const part of parts) {
            if (!part.wanted)
                continue;
            total += part.implicitWidth;
            count++;
        }
        if (titleColumn.wanted && lvl < 1) {
            total += titleColumn.implicitWidth;
            count++;
        }
        if (inksPill.wanted) {
            total += lvl < 2 ? inksPill.implicitWidth : inkButton.implicitWidth;
            count++;
        }
        total += thickness.sliderWidth + (lvl < 1 ? thickness.digitsWidth + 6 : 0);
        count++;
        return total + root.gap * Math.max(0, count - 1) + root.chrome;
    }

    /// The same, for a column: its height at a level of compaction.
    function heightAt(lvl) {
        if (!root.vertical || root.collapsed)
            return 0;
        const parts = [leading, modeButton, toolsGroup, editsGroup, presentGroup, shareButton, trailing, endGroup, thickness];
        let total = 0;
        let count = 0;
        for (const part of parts) {
            if (!(part.wanted ?? part.visible))
                continue;
            total += part.implicitHeight;
            count++;
        }
        if (inksPill.wanted) {
            total += lvl < 2 ? inksPill.implicitHeight : inkButton.implicitHeight;
            count++;
        }
        return total + root.gap * Math.max(0, count - 1) + root.padding * 2;
    }

    implicitWidth: layout.implicitWidth + root.chrome
    implicitHeight: layout.implicitHeight + root.padding * 2
    radius: root.vertical ? Math.min(Appearance.rounding.verylarge, width / 2) : Appearance.rounding.full
    // Opaque tones, not the layer tokens: those are translucent under a transparency
    // theme and lean on the compositor blurring what is behind them, and this tray floats
    // over arbitrary applications on a layer nothing blurs.
    color: Appearance.m3colors.m3surfaceContainer

    /// A row or a column of a group, with its buttons' inner corners pressed flat.
    component Group: GridLayout {
        property bool wanted: true
        visible: wanted
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? 32 : 1
        columns: root.vertical ? 1 : 32
        rowSpacing: 2
        columnSpacing: 2
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignCenter
    }

    component GroupButton: DrawToolButton {
        size: root.target
        useDynamicRadius: true
        groupHorizontal: !root.vertical
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? 32 : 1
        columns: root.vertical ? 1 : 32
        rowSpacing: root.gap
        columnSpacing: root.gap

        Group {
            id: leading
            wanted: leading.children.length > 0
        }

        // ── Mode ────────────────────────────────────────────────────────────
        // The pen as the largest control, round while up, a rounded square while down:
        // the shape is the state.
        DrawToolButton {
            id: modeButton
            readonly property bool wanted: root.showDrawToggle
            visible: wanted
            Layout.alignment: Qt.AlignCenter
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
            id: titleColumn
            readonly property bool wanted: root.title.length > 0 && root.full
            visible: wanted && root.level < 1 && !root.vertical
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                text: root.title
                color: Appearance.colors.colOnSurface
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
            }

            StyledText {
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

        // ── Tools ───────────────────────────────────────────────────────────
        Group {
            id: toolsGroup
            wanted: root.showTools && root.full

            GroupButton {
                symbol: "ink_pen"
                active: !root.eraser && root.tool === "pen"
                tooltipText: Translation.tr("Pen")
                shortcut: "P"
                onTriggered: root.toolPicked("pen")
            }
            GroupButton {
                symbol: "ink_highlighter"
                active: !root.eraser && root.tool === "highlighter"
                tooltipText: Translation.tr("Highlighter — under the ink, see-through")
                shortcut: "H"
                onTriggered: root.toolPicked("highlighter")
            }
            GroupButton {
                symbol: "stylus_laser_pointer"
                active: !root.eraser && root.tool === "laser"
                tooltipText: Translation.tr("Laser pointer — fades on its own")
                shortcut: "L"
                onTriggered: root.toolPicked("laser")
            }
            GroupButton {
                id: shapeButton
                readonly property bool picked: !root.eraser && (root.shapeSymbols[root.tool] !== undefined)
                symbol: root.shapeSymbols[picked ? root.tool : root.shapeTool] ?? "arrow_outward"
                active: picked
                tooltipText: picked
                    ? Translation.tr("%1 — click again for other shapes · Shift snaps").arg(root.toolNames[root.tool])
                    : Translation.tr("Shapes: %1").arg(root.toolNames[root.shapeTool])
                shortcut: "A R O I"
                onTriggered: {
                    if (picked)
                        root.shapeMenuRequested(shapeButton);
                    else
                        root.toolPicked(root.shapeTool);
                }
            }
            GroupButton {
                symbol: "ink_eraser"
                active: root.eraser
                tooltipText: root.eraser ? Translation.tr("Back to the pen") : Translation.tr("Eraser")
                shortcut: "E"
                onTriggered: root.eraserToggled()
            }
        }

        // ── Ink ─────────────────────────────────────────────────────────────
        // On a pill of their own, one step up the surface ladder.
        Rectangle {
            id: inksPill
            readonly property bool wanted: root.full && root.palette.length > 0
            visible: wanted && root.level < 2
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignCenter
            implicitWidth: inks.implicitWidth + 8
            implicitHeight: inks.implicitHeight + 8
            radius: root.vertical ? Appearance.rounding.large : Appearance.rounding.full
            color: Appearance.m3colors.m3surfaceContainerHigh

            Grid {
                id: inks
                anchors.centerIn: parent
                columns: root.vertical ? 2 : 32
                spacing: 0

                Repeater {
                    model: inksPill.wanted ? root.palette : []

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

        // Folded inks: the current one, which opens the rest.
        RippleButton {
            id: inkButton
            visible: inksPill.wanted && root.level >= 2
            Layout.alignment: Qt.AlignCenter
            implicitWidth: root.target
            implicitHeight: root.target
            focusPolicy: Qt.NoFocus
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.m3colors.m3surfaceContainerHigh
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            onClicked: root.inkMenuRequested(inkButton)

            contentItem: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: Appearance.rounding.small
                    color: root.currentColor.length > 0 ? root.currentColor : "transparent"
                }
            }

            StyledToolTip {
                requireOverlay: false
                text: Translation.tr("Inks") + "  ·  1–9"
            }
        }

        // ── Thickness ───────────────────────────────────────────────────────
        // The number in tall condensed digits beside the slider; on a column, between
        // a thicker and a thinner button.
        GridLayout {
            id: thickness
            visible: root.full
            readonly property real sliderWidth: root.target * 2.4
            readonly property real digitsWidth: widthValue.implicitWidth
            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: root.vertical ? 3 : 1
            columns: root.vertical ? 1 : 3
            rowSpacing: 2
            columnSpacing: 6
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignCenter

            GroupButton {
                visible: root.vertical
                Layout.alignment: Qt.AlignHCenter
                size: root.target - 6
                symbol: "add"
                tooltipText: Translation.tr("Thicker")
                shortcut: "]"
                onTriggered: root.widthPicked(Math.min(24, Math.round(root.strokeWidth) + 1))
            }

            StyledSlider {
                id: widthSlider
                visible: !root.vertical
                Layout.preferredWidth: thickness.sliderWidth
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

            // Centred on the digit's ink, not its text box: a box makes room for
            // descenders digits never have, so a box-centred number sat high.
            Item {
                id: widthValue
                visible: root.level < 1 || root.vertical
                Layout.alignment: Qt.AlignCenter
                implicitWidth: digits.width + 2 + unit.implicitWidth
                implicitHeight: root.vertical ? Math.round(root.target * 0.8) : root.target

                readonly property rect glyph: digitMetrics.tightBoundingRect("0")

                FontMetrics {
                    id: digitMetrics
                    font: digits.font
                }

                StyledText {
                    id: digits
                    // Baseline placed so the glyph's own middle lands on the row's.
                    anchors.baseline: parent.top
                    anchors.baselineOffset: Math.round(widthValue.height / 2
                        - (widthValue.glyph.y + widthValue.glyph.height / 2))
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
                    anchors.left: digits.right
                    anchors.leftMargin: 2
                    anchors.baseline: digits.baseline
                    text: "PX"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 0.6
                }
            }

            GroupButton {
                visible: root.vertical
                Layout.alignment: Qt.AlignHCenter
                size: root.target - 6
                symbol: "remove"
                tooltipText: Translation.tr("Thinner")
                shortcut: "["
                onTriggered: root.widthPicked(Math.max(1, Math.round(root.strokeWidth) - 1))
            }
        }

        // ── Edits ───────────────────────────────────────────────────────────
        Group {
            id: editsGroup

            GroupButton {
                visible: !root.showTools && root.full
                symbol: "ink_eraser"
                active: root.eraser
                tooltipText: root.eraser ? Translation.tr("Back to the pen") : Translation.tr("Eraser")
                shortcut: "E"
                onTriggered: root.eraserToggled()
            }
            GroupButton {
                symbol: "undo"
                enabled: root.canUndo
                tooltipText: Translation.tr("Undo")
                shortcut: "Ctrl+Z"
                onTriggered: root.undoRequested()
            }
            GroupButton {
                visible: root.showRedo && root.full
                symbol: "redo"
                enabled: root.canRedo
                tooltipText: Translation.tr("Redo")
                shortcut: "Ctrl+Shift+Z"
                onTriggered: root.redoRequested()
            }
            GroupButton {
                visible: root.full
                symbol: "delete_sweep"
                enabled: root.canClear
                tooltipText: Translation.tr("Clear this screen")
                shortcut: "Del"
                onTriggered: root.clearRequested()
            }
        }

        DrawToolButton {
            visible: root.showPressure && root.full
            Layout.alignment: Qt.AlignCenter
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

        // ── Presenting ──────────────────────────────────────────────────────
        Group {
            id: presentGroup
            wanted: root.showPresent && root.full

            GroupButton {
                symbol: "developer_board"
                active: root.boardOn
                tooltipText: root.boardOn ? Translation.tr("Back to the screen") : Translation.tr("Board — a blank page over the screen")
                shortcut: "W / K"
                onTriggered: root.boardToggled()
            }
            GroupButton {
                symbol: "flashlight_on"
                active: root.spotlightOn
                tooltipText: Translation.tr("Spotlight — dim all but the pointer")
                shortcut: "F"
                onTriggered: root.spotlightToggled()
            }
            GroupButton {
                symbol: "zoom_in"
                active: root.zoomOn
                tooltipText: Translation.tr("Zoom — magnify around the pointer")
                shortcut: "Z"
                onTriggered: root.zoomToggled()
            }
        }

        // ── What the host does with the drawing ─────────────────────────────
        DrawToolButton {
            id: shareButton
            size: root.target
            readonly property bool wanted: root.showShare && root.full
            visible: wanted
            Layout.alignment: Qt.AlignCenter
            symbol: "ios_share"
            emphasised: true
            enabled: root.canShare
            tooltipText: Translation.tr("Copy, save or file the drawing")
            shortcut: "Ctrl+C"
            onTriggered: root.shareRequested(shareButton)
        }

        Group {
            id: trailing
            wanted: root.full && trailing.children.length > 0
        }

        // ── The tray itself ─────────────────────────────────────────────────
        Group {
            id: endGroup
            wanted: root.showSettings || root.collapsible || root.showClose

            GroupButton {
                id: settingsButton
                visible: root.showSettings && root.full
                symbol: "tune"
                active: root.settingsOpen
                tooltipText: Translation.tr("Drawing settings")
                onTriggered: root.settingsToggled(settingsButton)
            }
            GroupButton {
                visible: root.collapsible
                symbol: root.collapsed ? "expand_content" : "collapse_content"
                tooltipText: root.collapsed
                    ? Translation.tr("Show every tool")
                    : Translation.tr("Fold the toolbar down to the pen")
                shortcut: "C"
                onTriggered: root.collapseToggled()
            }
            GroupButton {
                visible: root.showClose
                symbol: "close"
                tooltipText: Translation.tr("Put the toolbar away and leave the drawing")
                shortcut: "Esc"
                onTriggered: root.closeRequested()
            }
        }
    }

    // Confirmation of a save, and the reason a save failed. Outside the tray: a line
    // that comes and goes inside it would move every control.
    Rectangle {
        x: root.vertical ? (root.x > 200 ? -width - 8 : root.width + 8) : (root.width - width) / 2
        y: root.vertical ? (root.height - height) / 2 : root.height + 6
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
