import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/** Letterforms that round off while the switch turns on: the ROND axis follows `rounded`. */
StyledText {
    id: root

    readonly property real rondOff: 0
    readonly property real rondOn: 100
    readonly property real sampleSize: 30
    readonly property real weight: 560

    property bool rounded: false
    property real rond: root.rounded ? root.rondOn : root.rondOff
    Behavior on rond {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    text: "Aa Rg 123"
    font.family: Appearance.font.family.main
    font.pixelSize: Math.round(root.sampleSize)
    font.variableAxes: ({
        "wght": root.weight,
        "ROND": Math.max(root.rondOff, Math.min(root.rondOn, root.rond))
    })
}
