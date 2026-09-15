import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Rectangle {
    id: root

    property string icon: ""
    property bool big: false
    property bool active: false
    property int size: root.big ? 50 : 40
    property color foreground: Appearance.colors.colOnLayer0
    property color accent: Appearance.colors.colPrimary
    property color onAccent: Appearance.colors.colOnPrimary
    signal activated()

    readonly property bool filled: root.big || (ripple.containsMouse && root.enabled)
    readonly property color iconColor: {
        if (root.filled)
            return root.onAccent;
        if (root.active)
            return root.accent;
        return root.foreground;
    }

    implicitWidth: root.size
    implicitHeight: root.size
    radius: height * 0.3
    color: root.filled ? root.accent : Qt.alpha(root.accent, 0)
    opacity: root.enabled ? 1 : 0.4

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: Math.round(root.size * 0.53)
        fill: 1
        color: root.iconColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    RippleArea {
        id: ripple
        hoverOpacity: root.big ? 0.08 : 0
        rippleColor: root.filled ? root.onAccent : root.foreground
        onClicked: root.activated()
    }
}
