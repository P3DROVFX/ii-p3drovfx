pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Take a Break (1x1): how long you have been at the screen without a pause.
 * A session starts when you come back - from idle (AppStats' idle timeout) or
 * the lock screen - or when you press "I took a break". Five cells, one per
 * fifth of the break interval, fill as the session runs; past the interval
 * they turn to the warning colour and square their corners, and the number
 * says so. Nothing ticks here: the session is two timestamps and the shell's
 * minute clock.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_break"

    readonly property real padding: 18
    readonly property int cells: 5
    readonly property int interval: Math.max(10, Number(root.options?.breakEveryMinutes ?? 50))
    property real sessionStart: Date.now()
    readonly property bool away: AppStats.userIdle || GlobalStates.screenLocked
    readonly property int minutes: root.away ? 0 : Math.max(0, Math.floor((DateTime.clock.date.getTime() - root.sessionStart) / 60000))
    readonly property real progress: root.minutes / root.interval
    readonly property bool due: root.progress >= 1

    // Coming back from idle or the lock screen starts a fresh session.
    onAwayChanged: if (!root.away) root.sessionStart = Date.now()

    StyledText {
        id: minutesText
        x: root.padding - 3
        y: root.padding - 10
        text: String(root.minutes)
        color: root.due ? WidgetColorScheme.warningColor : WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 76
        font.variableAxes: ({ "wght": 760, "wdth": 60, "ROND": 100 })
    }
    StyledText {
        anchors.left: minutesText.right
        anchors.leftMargin: 6
        anchors.baseline: minutesText.baseline
        width: root.designWidth - x - root.padding
        wrapMode: Text.Wrap
        lineHeight: 0.9
        text: root.due ? Translation.tr("min · time for a break") : Translation.tr("min on screen")
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 13
        font.variableAxes: ({ "wght": 500, "wdth": 100, "slnt": -10, "ROND": 100 })
    }

    // ── The cells ──
    Row {
        id: cellRow
        x: root.padding
        y: 100
        spacing: 6

        Repeater {
            model: root.cells

            delegate: Rectangle {
                id: cell
                required property int index
                readonly property real fill: Math.max(0, Math.min(1, root.progress * root.cells - cell.index))
                width: (root.designWidth - root.padding * 2 - cellRow.spacing * (root.cells - 1)) / root.cells
                height: 78
                radius: root.due ? Appearance.rounding.verysmall : root.pill(width)
                color: WidgetColorScheme.pillBgColor
                clip: true
                Behavior on radius {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: parent.height * cell.fill
                    radius: parent.radius
                    color: root.due ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
                    Behavior on height {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    WidgetButton {
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding - 4
        width: root.designWidth - root.padding * 2
        height: 36
        symbol: "self_improvement"
        symbolSize: 18
        label: Translation.tr("I took a break")
        labelSize: Appearance.font.pixelSize.small
        colFill: root.due ? WidgetColorScheme.warningColor : WidgetColorScheme.pillBgColor
        colContent: root.due ? root.contentOn(WidgetColorScheme.warningColor) : WidgetColorScheme.textColorOnBg
        onClicked: if (root.actionsEnabled) root.sessionStart = Date.now()
    }
}
