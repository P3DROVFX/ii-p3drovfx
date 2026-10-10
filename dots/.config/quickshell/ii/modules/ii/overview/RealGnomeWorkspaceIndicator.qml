import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Real Gnome: GNOME Shell's workspace indicator under the plane.
 *
 * One dot per workspace in use in the current group of the grid, plus one empty
 * workspace after them, as GNOME's dynamic workspaces show; the active one is a
 * longer pill that slides to the new workspace with the strip. A dot switches to
 * its workspace (the overview stays open and slides there).
 */
Item {
    id: root

    required property string screenName
    property bool shown: false

    // At 8 px a fully rounded dot is only eight rows of pixels and reads as a
    // rounded square; 10 px is the smallest size that looks round on screen.
    readonly property real dotSize: 10
    readonly property real activeWidth: 32
    readonly property real spacing: 8

    readonly property var monitor: Hyprland.monitors.values.find(m => m.name === root.screenName) ?? null
    readonly property int activeWs: Math.max(1, root.monitor?.activeWorkspace?.id ?? 1)
    readonly property int perGroup: Math.max(1, (Config.options.overview.rows ?? 2) * (Config.options.overview.columns ?? 5))
    readonly property int groupStart: Math.floor((root.activeWs - 1) / root.perGroup) * root.perGroup + 1
    readonly property int highestUsed: {
        const end = root.groupStart + root.perGroup - 1;
        let highest = 0;
        for (const win of HyprlandData.windowList ?? []) {
            const id = Number(win?.workspace?.id ?? 0);
            if (id >= root.groupStart && id <= end && id > highest)
                highest = id;
        }
        return highest;
    }
    // In use, the active one, and one empty workspace after them.
    readonly property int count: Math.max(1, Math.min(root.perGroup,
        Math.max(root.highestUsed, root.activeWs) - root.groupStart + 2))
    readonly property int activeIndex: root.activeWs - root.groupStart

    implicitWidth: root.count * root.dotSize + (root.activeWidth - root.dotSize) + (root.count - 1) * root.spacing
    implicitHeight: 24

    opacity: root.shown ? 1 : 0
    visible: opacity > 0.001
    enabled: root.shown
    Behavior on opacity {
        NumberAnimation {
            duration: Math.round((root.shown ? 220 : 120) * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    // The pill: moves on the same curve and speed as the workspace slide.
    Rectangle {
        id: activePill
        x: root.activeIndex * (root.dotSize + root.spacing)
        anchors.verticalCenter: parent.verticalCenter
        width: root.activeWidth
        height: root.dotSize
        radius: Appearance.rounding.full
        antialiasing: true
        color: Appearance.m3colors.m3onSurface
        Behavior on x {
            NumberAnimation {
                duration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                    * 100 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
            }
        }
    }

    Repeater {
        model: root.count

        delegate: Item {
            id: dot
            required property int index
            readonly property int workspaceId: root.groupStart + dot.index
            readonly property bool active: dot.index === root.activeIndex
            // Dots after the active one sit past the pill.
            x: dot.index * (root.dotSize + root.spacing) + (dot.index > root.activeIndex ? root.activeWidth - root.dotSize : 0)
            width: dot.active ? root.activeWidth : root.dotSize
            height: root.height
            Behavior on x {
                NumberAnimation {
                    duration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                        * 100 * Appearance.animMultiplier)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.dotSize
                height: root.dotSize
                radius: Appearance.rounding.full
                antialiasing: true
                color: Appearance.m3colors.m3onSurface
                visible: !dot.active
                opacity: dotHover.hovered ? 0.85 : 0.45
                scale: dotHover.hovered ? 1.25 : 1
                Behavior on opacity {
                    NumberAnimation { duration: Math.round(150 * Appearance.animMultiplier) }
                }
                Behavior on scale {
                    NumberAnimation { duration: Math.round(150 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
                }
            }

            HoverHandler {
                id: dotHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                // A generous target around a small dot.
                margin: 6
                onTapped: {
                    if (!dot.active)
                        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${dot.workspaceId} })`);
                }
            }
        }
    }
}
