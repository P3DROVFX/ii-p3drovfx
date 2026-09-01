import QtQuick
import qs.modules.common.widgets

/**
 * Stand-in for a hub tab whose controls are not built yet.
 *
 * The tab exists in the bar - and in the settings search index - from the first step, so the
 * page's shape never changes underneath the user as the tabs fill in.
 */
Item {
    id: root
    anchors.fill: parent

    property alias icon: placeholder.icon
    property alias title: placeholder.title
    property alias description: placeholder.description
    /// The settings window pushes a restored scroll position onto whatever page it loaded.
    /// There is nothing to scroll here; owning the property keeps that write from failing.
    property real contentY: 0

    PagePlaceholder {
        id: placeholder
        animateIconOnShow: true
    }
}
