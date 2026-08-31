pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.clock

/**
 * Neural Expressive clock.
 *
 * The family reads the time as something *positioned in a system* rather than
 * as two numbers with a colon:
 *
 *   orbit  Hours in the middle of a ring the minute fills.
 *   bloom  Two interlocking Material shapes, the front one die-cutting the back.
 *   dial   A real analogue face beside the digits.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.clockWidget.neuralVariant ?? "orbit"
    readonly property bool showMeridiem: (Config.options.bar.clockWidget.showMeridiem ?? true)
        && DateTime.meridiem !== ""

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    readonly property string hoursText: DateTime.hours
    readonly property string minutesText: DateTime.minutes
    readonly property string meridiemText: DateTime.meridiem.toUpperCase()

    BarWidgetPalette {
        id: theme
        colorMode: Config.options.bar.clockWidget.colorMode ?? "tonal"
    }

    readonly property real targetLength: root.vertical
        ? Math.max(root.thickness, contentLoader.implicitHeight)
        : Math.max(root.thickness, contentLoader.implicitWidth)
    property real animatedLength: root.targetLength

    // One driver for the slot and the surface both — see AGENTS.md §6.1.
    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.animatedLength
        height: root.vertical ? root.animatedLength : root.thickness
        sourceComponent: {
            if (root.variant === "bloom")
                return bloomVariant;
            if (root.variant === "dial")
                return dialVariant;
            return orbitVariant;
        }
    }

    // ── orbit ────────────────────────────────────────────────────────────────
    Component {
        id: orbitVariant

        GridLayout {
            columns: root.vertical ? 1 : 2
            rowSpacing: 1
            columnSpacing: Math.round(root.thickness * 0.2)

            Item {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.thickness
                implicitHeight: root.thickness

                CircularProgress {
                    anchors.centerIn: parent
                    implicitSize: root.thickness
                    lineWidth: Math.max(2, Math.round(root.thickness * 0.09))
                    // How far through the hour we are. The ring is the only
                    // part of this variant that says something the digits do
                    // not, so it tracks minutes, not hours.
                    value: DateTime.minuteProgress
                    colPrimary: theme.accent
                    colSecondary: ColorUtils.transparentize(theme.accent, 0.8)
                    gapAngle: 0
                }

                StyledText {
                    anchors.centerIn: parent
                    text: root.hoursText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * 0.44)
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.6
                    color: theme.bare
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignCenter
                spacing: -2

                StyledText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.minutesText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.4 : 0.46))
                    font.variableAxes: ({
                        "wght": 700
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.4
                    color: theme.bare
                }

                StyledText {
                    visible: root.showMeridiem
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.meridiemText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.max(8, Math.round(root.thickness * 0.26))
                    font.variableAxes: ({
                        "wght": 600
                    })
                    font.letterSpacing: 1.0
                    color: theme.bareAccent
                }
            }
        }
    }

    // ── bloom ────────────────────────────────────────────────────────────────
    Component {
        id: bloomVariant

        NeuralClockBloom {
            vertical: root.vertical
            thickness: root.thickness
            hoursText: root.hoursText
            minutesText: root.minutesText
            colHours: theme.accent
            colOnHours: theme.onAccent
            colMinutes: theme.container
            colOnMinutes: theme.onContainer
        }
    }

    // ── dial ─────────────────────────────────────────────────────────────────
    Component {
        id: dialVariant

        GridLayout {
            columns: root.vertical ? 1 : 2
            rowSpacing: 2
            columnSpacing: Math.round(root.thickness * 0.22)

            Item {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.thickness
                implicitHeight: root.thickness

                MaterialShape {
                    id: dialFace
                    anchors.centerIn: parent
                    implicitSize: root.thickness
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: theme.container
                }

                // Hands are rounded bars pinned at the face's centre and rotated
                // about that end, which is cheaper and crisper at 32px than a
                // Shape path and needs no stroke joins.
                Rectangle {
                    id: hourHand
                    x: dialFace.x + dialFace.width / 2 - width / 2
                    y: dialFace.y + dialFace.height / 2 - height
                    width: Math.max(2, Math.round(root.thickness * 0.075))
                    height: Math.round(root.thickness * 0.24)
                    radius: Appearance.rounding.full
                    color: theme.onContainer
                    transformOrigin: Item.Bottom
                    rotation: DateTime.hourProgress * 360
                }

                Rectangle {
                    id: minuteHand
                    x: dialFace.x + dialFace.width / 2 - width / 2
                    y: dialFace.y + dialFace.height / 2 - height
                    width: Math.max(2, Math.round(root.thickness * 0.06))
                    height: Math.round(root.thickness * 0.34)
                    radius: Appearance.rounding.full
                    color: theme.accent
                    transformOrigin: Item.Bottom
                    rotation: DateTime.minuteProgress * 360
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignCenter
                spacing: -3

                StyledText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.hoursText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.42 : 0.5))
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.8
                    color: theme.bare
                }

                StyledText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.minutesText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.42 : 0.5))
                    font.variableAxes: ({
                        "wght": 500
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.8
                    color: theme.bareAccent
                }
            }
        }
    }

    MouseArea {
        id: clockMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: clockMouseArea
        }
    }
}
