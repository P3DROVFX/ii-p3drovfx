import QtQuick
import qs.modules.common

// Interpolate the scene position once. Preview offsets and slot changes must
// not animate independently, or dropping restarts the neighbours' movement.
Item {
    id: root
    property real layoutPosition: 0
    property real offset: 0
    property bool animate: false
    property bool tracking: false
    property bool settling: false
    property real position: layoutPosition + offset

    Behavior on position {
        enabled: root.animate && !root.tracking && !root.settling
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
}
