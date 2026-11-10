pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The scrolling script, drawn identically by the contracted strip and by the
 * card the hover grows the island into.
 *
 * The motion is not here: both faces translate by the session's `scrollY`,
 * owned by the injected `prompter` (the Teleprompter service, or the Settings
 * preview's demo session), so the script keeps its exact place across the
 * morph instead of each face running its own animation.
 *
 * The clip is the whole face, with no vertical margin: a resting script fills
 * the body line by line, and a scrolling one is cut by the body's own edges,
 * the way a teleprompter glass cuts it.
 *
 * Each face clamps the offset at *its own* bottom edge: the taller card shows
 * the script's last lines flush with it instead of scrolling past them into
 * blank space, and the two only ever disagree on the final viewportful.
 */
Item {
    id: root

    required property var prompter
    /** Horizontal breathing room inside the face. */
    property real padX: 18

    clip: true

    /** The full height of the wrapped script; the face reports it upstream. */
    readonly property real textHeight: script.height
    readonly property real lineHeightPx: root.prompter.lineHeightPx
    readonly property real offset: Math.min(root.prompter.scrollY,
        Math.max(0, root.prompter.contentHeight - root.height))

    Item {
        id: mover
        y: -root.offset
        anchors.left: parent.left
        anchors.right: parent.right

        // Mirror mode flips the script for a teleprompter glass rig; it reads
        // as a turn, not a cut.
        transform: Scale {
            xScale: root.prompter.mirror ? -1 : 1
            origin.x: mover.width / 2

            Behavior on xScale {
                enabled: !Appearance.reducedMotion
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        StyledText {
            id: script
            x: root.padX
            width: root.width - 2 * root.padX
            text: root.prompter.text
            wrapMode: Text.Wrap
            font.family: root.prompter.promptFontFamily
            font.pixelSize: root.prompter.fontSize
            font.weight: root.prompter.bold ? Font.Bold : Font.DemiBold
            font.variableAxes: ({
                "wght": root.prompter.bold ? 700 : 500
            })
            lineHeight: root.lineHeightPx
            lineHeightMode: Text.FixedHeight
            color: Appearance.colors.colOnSurface
            // A held script dims; still readable, visibly paused.
            opacity: root.prompter.paused ? 0.6 : 1

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(script)
            }
        }
    }
}
