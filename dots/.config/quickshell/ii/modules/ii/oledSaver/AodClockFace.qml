import QtQuick
import qs
import qs.modules.common

/**
 * The Always On Display's own clock, drawn instead of the lock's widgets when
 * `oledSaver.clockStyle` names one of the faces. Shared by the desktop overlay
 * (OledSaver) and the lock (LockSurface); the anti burn-in shift is applied here,
 * so every face gets it.
 *
 * Loaded synchronously: an async Loader swapping sources fast crashes qs.
 */
Item {
    id: root

    property string style: Config.options.oledSaver.clockStyle ?? "widgets"
    /// False while nothing of the face is on screen: the faces stop their clocks.
    property bool running: true

    Loader {
        id: faceLoader
        width: root.width
        height: root.height
        x: GlobalStates.aodBurnInShiftX
        y: GlobalStates.aodBurnInShiftY
        Behavior on x {
            animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(faceLoader)
        }
        Behavior on y {
            animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(faceLoader)
        }

        sourceComponent: root.style === "flip" ? flipFace
            : root.style === "dial" ? dialFace
            : root.style === "expressive" ? expressiveFace
            : root.style === "dots" ? dotsFace
            : root.style === "analog" ? analogFace
            : root.style === "info" ? infoFace
            : null
    }

    Component {
        id: flipFace
        AodFlipClock {
            running: root.running
        }
    }
    Component {
        id: dialFace
        AodDialClock {
            running: root.running
        }
    }
    Component {
        id: expressiveFace
        AodExpressiveClock {
            running: root.running
        }
    }
    Component {
        id: dotsFace
        AodDotMatrixClock {
            running: root.running
        }
    }
    Component {
        id: analogFace
        AodShapeAnalogClock {
            running: root.running
        }
    }
    Component {
        id: infoFace
        AodInfoClock {
            running: root.running
        }
    }
}
