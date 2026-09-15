import qs.modules.ii.bar.shared
import "KeyboardLayoutPopupContent.qml"

// Bar popup shell. The body lives in KeyboardLayoutPopupContent, shared with
// the akehono shelf, which hosts the same content in its in-window chipPopup
// slot instead of a separate popup window.
StyledPopup {
    id: root
    stickyHover: true

    contentItem: KeyboardLayoutPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
    }
}