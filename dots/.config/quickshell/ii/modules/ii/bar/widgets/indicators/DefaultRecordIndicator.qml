pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Default record indicator — the bar's own idiom, not a design of its own.
 *
 * It paints no surface: the `BarGroup` chip around it is the surface, and the
 * group is highlighted while the capture is live, exactly as it is for every
 * other default widget that has an "on" state. That is why the content colour
 * is `onActivatedColor` (the bar hands it over) and not an error colour —
 * inside a filled primary chip, red would be a foreign body.
 *
 * The state lives in the icon; the seconds live in the rolling digits.
 */
Item {
    id: root

    property bool vertical: false
    property bool minimal: false
    property bool live: false
    property bool loading: false
    property bool paused: false
    property bool hovering: false
    property bool animateDigits: true
    property string timeText: "00:00"
    property string stateIcon: "videocam"
    property color colContent: Appearance.colors.colOnLayer1

    readonly property bool showTime: !root.minimal && !root.loading

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 6
    implicitHeight: root.vertical ? content.implicitHeight : Appearance.sizes.baseBarHeight

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: 5
        rowSpacing: 1

        MaterialSymbol {
            Layout.alignment: Qt.AlignCenter
            text: root.stateIcon
            iconSize: Appearance.font.pixelSize.large
            color: root.colContent
            // Outline, even while live: the chip behind it is already filled
            // when the capture is running, and a filled glyph inside a filled
            // chip is a blob at 17px. The other families fill theirs because
            // they sit on their own surface.
            fill: 0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Sanctioned rotation: it runs only while the portal request is
            // outstanding, and stops the moment the recorder actually starts.
            RotationAnimator on rotation {
                running: root.loading
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }

        RecordTimerText {
            Layout.alignment: Qt.AlignCenter
            visible: root.showTime
            value: root.timeText
            stacked: root.vertical
            stackSpacing: -3
            pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            colText: root.colContent
            fontFamily: Appearance.font.family.main
            weight: 600
            animate: root.animateDigits
            opacity: root.paused ? 0.6 : 1.0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
