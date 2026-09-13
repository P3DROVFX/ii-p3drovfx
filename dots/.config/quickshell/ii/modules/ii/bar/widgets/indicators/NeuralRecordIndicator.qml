pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Neural Expressive record indicator.
 *
 * The Neural family reads a value as something *structured* rather than as a
 * label with a number next to it:
 *
 *   duo    The clock cut in two — minutes and seconds in two separate Material
 *          shapes, with a real gap between them and no colon anywhere.
 *   slab   A solid plate carrying the clock, with the minute running as a rail
 *          along its bottom edge.
 *   meter  No surface at all: a bare rail beside bare numerals.
 *
 * Where a rail appears it is a progress indicator, not a pulse: it advances in
 * one direction, it is derived from the elapsed time, and it stands still the
 * moment the recording is paused.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool minimal: false
    property bool live: false
    property bool loading: false
    property bool paused: false
    property bool hovering: false
    property bool animateDigits: true
    property bool showLabel: true
    property string timeText: "00:00"
    property string label: "REC"
    property string stateIcon: "videocam"
    // 0 → 1 through the current minute.
    property real minuteProgress: 0

    readonly property string variant: Config.options.bar.indicators.record.neuralVariant ?? "duo"
    readonly property bool showTime: !root.minimal && !root.loading

    BarWidgetPalette {
        id: theme
        colorMode: Config.options.bar.indicators.record.colorMode ?? "alert"
    }

    readonly property real labelPixelSize: Math.max(8, Math.round(root.thickness * (root.vertical ? 0.23 : 0.27)))
    readonly property real timePixelSize: Math.max(10, Math.round(root.thickness * (root.vertical ? 0.34 : 0.44)))
    readonly property real stateOpacity: root.paused ? 0.72 : 1.0

    // The clock split in two: everything the seconds are not on one side —
    // minutes alone most of the time, `HH:MM` once a capture has run past an
    // hour — and the seconds, the half that actually moves, on the other.
    readonly property string leadText: {
        const parts = root.timeText.split(":");
        return parts.length > 1 ? parts.slice(0, -1).join(":") : "00";
    }
    readonly property string secondsText: {
        const parts = root.timeText.split(":");
        return parts.length > 1 ? parts[parts.length - 1] : "00";
    }

    implicitWidth: contentLoader.implicitWidth
    implicitHeight: contentLoader.implicitHeight

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: {
            if (root.variant === "slab")
                return slabVariant;
            if (root.variant === "meter")
                return meterVariant;
            return duoVariant;
        }
    }

    // ── duo ──────────────────────────────────────────────────────────────────
    Component {
        id: duoVariant

        GridLayout {
            id: duo

            // Two bodies, not one object: the gap is the design, so it is wide
            // enough that the pair can never read as a single shape with a
            // notch in it.
            readonly property real shapeSize: Math.round(root.thickness * 0.94)
            readonly property real digitSize: Math.max(10, Math.round(duo.shapeSize * 0.44))

            columns: root.vertical ? 1 : 2
            rowSpacing: Math.round(root.thickness * 0.14)
            columnSpacing: Math.round(root.thickness * 0.2)
            opacity: root.stateOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(duo)
            }

            // The slower half, in the quieter tone. A flat squircle against a
            // seven-lobed cookie — two silhouettes that cannot be confused at
            // bar scale, which is the whole point of splitting the clock into
            // bodies instead of punctuating it with a colon. A spikier shape
            // (SoftBurst) was tried here and lost: the lobes eat the room the
            // two numerals need, and the star fights the calm square beside it.
            MaterialShape {
                Layout.alignment: Qt.AlignCenter
                visible: root.showTime
                implicitSize: duo.shapeSize
                shape: MaterialShape.Shape.Square
                color: theme.colContainer

                StyledText {
                    anchors.centerIn: parent
                    text: root.leadText
                    font.family: Appearance.font.family.title
                    font.pixelSize: root.leadText.length > 2
                        ? Math.max(9, Math.round(duo.digitSize * 0.62))
                        : duo.digitSize
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.6
                    color: theme.colOnContainer
                }
            }

            // The half that moves, in the loud tone. It also stands in for the
            // whole widget when there is no clock to show, so `minimal` is one
            // shape rather than a gap with nothing on the other side of it.
            MaterialShape {
                Layout.alignment: Qt.AlignCenter
                implicitSize: duo.shapeSize
                shape: MaterialShape.Shape.Cookie7Sided
                color: root.hovering ? theme.colContainer : theme.colAccent

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RecordTimerText {
                    anchors.centerIn: parent
                    visible: root.showTime
                    value: root.secondsText
                    pixelSize: duo.digitSize
                    colText: root.hovering ? theme.colOnContainer : theme.colOnAccent
                    weight: 800
                    letterSpacing: -0.4
                    animate: root.animateDigits
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.showTime
                    text: root.stateIcon
                    iconSize: Math.round(duo.shapeSize * 0.46)
                    fill: root.live ? 1 : 0
                    color: root.hovering ? theme.colOnContainer : theme.colOnAccent

                    RotationAnimator on rotation {
                        running: root.loading
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }
            }
        }
    }

    // ── slab ─────────────────────────────────────────────────────────────────
    Component {
        id: slabVariant

        Rectangle {
            id: slab

            readonly property real inset: Math.round(root.thickness * (root.vertical ? 0.16 : 0.26))
            readonly property real railThickness: Math.max(2, Math.round(root.thickness * 0.075))

            implicitWidth: root.vertical
                ? root.thickness
                : (root.showTime ? slabBody.implicitWidth + slab.inset * 2 : root.thickness)
            implicitHeight: root.vertical
                ? (root.showTime ? slabBody.implicitHeight + slab.inset * 2 + slab.railThickness : root.thickness)
                : root.thickness
            // A block, not a capsule: the Expressive family owns the pill, and
            // two pills side by side in one bar are indistinguishable.
            radius: Math.min(Appearance.rounding.small, Math.round(root.thickness * 0.26))
            color: root.hovering ? theme.colContainer : theme.colAccent
            opacity: root.stateOpacity

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(slab)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(slab)
            }

            readonly property color colContent: root.hovering ? theme.colOnContainer : theme.colOnAccent

            RecordTimerText {
                id: slabBody
                visible: root.showTime
                anchors.centerIn: parent
                anchors.verticalCenterOffset: root.vertical ? -Math.round(slab.railThickness) : -Math.round(slab.railThickness * 0.7)
                value: root.timeText
                stacked: root.vertical
                stackSpacing: -3
                pixelSize: root.timePixelSize
                colText: slab.colContent
                weight: 780
                letterSpacing: -0.5
                animate: root.animateDigits
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.showTime
                text: root.stateIcon
                iconSize: Math.round(root.thickness * 0.46)
                fill: root.live ? 1 : 0
                color: slab.colContent

                RotationAnimator on rotation {
                    running: root.loading
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }

            // The minute, running along the foot of the plate.
            Item {
                visible: root.showTime
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: slab.inset
                anchors.rightMargin: slab.inset
                anchors.bottomMargin: Math.round(slab.inset * 0.5)
                implicitHeight: slab.railThickness

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: slab.colContent
                    opacity: 0.24
                }

                Rectangle {
                    id: slabRailFill
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, root.minuteProgress))
                    radius: Appearance.rounding.full
                    color: slab.colContent

                    Behavior on width {
                        enabled: !Appearance.reducedMotion && !root.loading
                        NumberAnimation {
                            duration: Math.round(950 * Appearance.animMultiplier)
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // ── meter ────────────────────────────────────────────────────────────────
    Component {
        id: meterVariant

        GridLayout {
            id: meterRoot

            readonly property real railThickness: Math.max(3, Math.round(root.thickness * 0.1))
            readonly property real railLength: Math.round(root.thickness * (root.vertical ? 0.62 : 0.78))

            columns: root.vertical ? 1 : 2
            rowSpacing: Math.round(root.thickness * 0.1)
            columnSpacing: Math.round(root.thickness * 0.24)
            opacity: root.stateOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(meterRoot)
            }

            // Vertical bar: the rail lies across the top. Horizontal bar: it
            // stands on end beside the numerals and fills upwards, so in both
            // orientations it grows along the bar's own reading direction.
            Item {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical ? meterRoot.railLength : meterRoot.railThickness
                implicitHeight: root.vertical ? meterRoot.railThickness : meterRoot.railLength

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: theme.colBare
                    opacity: 0.2
                }

                Rectangle {
                    id: meterFill
                    readonly property real fraction: Math.max(0, Math.min(1, root.minuteProgress))

                    width: root.vertical ? parent.width * meterFill.fraction : parent.width
                    height: root.vertical ? parent.height : parent.height * meterFill.fraction
                    anchors.left: root.vertical ? parent.left : undefined
                    anchors.bottom: root.vertical ? undefined : parent.bottom
                    radius: Appearance.rounding.full
                    color: theme.colAccent

                    Behavior on width {
                        enabled: root.vertical && !Appearance.reducedMotion && !root.loading
                        NumberAnimation {
                            duration: Math.round(950 * Appearance.animMultiplier)
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on height {
                        enabled: !root.vertical && !Appearance.reducedMotion && !root.loading
                        NumberAnimation {
                            duration: Math.round(950 * Appearance.animMultiplier)
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignCenter
                spacing: -2

                RecordTimerText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    visible: root.showTime
                    value: root.timeText
                    stacked: root.vertical
                    stackSpacing: -3
                    pixelSize: root.timePixelSize
                    colText: theme.colBare
                    weight: 750
                    letterSpacing: -0.4
                    animate: root.animateDigits
                }

                RowLayout {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    visible: root.showLabel || !root.showTime
                    spacing: 3

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: !root.showTime
                        text: root.stateIcon
                        iconSize: root.labelPixelSize + 2
                        fill: root.live ? 1 : 0
                        color: theme.colBareAccent

                        RotationAnimator on rotation {
                            running: root.loading
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.label
                        animateChange: !Appearance.reducedMotion
                        animationDistanceX: 0
                        animationDistanceY: Math.round(root.labelPixelSize * 0.4)
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.labelPixelSize
                        font.variableAxes: ({
                            "wght": 650
                        })
                        font.letterSpacing: 1.0
                        color: theme.colBareAccent
                        opacity: 0.85
                    }
                }
            }
        }
    }
}
