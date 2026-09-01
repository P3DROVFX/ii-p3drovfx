import QtQuick

NumberAnimation {
    required property var animationSpec

    duration: animationSpec.duration
    easing.type: animationSpec.type
    easing.bezierCurve: animationSpec.bezierCurve
}
