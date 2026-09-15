import qs
import qs.modules.ii.bar.popups.bluetooth
import qs.modules.ii.bar.shared

// Bar popup shell. The body lives in ExpressiveBluetoothDevicesPopupContent,
// shared with the akehono shelf, which hosts the same content in its in-window
// chipPopup slot instead of a separate popup window.
StyledPopup {
    id: root
    stickyHover: true

    readonly property bool notifIsLeft: (Config.options.notifications.position ?? "top_right").endsWith("left")
    readonly property bool notifIsRight: (Config.options.notifications.position ?? "top_right").endsWith("right")
    readonly property bool sidebarOccludesPopup:
        (root.notifIsLeft && GlobalStates.effectiveLeftOpen)
        || (root.notifIsRight && GlobalStates.effectiveRightOpen)

    active: !sidebarOccludesPopup && (_computedActive || _isClosing)

    contentItem: ExpressiveBluetoothDevicesPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
        active: root.active
        hoverTarget: root.hoverTarget
    }
}