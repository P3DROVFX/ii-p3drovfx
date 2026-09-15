import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Item {
    id: root
    property string icon: ""
    property bool on: false
    property bool shown: true
    property var panel: null
    property var altAction: null
    readonly property bool hovered: ripple.containsMouse
    signal clicked()

    visible: shown
    implicitWidth: 48
    implicitHeight: 48

    Squircle {
        anchors.fill: parent
        radius: 16
        smoothing: AkebonoAppearance.squircleSmoothing
        color: root.on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        Behavior on color { ColorAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 23
        fill: root.on ? 1 : 0
        color: root.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        Behavior on color { ColorAnimation { duration: 240 } }
    }
    RippleArea {
        id: ripple
        shapeRadius: 16
        rippleColor: root.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        onClicked: root.clicked()
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: if (root.altAction) root.altAction()
    }
}
