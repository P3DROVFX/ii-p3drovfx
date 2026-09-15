import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts

Item {
    id: button

    property string buttonIcon
    property string buttonText
    property bool keyboardDown: false
    property real size: 120
    readonly property bool hovered: ripple.containsMouse
    readonly property bool highlighted: button.activeFocus || button.keyboardDown || ripple.pressed || ripple.containsMouse
    signal clicked()

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    implicitWidth: size
    implicitHeight: size

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            button.keyboardDown = true;
            button.clicked();
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            button.keyboardDown = false;
            event.accepted = true;
        }
    }

    Squircle {
        id: ring
        anchors.fill: parent
        radius: button.highlighted ? 44 : 32
        smoothing: AkebonoAppearance.squircleSmoothing
        color: button.highlighted ? bg.color : Appearance.colors.colOutlineVariant

        Behavior on radius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Squircle {
        id: bg
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, ring.radius - 1.5)
        smoothing: AkebonoAppearance.squircleSmoothing
        color: button.keyboardDown ? Appearance.colors.colPrimaryActive
            : button.highlighted ? Appearance.colors.colPrimary
            : Appearance.colors.colLayer1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: button.buttonIcon
        iconSize: 45
        fill: button.highlighted ? 1 : 0
        color: button.highlighted ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    RippleArea {
        id: ripple
        shapeRadius: bg.radius
        squircleMask: true
        rippleColor: button.highlighted ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        onClicked: button.clicked()
    }

    StyledToolTip {
        text: button.buttonText
    }
}
