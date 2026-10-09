import QtQuick
import qs.modules.common

/** A scroll track in the colours the switch chooses: primary tones when colourful, neutral when not. */
Rectangle {
    id: root

    readonly property real barLength: 96
    readonly property real barThickness: 10
    readonly property real thumbRatio: 0.45
    readonly property real thumbInset: 2
    readonly property real neutralThumbOpacity: 0.55

    property bool colorful: false

    implicitWidth: root.barLength
    implicitHeight: root.barThickness
    radius: height / 2
    color: root.colorful ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            margins: root.thumbInset
        }
        width: (root.width - root.thumbInset * 2) * root.thumbRatio
        radius: height / 2
        color: root.colorful ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
        opacity: root.colorful ? 1 : root.neutralThumbOpacity
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
