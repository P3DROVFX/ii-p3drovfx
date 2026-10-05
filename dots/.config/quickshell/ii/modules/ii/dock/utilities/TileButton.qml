import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A control on a wide tile. Circle at rest, rounded square while `active`
 * (running, armed): the corner morph is the state. Tinted variants take the
 * card's content colour at the usual 8/16/24 % steps.
 */
Item {
    id: button

    property string symbol: ""
    property bool active: false
    property bool filled: false
    property color colContent: ClockStyle.colOnSurface
    property color colFilled: ClockStyle.colPrimary
    property color colOnFilled: ClockStyle.colOnPrimary
    property string tip: ""
    property real iconScale: 0.5
    signal clicked()

    readonly property bool pressed: area.pressed
    readonly property bool hovered: area.containsMouse

    implicitWidth: 32
    implicitHeight: 32
    // Dimmed explicitly: a preview disables its whole tile, and that must
    // not grey the controls out.
    property bool dimmed: false
    opacity: button.dimmed ? 0.38 : 1

    Rectangle {
        anchors.fill: parent
        radius: button.pressed ? Math.round(button.height * 0.24)
            : button.active ? Math.round(button.height * 0.32)
            : button.height / 2
        color: button.filled
            ? (button.hovered ? ColorUtils.mix(button.colFilled, button.colOnFilled, 0.88) : button.colFilled)
            : ColorUtils.applyAlpha(button.colContent, button.pressed ? 0.24 : button.hovered ? 0.16 : 0.08)
        Behavior on radius {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }

    TileSymbol {
        anchors.centerIn: parent
        text: button.symbol
        iconSize: Math.round(button.height * button.iconScale)
        fill: 1
        color: button.filled ? button.colOnFilled : button.colContent
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    StyledToolTip {
        text: button.tip
        extraVisibleCondition: button.tip.length > 0 && area.containsMouse
    }
}
