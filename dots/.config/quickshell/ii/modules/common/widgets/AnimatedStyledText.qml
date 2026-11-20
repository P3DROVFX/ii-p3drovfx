import QtQuick

/**
 * A StyledText that slides and fades to its new value while `animateChange` is
 * on. The machinery lives here, not in StyledText: a Behavior, its animation and
 * the Translate cost ~7 KB per instance, and only a few dozen of the ~1300 texts
 * the shell builds ever animate.
 */
StyledText {
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
