import QtQuick

/**
 * A MaterialSymbol that slides and fades to its new glyph while `animateChange`
 * is on (see AnimatedStyledText for why this is not part of the base type).
 */
MaterialSymbol {
    id: root

    Behavior on text {
        enabled: root.animateChange
        TextChangeAnimation {
            host: root
            distanceX: root.animationDistanceX
            distanceY: root.animationDistanceY
        }
    }
}
