import qs.modules.ii.bar.popups.battery
import qs.modules.ii.bar.shared

// Bar popup shell. The body lives in BatteryPopupContent, shared with the
// akehono shelf, which hosts the same content in its in-window chipPopup slot
// instead of a separate popup window.
StyledPopup {
    id: root
    stickyHover: true

    contentItem: BatteryPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
    }
}