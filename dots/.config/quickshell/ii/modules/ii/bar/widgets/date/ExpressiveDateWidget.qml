pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.clock

/**
 * Material 3 Expressive date widget.
 *
 * Three variants, all built from the same rule: every part of the date gets its
 * own type treatment, so weight and size — not punctuation — tell you which
 * number you are reading.
 *
 *   stack   Oversized day numeral die-cut by the month and the weekday chip,
 *           which sit on top of it with a burned-out margin around them.
 *   badge   Day inside a cookie shape that overhangs the label pill it sits on.
 *   ribbon  Yesterday / today / tomorrow as a strip, today filled.
 *
 * The widget is paddingless in the bar, so it owns its own surface (or has none
 * at all, in `stack`).
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.dateWidget.expressiveVariant ?? "stack"
    readonly property bool uppercase: Config.options.bar.dateWidget.uppercase ?? true
    // The vertical bar is 44px wide; a year suffix does not fit next to a month
    // there, so the option only applies to the horizontal bar.
    readonly property bool showYear: (Config.options.bar.dateWidget.showYear ?? false) && !root.vertical

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    // Vertical bars are read top-to-bottom, so the long axis is free and the
    // short one is the constraint — the exact opposite of horizontal. Every
    // type size below is a fraction of `thickness`, which is why one set of
    // ratios per orientation is enough.
    readonly property real dayPixelSize: Math.round(root.thickness * (root.vertical ? 0.62 : 0.92))
    readonly property real labelPixelSize: Math.max(9, Math.round(root.thickness * (root.vertical ? 0.27 : 0.33)))
    readonly property real subLabelPixelSize: Math.max(8, Math.round(root.thickness * (root.vertical ? 0.24 : 0.30)))

    function cased(text) {
        return root.uppercase ? String(text).toUpperCase() : String(text);
    }

    readonly property string weekdayText: root.cased(DateTime.dayNameShort)
    readonly property string weekdayPrevText: root.cased(DateTime.dayNameShortPrev)
    readonly property string weekdayNextText: root.cased(DateTime.dayNameShortNext)
    readonly property string monthText: root.cased(DateTime.monthNameShort)
    readonly property string dayText: DateTime.dayOfMonth

    BarWidgetPalette {
        id: theme
        colorMode: Config.options.bar.dateWidget.colorMode ?? "tonal"
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
            if (root.variant === "badge")
                return badgeVariant;
            if (root.variant === "ribbon")
                return ribbonVariant;
            return stackVariant;
        }
    }

    // ── stack ────────────────────────────────────────────────────────────────
    Component {
        id: stackVariant

        ExpressiveDateStack {
            vertical: root.vertical
            thickness: root.thickness
            dayPixelSize: root.dayPixelSize
            labelPixelSize: root.labelPixelSize
            subLabelPixelSize: root.subLabelPixelSize
            dayText: root.dayText
            monthText: root.showYear ? `${root.monthText} ${DateTime.yearShort}` : root.monthText
            weekdayText: root.weekdayText
            colDay: theme.bare
            colMonth: theme.bareAccent
            colChip: theme.accent
            colOnChip: theme.onAccent
        }
    }

    // ── badge ────────────────────────────────────────────────────────────────
    Component {
        id: badgeVariant

        Item {
            id: badgeRoot

            readonly property real badgeSize: Math.round(root.thickness * (root.vertical ? 0.82 : 0.94))
            // How much of the pill's rounded end the badge covers. It stays
            // inside the measured box, so the overlap is drawn, not spilled
            // onto whatever widget sits next in the bar.
            readonly property real overlap: Math.round(badgeRoot.badgeSize * 0.42)

            implicitWidth: root.vertical
                ? root.thickness
                : badgeRoot.badgeSize + labelPlate.implicitWidth - badgeRoot.overlap
            implicitHeight: root.vertical
                ? badgeRoot.badgeSize + labelPlate.implicitHeight - badgeRoot.overlap
                : root.thickness

            Rectangle {
                id: labelPlate
                implicitWidth: root.vertical
                    ? root.thickness
                    : badgeLabels.implicitWidth + badgeRoot.overlap + Math.round(root.thickness * 0.52)
                implicitHeight: root.vertical
                    ? badgeLabels.implicitHeight + badgeRoot.overlap + Math.round(root.thickness * 0.26)
                    : Math.round(root.thickness * 0.84)
                // A rounded rectangle against an organic badge. Matching the
                // badge's curvature turns the pair into one blob at bar scale.
                radius: Appearance.rounding.small
                color: theme.container

                anchors.right: root.vertical ? undefined : parent.right
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.bottom: root.vertical ? parent.bottom : undefined
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                ColumnLayout {
                    id: badgeLabels
                    spacing: -1

                    anchors.right: root.vertical ? undefined : parent.right
                    anchors.rightMargin: root.vertical ? 0 : Math.round(root.thickness * 0.26)
                    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    anchors.bottom: root.vertical ? parent.bottom : undefined
                    anchors.bottomMargin: root.vertical ? Math.round(root.thickness * 0.13) : 0

                    StyledText {
                        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                        text: root.weekdayText
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.labelPixelSize
                        font.variableAxes: ({
                            "wght": 750
                        })
                        font.letterSpacing: 1.0
                        color: theme.onContainer
                    }

                    StyledText {
                        Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                        text: root.showYear ? `${root.monthText} ${DateTime.yearShort}` : root.monthText
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.subLabelPixelSize
                        font.variableAxes: ({
                            "wght": 500
                        })
                        font.letterSpacing: 1.0
                        color: theme.onContainer
                        opacity: 0.7
                    }
                }
            }

            MaterialShape {
                id: dayBadge
                implicitSize: badgeRoot.badgeSize
                shape: MaterialShape.Shape.Cookie9Sided
                color: theme.accent

                anchors.left: root.vertical ? undefined : parent.left
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? parent.top : undefined
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                StyledText {
                    anchors.centerIn: parent
                    text: root.dayText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(badgeRoot.badgeSize * 0.46)
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.6
                    color: theme.onAccent
                }
            }
        }
    }

    // ── ribbon ───────────────────────────────────────────────────────────────
    Component {
        id: ribbonVariant

        GridLayout {
            columns: root.vertical ? 1 : 3
            rowSpacing: 2
            columnSpacing: 3

            StyledText {
                Layout.alignment: Qt.AlignCenter
                text: root.weekdayPrevText
                font.family: Appearance.font.family.title
                font.pixelSize: root.subLabelPixelSize
                font.variableAxes: ({
                    "wght": 600
                })
                font.letterSpacing: 1.0
                color: theme.bare
                opacity: 0.36
            }

            Rectangle {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical
                    ? root.thickness
                    : todayRow.implicitWidth + Math.round(root.thickness * 0.5)
                implicitHeight: root.vertical
                    ? todayRow.implicitHeight + Math.round(root.thickness * 0.3)
                    : root.thickness
                radius: Appearance.rounding.full
                color: theme.accent

                GridLayout {
                    id: todayRow
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 2
                    rowSpacing: -1
                    columnSpacing: 5

                    StyledText {
                        Layout.alignment: Qt.AlignCenter
                        text: root.weekdayText
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.labelPixelSize
                        font.variableAxes: ({
                            "wght": 700
                        })
                        font.letterSpacing: 1.0
                        color: theme.onAccent
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignCenter
                        text: root.dayText
                        font.family: Appearance.font.family.title
                        font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.42 : 0.52))
                        font.variableAxes: ({
                            "wght": 800
                        })
                        font.features: ({
                            "tnum": 1
                        })
                        font.letterSpacing: -0.6
                        color: theme.onAccent
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignCenter
                text: root.weekdayNextText
                font.family: Appearance.font.family.title
                font.pixelSize: root.subLabelPixelSize
                font.variableAxes: ({
                    "wght": 600
                })
                font.letterSpacing: 1.0
                color: theme.bare
                opacity: 0.36
            }
        }
    }

    MouseArea {
        id: dateMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: dateMouseArea
        }
    }
}
