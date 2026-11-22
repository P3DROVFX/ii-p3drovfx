import QtQuick
import qs
import qs.modules.common
import qs.modules.ii.bar.shared
import qs.services

/**
 * The bar's notification center: the dashboard's notification list in a popup. Opens on
 * hover like every other bar popup, and stays while the pointer is inside it (sticky), so
 * the list can be scrolled and cleared. Opening it counts as reading what it shows.
 */
StyledPopup {
    id: root
    popupId: "notifications"
    stickyHover: true
    // Concentric with the notification groups inside: their radius plus the popup margin.
    popupRadius: Appearance.rounding.windowRounding + 10

    onOpenedChanged: {
        if (root.opened)
            Notifications.markAllRead();
    }

    contentItem: NotificationsPopupContent {}
}
