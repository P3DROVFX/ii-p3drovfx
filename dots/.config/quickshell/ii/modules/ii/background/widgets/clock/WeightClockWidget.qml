import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Weight Clock (1x1). Heavy hours stacked over the minutes, whose weight is
 * the hour's progress: a hairline at :00, as heavy as the hours by :59. The
 * axis eases on every minute instead of stepping. Weekday, day and month sit
 * stacked in monospace beside the figures.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_type_weight"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "clock_type_weight")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.clock_type_weight ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool weightFollowsMinutes: root.options?.weightFollowsMinutes ?? true

    // -- Geometry (design units) --
    readonly property real designSize: 240
    readonly property real padding: 18
    readonly property real figureSize: 118
    // Baseline-to-baseline of the two figure lines, tighter than the font's own.
    readonly property real lineStep: 96
    readonly property real heavyWeight: 900
    readonly property real lightWeight: 90
    readonly property real figureWidth: 62

    implicitWidth: root.designSize * root.contentScale
    implicitHeight: root.designSize * root.contentScale

    readonly property date now: DateTime.clock.date
    readonly property real hourProgress: root.now.getMinutes() / 59
    // Eased copy of the progress, so the weight glides into each new minute.
    property real easedProgress: root.hourProgress
    Behavior on easedProgress {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property real minuteWeight: root.weightFollowsMinutes
        ? root.lightWeight + (root.heavyWeight - root.lightWeight) * root.easedProgress
        : 260

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        TypeClockFrame {
            anchors.fill: parent
            showBackground: root.options?.showBackground ?? true
            textShadow: root.options?.textShadow ?? true

            Text {
                id: hoursText
                x: root.padding - 4
                y: root.padding - 30
                text: DateTime.hours
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: root.figureSize
                font.variableAxes: ({ "wght": root.heavyWeight, "wdth": root.figureWidth, "ROND": 100, "opsz": 144 })
                renderType: Text.QtRendering
            }

            Text {
                x: hoursText.x
                y: hoursText.y + root.lineStep
                text: DateTime.minutes
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: root.figureSize
                font.variableAxes: ({ "wght": Math.round(root.minuteWeight), "wdth": root.figureWidth, "ROND": 100, "opsz": 144 })
                renderType: Text.QtRendering
            }

            // Date, stacked in monospace down the right edge
            Column {
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding - 2
                spacing: 0

                Repeater {
                    model: [
                        Qt.locale().toString(root.now, "ddd").replace(".", "").toUpperCase(),
                        Qt.locale().toString(root.now, "dd"),
                        Qt.locale().toString(root.now, "MMM").replace(".", "").toUpperCase()
                    ]

                    delegate: StyledText {
                        required property string modelData
                        required property int index
                        anchors.right: parent.right
                        text: modelData
                        color: index === 1 ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: index === 1 ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.smaller
                        font.letterSpacing: 1.5
                    }
                }
            }

            StyledText {
                visible: DateTime.use12HourClock
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                y: root.padding
                text: DateTime.meridiem.toUpperCase()
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                font.letterSpacing: 1.5
            }
        }
    }
}
