import QtQuick
import QtQuick.Layouts

// The shell's ErrorShakeAnimation: a decaying sideways shake on Layout.leftMargin.
SequentialAnimation {
    id: root
    required property Item target
    property real distance: 30

    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance; duration: 50 }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance; duration: 50 }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance / 2; duration: 40 }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance / 2; duration: 40 }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: 0; duration: 30 }
}
