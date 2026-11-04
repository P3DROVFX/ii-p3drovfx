import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.overview
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * Real Gnome: the window held by a picker drag, drawn on one screen.
 *
 * The drag lives in one global (layout) rect, GlobalStates.realGnomeDragRect, so
 * every screen that has a surface for it draws its part: the picker's own
 * window on the overview's monitor, and the resident transition layer on the
 * others, so the window stays under the pointer as it crosses monitors.
 */
Item {
    id: root

    required property string screenName
    /** Screen coordinates -> parent coordinates. */
    property real offsetX: 0
    property real offsetY: 0
    property bool enabledHere: true

    readonly property var screenObj: Quickshell.screens.find(s => s.name === root.screenName) ?? null
    readonly property real screenX: root.screenObj ? root.screenObj.x : 0
    readonly property real screenY: root.screenObj ? root.screenObj.y : 0
    readonly property rect g: GlobalStates.realGnomeDragRect

    readonly property var heldToplevel: {
        const address = GlobalStates.realGnomeDraggedWindow;
        if (!root.enabledHere || address === "" || GlobalStates.realGnomeDragPhase === "")
            return null;
        return (ToplevelManager.toplevels.values ?? []).find(toplevel => {
            const raw = String(toplevel?.HyprlandToplevel?.address ?? "");
            const key = raw.toLowerCase().indexOf("0x") === 0 ? "0x" + raw.slice(2) : "0x" + raw;
            return key === address;
        }) ?? null;
    }

    visible: root.heldToplevel !== null && root.screenObj !== null
        && g.x < root.screenX + root.screenObj.width && g.x + g.width > root.screenX
        && g.y < root.screenY + root.screenObj.height && g.y + g.height > root.screenY
    x: g.x - root.screenX + root.offsetX
    y: g.y - root.screenY + root.offsetY
    width: g.width
    height: g.height
    opacity: GlobalStates.realGnomeDragOpacity

    StyledRectangularShadow {
        target: dragCapture
        blur: 28
        opacity: 0.45
        offset: Qt.vector2d(0, 6)
    }
    Item {
        id: dragCapture
        anchors.fill: parent
        layer.enabled: true
        layer.effect: OverviewRoundedMask {
            cornerRadius: Appearance.rounding.windowRounding
        }
        ScreencopyView {
            anchors.fill: parent
            captureSource: root.visible ? root.heldToplevel : null
            live: true
            paintCursor: false
        }
    }
}
