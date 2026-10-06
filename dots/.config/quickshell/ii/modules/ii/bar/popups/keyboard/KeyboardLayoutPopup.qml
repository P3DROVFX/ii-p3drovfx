import qs.modules.ii.bar.shared
import QtQuick

StyledPopup {
    id: root
    popupId: "keyboard"
    stickyHover: true

    contentItem: KeyboardLayoutPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
    }
}
