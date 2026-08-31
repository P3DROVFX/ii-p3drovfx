pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.clock

/**
 * Relief clock — a family built entirely out of one idea: **what is removed**.
 *
 * Every variant here is an inverted `OpacityMask`. Nothing is outlined with a
 * stroke and nothing has a border; the shapes you read are the gaps where one
 * layer has been subtracted from another.
 *
 *   split    Hours and minutes overlapping, the minutes cutting the hours.
 *   seam     One hairline the numerals cut as they cross it.
 *   outline  Minutes as hollow numerals — a glyph subtracted from its own
 *            dilated copy, which leaves the rule around it and nothing inside.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.clockWidget.reliefVariant ?? "split"
    readonly property bool showMeridiem: (Config.options.bar.clockWidget.showMeridiem ?? true)
        && DateTime.meridiem !== ""

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

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
            if (root.variant === "seam")
                return seamVariant;
            if (root.variant === "outline")
                return outlineVariant;
            return splitVariant;
        }
    }

    Component {
        id: splitVariant

        ReliefClockSplit {
            vertical: root.vertical
            thickness: root.thickness
            hoursText: DateTime.hours
            minutesText: DateTime.minutes
            colHours: theme.bareAccent
            colMinutes: theme.bare
        }
    }

    Component {
        id: seamVariant

        ReliefClockSeam {
            vertical: root.vertical
            thickness: root.thickness
            hoursText: DateTime.hours
            minutesText: DateTime.minutes
            meridiemText: root.showMeridiem ? DateTime.meridiem.toUpperCase() : ""
            colRule: theme.accent
            colDigits: theme.bare
        }
    }

    Component {
        id: outlineVariant

        ReliefClockOutline {
            vertical: root.vertical
            thickness: root.thickness
            hoursText: DateTime.hours
            minutesText: DateTime.minutes
            colSolid: theme.bare
            colHollow: theme.bareAccent
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
