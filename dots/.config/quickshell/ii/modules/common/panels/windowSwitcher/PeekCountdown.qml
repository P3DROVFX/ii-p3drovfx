import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The countdown to a peek, on the selected cover or card: a small ring that fills while the
 * selection holds still (WindowSwitcher.peekDelayMs), and stays full, with an eye, once the
 * peek is up. It only shows once the hold has lasted a moment, so a burst of Tabs flashes
 * nothing. Shared by the island and the panel.
 */
Item {
    id: badge

    property bool selected: false
    property real size: 26

    readonly property bool arming: badge.selected && WindowSwitcher.peekArming
    readonly property bool peeking: badge.selected && WindowSwitcher.peeking && WindowSwitcher.peekEntry !== null

    width: badge.size
    height: badge.size
    visible: badge.opacity > 0.001 && WindowSwitcher.peekDelayMs > 0
    opacity: badge.peeking || (badge.arming && badge.fill > 0.2) ? 1 : 0
    scale: badge.opacity > 0 ? 1 : 0.8
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }

    property real fill: 0
    NumberAnimation {
        id: fillAnimation
        target: badge
        property: "fill"
        from: 0
        to: 1
        duration: WindowSwitcher.peekDelayMs
        easing.type: Easing.Linear
    }
    onArmingChanged: {
        if (badge.arming) {
            fillAnimation.restart();
        } else {
            fillAnimation.stop();
            badge.fill = badge.peeking ? 1 : 0;
        }
    }
    onPeekingChanged: badge.fill = badge.peeking ? 1 : (badge.arming ? badge.fill : 0)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Appearance.colors.colLayer0
        opacity: 0.85
    }

    CircularProgress {
        anchors.fill: parent
        implicitSize: badge.size
        lineWidth: 2
        value: badge.fill
        enableAnimation: false
        gapAngle: 0
        colPrimary: Appearance.colors.colPrimary
        colSecondary: "transparent"
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "visibility"
        iconSize: Math.round(badge.size * 0.5)
        color: badge.peeking ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
    }
}
