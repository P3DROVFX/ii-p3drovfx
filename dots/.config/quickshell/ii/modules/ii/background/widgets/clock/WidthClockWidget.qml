import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Width Clock (2x1). The time on one line whose width axis trades sides as
 * the hour passes: the hours start wide and narrow down while the minutes
 * widen, so the colon drifts left through the hour. The line always fills the
 * card. Above it, the part of the day in italic and the date in monospace.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_type_width"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "clock_type_width")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.clock_type_width ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool widthFollowsHour: root.options?.widthFollowsHour ?? true
    readonly property bool showPartOfDay: root.options?.showPartOfDay ?? true

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 240
    readonly property real padding: 22
    readonly property real maxFigureSize: 168
    readonly property real measureSize: 100
    readonly property real figureWeight: 820
    readonly property real wideWidth: 151
    readonly property real narrowWidth: 25

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    readonly property date now: DateTime.clock.date
    readonly property real hourProgress: root.now.getMinutes() / 59
    property real easedProgress: root.hourProgress
    Behavior on easedProgress {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property real hoursWidth: root.widthFollowsHour
        ? root.wideWidth + (root.narrowWidth - root.wideWidth) * root.easedProgress : 125
    readonly property real minutesWidth: root.widthFollowsHour
        ? root.narrowWidth + (root.wideWidth - root.narrowWidth) * root.easedProgress : 60

    readonly property string partOfDay: {
        const h = root.now.getHours();
        if (h < 5)
            return Translation.tr("Night");
        if (h < 12)
            return Translation.tr("Morning");
        if (h < 18)
            return Translation.tr("Afternoon");
        if (h < 22)
            return Translation.tr("Evening");
        return Translation.tr("Night");
    }

    function axes(width, weight) {
        return { "wght": weight, "wdth": Math.round(width), "ROND": 100, "opsz": 144 };
    }

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        TypeClockFrame {
            id: frame
            anchors.fill: parent
            showBackground: root.options?.showBackground ?? true
            textShadow: root.options?.textShadow ?? true

            StyledText {
                id: dayWord
                visible: root.showPartOfDay
                x: root.padding
                y: root.padding - 4
                text: root.partOfDay
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.huge
                font.variableAxes: ({ "wght": 450, "wdth": 100, "slnt": -10, "ROND": 0 })
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: dayWord.verticalCenter
                text: Qt.locale().toString(root.now, "ddd dd MMM").replace(/\./g, "").toUpperCase()
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.5
            }

            // The line at a fixed size, transparent: its width sizes the real one.
            Row {
                id: measure
                opacity: 0
                Text { text: DateTime.hours; font.family: Appearance.font.family.main; font.pixelSize: root.measureSize; font.variableAxes: root.axes(root.hoursWidth, root.figureWeight) }
                Text { text: ":"; font.family: Appearance.font.family.main; font.pixelSize: root.measureSize; font.variableAxes: root.axes(60, 600) }
                Text { text: DateTime.minutes; font.family: Appearance.font.family.main; font.pixelSize: root.measureSize; font.variableAxes: root.axes(root.minutesWidth, root.figureWeight) }
            }

            Row {
                id: timeRow
                readonly property real meridiemWidth: meridiem.visible ? meridiem.implicitWidth + 8 : 0
                readonly property real fitSize: Math.floor(Math.min(root.maxFigureSize,
                    root.measureSize * (frame.width - root.padding * 2 - timeRow.meridiemWidth) / Math.max(1, measure.implicitWidth)))
                x: root.padding - 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -Math.round(timeRow.fitSize * 0.16)

                Text {
                    id: hoursText
                    text: DateTime.hours
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: timeRow.fitSize
                    font.variableAxes: root.axes(root.hoursWidth, root.figureWeight)
                    renderType: Text.QtRendering
                }
                Text {
                    text: ":"
                    color: WidgetColorScheme.accentColor
                    font.family: Appearance.font.family.main
                    font.pixelSize: timeRow.fitSize
                    font.variableAxes: root.axes(60, 600)
                    renderType: Text.QtRendering
                }
                Text {
                    text: DateTime.minutes
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: timeRow.fitSize
                    font.variableAxes: root.axes(root.minutesWidth, root.figureWeight)
                    renderType: Text.QtRendering
                }
                StyledText {
                    id: meridiem
                    visible: DateTime.use12HourClock
                    anchors.baseline: hoursText.baseline
                    leftPadding: 8
                    text: DateTime.meridiem.toUpperCase()
                    color: WidgetColorScheme.accentColor
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.letterSpacing: 1.5
                }
            }
        }
    }
}
