import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../../ii/bar/widgets/workspaces"

ShelfPill {
    id: root

    property real barHeight: 54
    property string style: "default"

    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (wsLoader.item?.implicitWidth ?? 0) || Math.round(root.pillHeight)
    implicitHeight: root.pillHeight

    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    Loader {
        id: wsLoader
        anchors.centerIn: parent
        height: root.height
        sourceComponent: root.style === "minimal" ? minimalComp
            : root.style === "expressive" ? expressiveComp
            : root.style === "dock" ? dockComp
            : root.style === "index" ? indexComp
            : defaultComp
    }

    Component {
        id: defaultComp
        Workspaces {}
    }

    Component {
        id: minimalComp
        MinimalWorkspaces {}
    }

    Component {
        id: expressiveComp
        ExpressiveWorkspaces {}
    }

    Component {
        id: dockComp
        DockWorkspaces {}
    }

    Component {
        id: indexComp
        IndexWorkspaces {}
    }
}