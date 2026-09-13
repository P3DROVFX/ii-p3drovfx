import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "water_reminder"

    implicitWidth: 240
    implicitHeight: 240

    // Theme palette tokens from WidgetColorScheme (same usage as other utility widgets).
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    readonly property color onAccentColor: WidgetColorScheme.onAccentColor
    readonly property color innerShapeColor: WidgetColorScheme.innerShapeColor

    // Water accent: filled glasses and action button use the accent/on-accent pair.
    readonly property color glassFillColor: root.accentColor
    readonly property color glassCheckColor: root.onAccentColor
    readonly property color trackColor: root.innerShapeColor

    readonly property int dailyGoal: Math.max(1, Config.options.background.widgets.water_reminder.dailyGoal || 8)
    readonly property int filled: Math.max(0, Math.min(dailyGoal, WaterReminderService.glassesDrunk))
    readonly property int remaining: Math.max(0, dailyGoal - filled)
    readonly property bool goalReached: filled >= dailyGoal

    // Geometry — adaptive so any dailyGoal fits the 1x1 pill.
    readonly property real cardMargin: 16
    readonly property real pillW: root.width - cardMargin * 2
    readonly property real trackPadding: 4
    readonly property real overlapRatio: 0.65
    readonly property real circleDiam: Math.max(22, Math.min(42, (pillW - trackPadding * 2) / (1 + (dailyGoal - 1) * overlapRatio)))
    readonly property real circleStep: circleDiam * overlapRatio
    readonly property real dotDiam: 7
    readonly property real dotStartX: {
        if (filled === 0 && remaining === 1) return (pillW - dotDiam) / 2;
        if (filled === 0) return trackPadding;
        return trackPadding + (filled - 1) * circleStep + circleDiam + 10;
    }
    readonly property real dotStep: remaining > 1 ? (pillW - dotStartX - trackPadding - dotDiam) / (remaining - 1) : 0
    readonly property real pillH: circleDiam + trackPadding * 2

    StyledRectangularShadow {
        id: bgShadow
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? false
        layer.effect: InnerShadow {
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 8.0
            samples: 16
            horizontalOffset: 0
            verticalOffset: 1
            spread: 0.0
        }

        // ------- Progress track (top) -------
        Rectangle {
            id: pillTrack
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.cardMargin
            height: root.pillH
            radius: height / 2
            color: root.trackColor

            Item {
                id: pillContent
                anchors.fill: parent

                // Filled glasses distributed across the full track width, newest on top.
                Repeater {
                    model: root.filled
                    delegate: Item {
                        id: dp
                        required property int index

                        x: root.trackPadding + dp.index * root.circleStep
                        y: (pillContent.height - root.circleDiam) / 2
                        width: root.circleDiam
                        height: root.circleDiam
                        z: dp.index
                        opacity: 0.0
                        scale: 0.4

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: root.glassFillColor
                            border.color: root.cardBgColor
                            border.width: Math.max(1, Math.round(2 * Appearance.rounding.scale))
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: root.circleDiam * 0.60
                            fill: 1
                            color: root.glassCheckColor
                        }

                        SequentialAnimation {
                            running: true
                            ParallelAnimation {
                                NumberAnimation { target: dp; property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                                NumberAnimation { target: dp; property: "scale"; from: 0.4; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }

                // Remaining slots as small faded accent dots after the last filled glass.
                Repeater {
                    model: root.remaining
                    delegate: Item {
                        required property int index
                        x: root.dotStartX + index * root.dotStep
                        y: (pillContent.height - root.dotDiam) / 2
                        width: root.dotDiam
                        height: root.dotDiam

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: ColorUtils.applyAlpha(root.glassFillColor, 0.45)
                        }
                    }
                }
            }
        }

        // ------- Bottom text (left) -------
        ColumnLayout {
            id: bottomText
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            anchors.right: waterButton.left
            anchors.rightMargin: 10
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.goalReached
                      ? Translation.tr("Goal reached!")
                      : Translation.tr("%1 glasses").arg(String(root.remaining))
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
                color: root.textColorOnBg
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.goalReached
                      ? Translation.tr("Well done 💧")
                      : Translation.tr("left to goal")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
                color: root.subtextColorOnBg
                elide: Text.ElideRight
            }
        }

        // ------- Action button (bottom-right) -------
        RippleButton {
            id: waterButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.cardMargin
            width: 58
            height: 58
            rippleEnabled: true
            buttonRadius: Appearance.rounding.normal
            colBackground: root.accentColor
            colBackgroundHover: Qt.darker(root.accentColor, 1.08)
            colBackgroundActive: Qt.darker(root.accentColor, 1.14)
            colRipple: ColorUtils.applyAlpha(root.onAccentColor, 0.35)

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.goalReached ? "restart_alt" : "water_full"
                iconSize: 30
                fill: 1
                color: root.onAccentColor
            }

            onClicked: WaterReminderService.addGlass()
            altAction: () => WaterReminderService.addGlass()
        }
    }
}
