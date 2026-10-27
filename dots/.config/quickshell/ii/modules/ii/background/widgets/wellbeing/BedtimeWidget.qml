pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Bedtime (2x1): tonight and the week behind it, from the Clock's Bedtime.
 * On the left a crescent moon - a disc with a bite of the card taken out of
 * it, the bite growing into a full disc once bedtime arrives - over the
 * target time in a wide light cut and how long until it. On the right the
 * last seven nights hang from the target line: a bar up for each night that
 * ended early, down for each that ran late, faded when only estimated from
 * screen time.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_bedtime"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property date now: DateTime.clock.date
    readonly property bool enabled: BedtimeService.enabled
    readonly property string phase: BedtimeService.phaseAt(root.now)
    readonly property var target: BedtimeService.targetFor(BedtimeService.nightKey(root.now))
    readonly property int minutesToGo: Math.round((root.target.getTime() - root.now.getTime()) / 60000)
    readonly property var nights: {
        void BedtimeService.nights;
        void AppStats.history;
        return BedtimeService.history(7);
    }
    readonly property real maxSwing: 120

    readonly property string untilText: {
        if (!root.enabled)
            return Translation.tr("Bedtime is off");
        if (root.phase === "bedtime")
            return Translation.tr("Time to sleep");
        if (root.phase === "windDown")
            return Translation.tr("Wind down · %1").arg(ScreenTimeLimits.formatMinutes(Math.max(0, root.minutesToGo)));
        if (root.minutesToGo < 0 || root.minutesToGo > 16 * 60)
            return Translation.tr("Tonight");
        return Translation.tr("In %1").arg(ScreenTimeLimits.formatMinutes(root.minutesToGo));
    }

    onCardTapped: GlobalStates.openClockApp("bedtime")

    // ── Tonight ──
    Item {
        id: moon
        x: root.padding + 4
        y: root.padding + 4
        width: 78
        height: 78

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.phase === "bedtime" ? WidgetColorScheme.accentColor : WidgetColorScheme.innerShapeColor
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        // The bite: card colour over the disc. It slides off as bedtime comes.
        Rectangle {
            width: parent.width * 0.86
            height: width
            radius: width / 2
            x: root.phase === "bedtime" ? parent.width * 1.2 : root.phase === "windDown" ? parent.width * 0.5 : parent.width * 0.3
            y: -parent.height * 0.12
            color: root.cardColor
            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }

    StyledText {
        id: targetText
        x: root.padding - 2
        anchors.top: moon.bottom
        anchors.topMargin: 2
        text: root.enabled ? Qt.locale().toString(root.target, Config.options?.time?.format ?? "hh:mm") : "--:--"
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 54
        font.variableAxes: ({ "wght": 260, "wdth": 125, "ROND": 100 })
    }

    StyledText {
        x: root.padding
        anchors.top: targetText.bottom
        anchors.topMargin: -2
        width: 200
        elide: Text.ElideRight
        text: root.untilText
        color: root.phase === "none" ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.accentColor
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.normal
        font.variableAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
    }

    // ── The week ──
    Rectangle {
        id: chart
        x: 236
        y: root.padding
        width: root.designWidth - chart.x - root.padding
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.large
        color: WidgetColorScheme.pillBgColor

        readonly property real labelHeight: 22
        readonly property real targetY: (chart.height - chart.labelHeight) / 2 + 4
        readonly property real reach: chart.targetY - 16

        // The target line.
        Rectangle {
            x: 12
            y: chart.targetY - 1
            width: chart.width - 24
            height: 2
            radius: 1
            color: WidgetColorScheme.subtextColorOnBg
            opacity: 0.4
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            spacing: (chart.width - 24 - 7 * 18) / 6

            Repeater {
                model: root.nights

                delegate: Item {
                    id: night
                    required property var modelData
                    readonly property bool known: night.modelData.lastActive > 0 && night.modelData.applies !== false
                    readonly property real swing: Math.max(-1, Math.min(1, night.modelData.lateMinutes / root.maxSwing))
                    readonly property real barLength: Math.max(10, Math.abs(night.swing) * chart.reach)
                    width: 18
                    height: parent.height

                    Rectangle {
                        visible: night.known
                        width: parent.width
                        height: night.barLength
                        // Late hangs below the line, early stands above it.
                        y: night.swing > 0 ? chart.targetY - 5 : chart.targetY + 5 - height
                        radius: root.pill(width)
                        opacity: night.modelData.estimated ? 0.5 : 1
                        color: night.modelData.onTime ? WidgetColorScheme.accentColor : WidgetColorScheme.warningColor
                    }
                    Rectangle {
                        visible: !night.known
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: chart.targetY - height / 2
                        width: 8
                        height: 8
                        radius: 4
                        color: WidgetColorScheme.subtextColorOnBg
                        opacity: 0.4
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        // The evening the night belongs to, not the morning a late target falls on.
                        text: Qt.locale().toString(new Date(night.modelData.night + "T12:00:00"), "ddd").charAt(0).toUpperCase()
                        color: WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 11
                        font.variableAxes: ({ "wght": 650, "wdth": 110, "ROND": 100 })
                    }
                }
            }
        }
    }
}
