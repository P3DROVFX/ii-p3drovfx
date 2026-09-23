import qs
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
    /** Scales with the button, so a smaller host (the island) keeps the proportion. */
    property real iconSize: Math.round(button.size * 0.375)
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
    readonly property bool activeState: button.activeFocus || button.focus || button.isHovered || button.isPressed || button.keyboardDown

    property real animScale: button.shown ? 1.0 : 0.7
    property real animTranslateX: button.shown ? 0 : -35
    property real animOpacity: button.shown ? 1.0 : 0.0

    /**
     * Dynamic radius (grouped smart-radius) rounding: the single vertex sitting at the
     * grid's outer end takes the system's end radius - `min(h/2, large)`, the same rule
     * as a grouped run's ends - while every other vertex stays at the tight seam radius.
     * Each corner button has exactly one outer end; the hosts flag which one.
     */
    property real outerRadius: Math.min(button.size / 2, Appearance.rounding.large)
    property bool outerTopLeft: false
    property bool outerTopRight: false
    property bool outerBottomLeft: false
    property bool outerBottomRight: false

    /**
     * Inner (seam) radius while inactive: the tight corners connecting the grid.
     * The single outer end vertex takes `outerRadius`; the active button is a circle.
     */
    property real inactiveRadius: (Appearance.rounding.scale === 0) ? 0 : 4

    readonly property real innerCornerRadius: button.activeState ? button.size / 2 : button.inactiveRadius
    readonly property real outerCornerRadius: button.activeState ? button.size / 2 : button.outerRadius

    topLeftRadius: button.outerTopLeft ? button.outerCornerRadius : button.innerCornerRadius
    topRightRadius: button.outerTopRight ? button.outerCornerRadius : button.innerCornerRadius
    bottomLeftRadius: button.outerBottomLeft ? button.outerCornerRadius : button.innerCornerRadius
    bottomRightRadius: button.outerBottomRight ? button.outerCornerRadius : button.innerCornerRadius

    component RadiusBehavior: NumberAnimation {
        duration: 140
        easing.type: Easing.OutCubic
    }
    Behavior on topLeftRadius { RadiusBehavior { } }
    Behavior on topRightRadius { RadiusBehavior { } }
    Behavior on bottomLeftRadius { RadiusBehavior { } }
    Behavior on bottomRightRadius { RadiusBehavior { } }

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
        iconSize: button.iconSize
        text: buttonIcon
        fill: button.activeState ? 1 : 0
    }

    StyledToolTip {
        text: buttonText
    }
}
