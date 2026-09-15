import qs.modules.ii.bar.popups.sports
import qs.modules.ii.bar.shared
import qs.modules.common

// Bar popup shell. The body lives in SportsPopupContent, shared with the
// akehono shelf, which hosts the same content in its in-window chipPopup slot
// instead of a separate popup window.
StyledPopup {
    id: root
    stickyHover: true
    popupRadius: Appearance.rounding.verylarge

    contentItem: SportsPopupContent {
        opened: root.opened
        popupOpenProgress: root.popupOpenProgress
    }
}