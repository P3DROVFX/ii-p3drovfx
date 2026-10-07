pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Every live draw preference, in the drawing itself.
 *
 * Opened from the tray's tune button, so changing how the pen behaves never means
 * leaving the screen being annotated for the Settings app. The only switch that stays in
 * Settings is the one that turns live draw off, which cannot live inside the thing it
 * removes.
 *
 * Built from the timetable form vocabulary (docs/design): a header in the title face,
 * then filled rows — each with its own Material shape, a caption and its control — and
 * the keyboard shortcuts as keycaps at the end, since the tray only hints at them.
 */
Rectangle {
    id: root

    /// Whether a measuring pen has touched the sheet yet. Pressure is moot without one.
    property bool penSeen: false

    signal closeRequested()

    readonly property var opts: Config.options?.tablet?.liveDraw ?? null

    implicitWidth: 380
    implicitHeight: column.implicitHeight + 32
    radius: Appearance.rounding.verylarge
    color: Appearance.m3colors.m3surfaceContainer

    function setPen(key, value) {
        if (Config.ready && Config.options.tablet.liveDraw[key] !== value)
            Config.options.tablet.liveDraw[key] = value;
    }

    // A row: shape, caption over a line, and the control on the right.
    component SettingRow: Rectangle {
        id: row
        property string symbol: ""
        property var shape: MaterialShape.Shape.Cookie7Sided
        property string label: ""
        property string detail: ""
        property bool on: false
        default property alias control: controlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(60, rowLayout.implicitHeight + 16)
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHighest

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                shape: row.shape
                text: row.symbol
                iconSize: 18
                padding: 9
                fill: row.on ? 1 : 0
                // Primary when on, a step down the surface ladder when off: the container
                // tones sit within a shade of the row in low-chroma schemes.
                color: row.on ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerLow
                colSymbol: row.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: row.detail.length > 0
                    text: row.detail
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            Item {
                id: controlSlot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    // A slider row: caption and the value in condensed digits above a full-width slider.
    component SliderRow: Rectangle {
        id: srow
        property string symbol: ""
        property var shape: MaterialShape.Shape.Cookie7Sided
        property string label: ""
        property string detail: ""
        property real value: 0
        signal moved(real value)

        Layout.fillWidth: true
        implicitHeight: sliderColumn.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHighest

        ColumnLayout {
            id: sliderColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    shape: srow.shape
                    text: srow.symbol
                    iconSize: 18
                    padding: 9
                    color: srow.value > 0 ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerLow
                    colSymbol: srow.value > 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: srow.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: srow.detail
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                StyledText {
                    text: srow.value === 0 ? Translation.tr("Off") : Math.round(srow.value)
                    color: srow.value === 0 ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                    font.pixelSize: srow.value === 0 ? Appearance.font.pixelSize.normal : 30
                    font.features: ({ "tnum": 1 })
                }
            }

            StyledSlider {
                id: slider
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 5
                focusPolicy: Qt.NoFocus
                value: srow.value
                usePercentTooltip: false
                trackColor: ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHighest, Appearance.m3colors.m3onSurface, 0.8)
                onMoved: srow.moved(slider.value)
            }
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.SoftBurst
                text: "draw"
                iconSize: 24
                padding: 12
                fill: 1
                color: Appearance.colors.colPrimary
                colSymbol: Appearance.colors.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2
                StyledText {
                    text: Translation.tr("Draw on screen")
                    color: Appearance.colors.colOnSurface
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                }
                StyledText {
                    text: Translation.tr("Pen, mouse and shortcuts")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            DrawToolButton {
                symbol: "close"
                size: 40
                tooltipText: Translation.tr("Close")
                onTriggered: root.closeRequested()
            }
        }

        // ── The pen ─────────────────────────────────────────────────────────
        SettingRow {
            symbol: "stylus"
            shape: MaterialShape.Shape.Cookie9Sided
            label: Translation.tr("Pen pressure")
            detail: root.penSeen
                ? Translation.tr("Press harder for a thicker line")
                : Translation.tr("Waiting for a pen — a mouse always draws even lines")
            on: LiveDraw.usePressure

            StyledSwitch {
                focusPolicy: Qt.NoFocus
                checked: LiveDraw.usePressure
                onClicked: root.setPen("pressure", !LiveDraw.usePressure)
            }
        }

        SliderRow {
            symbol: "mouse"
            shape: MaterialShape.Shape.Clover4Leaf
            label: Translation.tr("Mouse smoothing")
            detail: Translation.tr("Steadies the hand on a mouse or a touchpad")
            value: Config.options?.liveDraw?.mouseSmoothing ?? 60
            onMoved: value => {
                if (Config.ready)
                    Config.options.liveDraw.mouseSmoothing = Math.round(value);
            }
        }

        SliderRow {
            symbol: "gesture"
            shape: MaterialShape.Shape.Flower
            label: Translation.tr("Line smoothing")
            detail: Translation.tr("Rounds every line off; higher trails further behind")
            value: root.opts?.smoothing ?? 55
            onMoved: value => root.setPen("smoothing", Math.min(95, Math.round(value)))
        }

        SettingRow {
            symbol: "view_carousel"
            shape: MaterialShape.Shape.Pill
            label: Translation.tr("Slide with the workspace")
            detail: Translation.tr("Drawings travel with their workspace when you switch")
            on: root.opts?.workspaceParallax ?? true

            StyledSwitch {
                focusPolicy: Qt.NoFocus
                checked: root.opts?.workspaceParallax ?? true
                onClicked: root.setPen("workspaceParallax", !(root.opts?.workspaceParallax ?? true))
            }
        }

        // ── Shortcuts ───────────────────────────────────────────────────────
        StyledText {
            Layout.topMargin: 6
            Layout.leftMargin: 4
            text: Translation.tr("Keyboard, while drawing")
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            columns: 2
            columnSpacing: 12
            rowSpacing: 6

            Repeater {
                model: [
                    { keys: ["Ctrl", "Z"], text: Translation.tr("Undo") },
                    { keys: ["Ctrl", "Shift", "Z"], text: Translation.tr("Redo") },
                    { keys: ["E"], text: Translation.tr("Eraser") },
                    { keys: ["1", "–", "9"], text: Translation.tr("Ink") },
                    { keys: ["[", "]"], text: Translation.tr("Thickness") },
                    { keys: ["Del"], text: Translation.tr("Clear this screen") },
                    { keys: ["Tab"], text: Translation.tr("Clicks go through") },
                    { keys: ["C"], text: Translation.tr("Fold the toolbar") },
                    { keys: ["Ctrl", "S"], text: Translation.tr("Save to Notes") },
                    { keys: ["Esc"], text: Translation.tr("Close") }
                ]

                delegate: RowLayout {
                    id: shortcutRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    KeyHint {
                        keys: shortcutRow.modelData.keys
                        pixelSize: 11
                        surface: Appearance.m3colors.m3surfaceContainer
                        onSurface: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: shortcutRow.modelData.text
                        color: Appearance.colors.colOnSurface
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
