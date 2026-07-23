import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string buttonIcon
    property string buttonText
    property bool keyboardDown: false
    property real size: 120
    property int animIndex: 0
    property bool shown: false

    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            if (hovered) {
                button.forceActiveFocus();
            }
        }
    }

    readonly property bool isHovered: hoverHandler.hovered || button.hovered
    readonly property bool activeState: button.focus || button.isHovered || button.isPressed || button.keyboardDown

    property real animScale: button.shown ? 1.0 : 0.7
    property real animTranslateX: button.shown ? 0 : -35
    property real animOpacity: button.shown ? 1.0 : 0.0

    buttonRadius: button.activeState ? size / 2 : Appearance.rounding.verylarge
    buttonEffectiveRadius: button.down ? button.buttonRadiusPressed : button.buttonRadius

    Behavior on buttonEffectiveRadius {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    colBackground: button.keyboardDown ? Appearance.colors.colSecondaryContainerActive : 
        button.activeState ? Appearance.colors.colPrimary : 
        Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colPrimary
    colRipple: Appearance.colors.colPrimaryActive
    property color colText: button.activeState ?
        Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    background.implicitHeight: size
    background.implicitWidth: size

    scale: (button.down ? 0.94 : (button.activeState ? 1.04 : 1.0)) * animScale

    transform: Translate {
        x: button.animTranslateX
    }

    opacity: animOpacity

    Behavior on animScale {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Behavior on animTranslateX {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    Behavior on animOpacity {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: cascadeTimer
        interval: animIndex * 35
        repeat: false
        onTriggered: {
            button.shown = true;
        }
    }

    function animateIn() {
        button.shown = false;
        cascadeTimer.restart();
    }

    function animateOut() {
        cascadeTimer.stop();
        button.shown = false;
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true;
            button.clicked();
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false;
            event.accepted = true;
        }
    }

    contentItem: MaterialSymbol {
        id: icon
        anchors.fill: parent
        color: button.colText
        horizontalAlignment: Text.AlignHCenter
        iconSize: 45
        text: buttonIcon
    }

    StyledToolTip {
        text: buttonText
    }
}
