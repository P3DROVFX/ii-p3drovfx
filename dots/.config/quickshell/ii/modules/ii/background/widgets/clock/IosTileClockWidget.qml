pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "RoundedRectRay.js" as Ray

// iOS small-widget clock: a card with condensed heavy digits and a minute
// track that follows the card's rounded outline instead of a circle.
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_ios_tile"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    readonly property var opts: Config.options.background.widgets.clock_ios_tile
    readonly property bool showTicks: opts?.showTicks ?? true
    readonly property real contentScale: (opts?.widgetSize ?? 100) / 100.0
    readonly property real designSize: 240
    implicitWidth: designSize * contentScale
    implicitHeight: designSize * contentScale

    // -- Colors (WidgetColorScheme) --
    property color colCardBg: WidgetColorScheme.cardBgColor
    property color colText: WidgetColorScheme.textColorOnBg
    property color colTickMinor: WidgetColorScheme.subtextColorOnBg

    // -- Typography --
    // The condensed heavy look comes from the font's own width axis.
    readonly property var digitsAxes: ({ "wdth": 40, "wght": 800 })
    readonly property string timeString: DateTime.hours + ":" + DateTime.minutes
    readonly property real digitsMaxPixelSize: 120
    readonly property real referencePixelSize: 100
    // Share of the card the digits may span, leaving room for the track.
    readonly property real digitsWidthShare: showTicks ? 0.66 : 0.8
    readonly property real digitsPixelSize: Math.min(digitsMaxPixelSize,
        referencePixelSize * designSize * digitsWidthShare / Math.max(1, digitsMetrics.advanceWidth))

    TextMetrics {
        id: digitsMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: root.referencePixelSize
        font.variableAxes: root.digitsAxes
        font.features: { "tnum": 1 }
        text: root.timeString
    }

    // -- Minute track (design units) --
    readonly property real tickInset: 12
    readonly property real tickMajorLength: 16
    readonly property real tickMinorLength: 10
    readonly property real tickMajorWidth: 4
    readonly property real tickMinorWidth: 2

    StyledDropShadow {
        target: card
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.verylarge
            color: WidgetColorScheme.tintBackground(root.colCardBg)

            Repeater {
                model: root.showTicks ? 60 : 0

                Rectangle {
                    required property int index
                    readonly property bool major: index % 5 === 0
                    readonly property real angle: index * 6
                    readonly property real reach: Ray.distance(angle, root.designSize / 2 - root.tickInset, card.radius - root.tickInset)
                    readonly property real centreDist: reach - height / 2

                    width: major ? root.tickMajorWidth : root.tickMinorWidth
                    height: major ? root.tickMajorLength : root.tickMinorLength
                    radius: width / 2
                    antialiasing: true
                    color: major ? root.colText : root.colTickMinor
                    x: root.designSize / 2 + Math.sin(angle * Math.PI / 180) * centreDist - width / 2
                    y: root.designSize / 2 - Math.cos(angle * Math.PI / 180) * centreDist - height / 2
                    rotation: angle
                }
            }

            StyledText {
                anchors.centerIn: parent
                text: root.timeString
                color: root.colText
                font.family: Appearance.font.family.main
                font.pixelSize: root.digitsPixelSize
                font.variableAxes: root.digitsAxes
                font.features: { "tnum": 1 }
            }
        }
    }
}
