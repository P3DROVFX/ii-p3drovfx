import qs.modules.ii.bar.popups.activeWindow
import qs.modules.ii.bar.shared
import QtQuick

// Bar popup shell. The body lives in ActiveWindowPopupContent, shared with
// the akehono shelf, which hosts the same content in its in-window chipPopup
// slot instead of a separate popup window.
StyledPopup {
    id: root

    property Item targetItem
    property string appClassText
    property string appTitleText
    property string activeWindowAddress
    property var monitor
    property int popupWidth: 350
    property int maxPopupWidth: 600

    hoverTarget: targetItem
    stickyHover: true

    contentItem: ActiveWindowPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
        appClassText: root.appClassText
        appTitleText: root.appTitleText
        activeWindowAddress: root.activeWindowAddress
        monitor: root.monitor
        popupWidth: root.popupWidth
        maxPopupWidth: root.maxPopupWidth
    }
}