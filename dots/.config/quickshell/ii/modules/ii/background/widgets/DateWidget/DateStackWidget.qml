import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Date Stack (1x1). The day of the month, tall and condensed, set on a big
 * primary cookie that morphs to a twelve-sided one under the pointer; the
 * weekday above, the month on a chip that overlaps the cookie's foot.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_date_stack"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_date_stack")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_date_stack ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool showShape: root.options?.showShape ?? true
    readonly property bool showWeekNumber: root.options?.showWeekNumber ?? true

    // -- Geometry (design units) --
    readonly property real designSize: 240
    readonly property real padding: 18
    readonly property real shapeSize: 158
    readonly property real dayFigureSize: 112
    readonly property real chipHeight: 36

    implicitWidth: root.designSize * root.contentScale
    implicitHeight: root.designSize * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        HoverHandler {
            id: hover
        }

        StyledRectangularShadow {
            target: card
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

            StyledText {
                id: weekday
                x: root.padding
                y: root.padding - 2
                width: parent.width - root.padding * 2 - (weekBadge.visible ? weekBadge.width + 8 : 0)
                text: cal.locale.toString(cal.today, "dddd")
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.variableAxes: ({ "wght": 650, "ROND": 100 })
                elide: Text.ElideRight
            }

            StyledText {
                id: weekBadge
                visible: root.showWeekNumber
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: weekday.verticalCenter
                text: Translation.tr("W%1").arg(cal.weekNumber(cal.today))
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1
            }

            MaterialShape {
                id: dayShape
                visible: root.showShape
                anchors.horizontalCenter: parent.horizontalCenter
                y: 46
                implicitSize: root.shapeSize
                shape: hover.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                color: WidgetColorScheme.accentColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: dayShape.verticalCenter
                anchors.verticalCenterOffset: -2
                text: cal.locale.toString(cal.today, "dd")
                color: root.showShape ? WidgetColorScheme.onAccentColor : WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: root.dayFigureSize
                font.variableAxes: ({ "wght": 820, "wdth": 28, "ROND": 100, "opsz": 144 })
                renderType: Text.QtRendering
            }

            // Month chip, overlapping the cookie's foot
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding - 4
                width: Math.min(chipRow.implicitWidth + 32, parent.width - root.padding * 2)
                height: root.chipHeight
                radius: Appearance.rounding.full
                color: WidgetColorScheme.pillFillColor

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 8

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cal.locale.toString(cal.today, "MMMM")
                        color: WidgetColorScheme.textColorOnPillFill
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cal.today.getFullYear()
                        color: WidgetColorScheme.textColorOnPillFill
                        opacity: 0.7
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }
}
