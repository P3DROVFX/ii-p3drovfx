import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property int index

    property real idx1: index
    property real idx2: index
    property int idx1Duration: 100
    property int idx2Duration: 300
    property int easingType: Easing.OutSine
    property real easingOvershoot: 1.70158
    property list<real> bezierCurve: []

    Behavior on idx1 {
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: root.easingType
            easing.overshoot: root.easingType === Easing.OutBack || root.easingType === Easing.InOutBack || root.easingType === Easing.InBack ? root.easingOvershoot : 0
            easing.bezierCurve: root.bezierCurve
        }
    }
    Behavior on idx2 {
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: root.easingType
            easing.overshoot: root.easingType === Easing.OutBack || root.easingType === Easing.InOutBack || root.easingType === Easing.InBack ? root.easingOvershoot : 0
            easing.bezierCurve: root.bezierCurve
        }
    }
}
