import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The primary start/pause control. Running, it is a wide rounded square; stopped, a
 * circle — the shape morph Material 3 Expressive uses to show a state, not a colour.
 */
RippleButton {
    id: root

    property bool running: false
    property real size: ClockStyle.fabSizeLarge
    property color colIdle: ClockStyle.colPrimary
    property color colIdleHover: ClockStyle.colPrimaryHover
    property color colIdleActive: ClockStyle.colPrimaryActive
    property color colOnIdle: ClockStyle.colOnPrimary
    property color colRunning: ClockStyle.colPrimaryContainer
    property color colRunningHover: ClockStyle.colPrimaryContainerHover
    property color colRunningActive: ClockStyle.colPrimaryContainerActive
    property color colOnRunning: ClockStyle.colOnPrimaryContainer

    implicitHeight: root.size
    implicitWidth: root.running ? root.size * 1.45 : root.size
    buttonRadius: root.running ? ClockStyle.radiusExtraLarge : root.size / 2
    buttonRadiusPressed: ClockStyle.radiusLarge
    colBackground: root.running ? root.colRunning : root.colIdle
    colBackgroundHover: root.running ? root.colRunningHover : root.colIdleHover
    colRipple: root.running ? root.colRunningActive : root.colIdleActive

    Behavior on implicitWidth {
        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
    }

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.running ? "pause" : "play_arrow"
            iconSize: root.size * 0.42
            fill: 1
            color: root.running ? root.colOnRunning : root.colOnIdle
            animateChange: !ClockStyle.reducedMotion
            animationDistanceY: 0
            animationDistanceX: root.size * 0.12
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
        }
    }
}
