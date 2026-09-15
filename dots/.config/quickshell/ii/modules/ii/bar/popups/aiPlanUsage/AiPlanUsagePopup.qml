pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.bar.popups.aiPlanUsage
import qs.modules.ii.bar.shared
import qs.modules.common

// Bar popup shell. The body lives in AiPlanUsagePopupContent, shared with the
// akehono shelf, which hosts the same content in its in-window chipPopup slot
// instead of a separate popup window.
StyledPopup {
    id: root
    stickyHover: true
    popupRadius: Appearance.rounding.large

    contentItem: AiPlanUsagePopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
    }
}