pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.ii.dynamicIsland.core
import "../activities/teleprompter"

/**
 * The contracted teleprompter: the user's script crossing the island in the
 * configured number of lines, in the reading face, bold.
 *
 * The island's height for this face is arithmetic the service owns — exactly
 * lines × fixed line height, clip edge to edge — published as the source's
 * `sizeOverride`, so the user's 1-to-4 lines choice resizes the island live.
 * This face only has to draw inside the box and report how tall the wrapped
 * script came out; the scroll extent (all there is to travel) is the difference.
 *
 * The reading state is said by two things only: the progress hairline along
 * the top edge (warning colour while paused, full when the script is read)
 * and the countdown owning the face before the scroll starts. Nothing else
 * decorates it — a prompter is a surface to read, not to look at.
 *
 * The face is also a control: a click holds and resumes the reading, and the
 * wheel travels the script by hand — unless the island is in click-to-expand,
 * where the click belongs to the surface. The hover still grows the island
 * into the wider card with the full controls; none of it opens the dashboard,
 * which is what the descriptor's `bodyClickOpensDashboard: false` and the
 * expanded presentation together guarantee.
 */
Item {
    id: root
    anchors.fill: parent

    /** Injectable: the Settings preview drives this same face with a demo session. */
    property var prompter: Teleprompter
    property bool isPreview: false

    // The reading window is the whole face: the clip has no vertical margin,
    // so the body's own edges cut the scrolling lines.
    Item {
        id: viewport
        anchors.fill: parent

        TeleprompterText {
            id: script
            anchors.fill: parent
            prompter: root.prompter
        }
    }

    /** The script lays out a turn later; every change re-measures the extent. */
    function syncLayout() {
        root.prompter.reportLayout(script.textHeight, viewport.height);
    }
    Connections {
        target: script
        function onTextHeightChanged() {
            root.syncLayout();
        }
    }
    onHeightChanged: root.syncLayout()
    Component.onCompleted: root.syncLayout()

    // ── Progress: the hairline along the top edge ───────────────────────────
    // Full-bleed: it is the state of the whole face, not a widget inside it.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 3
        visible: root.prompter.showProgress && root.prompter.running
        color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.14)

        Rectangle {
            height: parent.height
            width: parent.width * root.prompter.progress
            color: root.prompter.paused ? Appearance.colors.colWarning : Appearance.colors.colPrimary

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // ── The countdown owns the face ─────────────────────────────────────────
    // The number is the thing to read; the script behind it is dimmed to a hint
    // of what is coming.
    Rectangle {
        anchors.fill: parent
        visible: root.prompter.phase === "countdown"
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.88)

        StyledText {
            anchors.centerIn: parent
            text: root.prompter.countdownLeft
            font.family: Appearance.font.family.numbers
            font.pixelSize: Math.max(14, Math.round(root.height * 0.62))
            font.weight: Font.Bold
            font.variableAxes: ({
                "wght": 760
            })
            color: Appearance.colors.colPrimary
        }
    }

    // ── The face as a control ───────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        // Under click-to-expand the click belongs to the surface: it is how the
        // card with the real controls opens.
        enabled: !IslandPolicy.clickToExpand
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.prompter.togglePause()
    }

    WheelHandler {
        // Sign convention: wheel down (negative angleDelta) travels forward.
        // Touchpads report pixel deltas; mice report eighths of a line.
        onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 4;
            root.prompter.nudge(-delta);
        }
    }
}
