pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property int currentPageIndex: 0
    property int pageCount: WelcomePageRegistry.pages.length

    implicitHeight: Appearance.rounding.small
    Accessible.name: Translation.tr("Step %1 of %2")
        .arg(String(Math.max(0, root.currentPageIndex) + 1))
        .arg(String(root.pageCount))

    StyledProgressBar {
        anchors.fill: parent
        from: 0
        to: 1
        value: root.pageCount > 1
            ? root.currentPageIndex / (root.pageCount - 1)
            : 1
        valueBarHeight: 8
        valueBarGap: 0
        wavy: false
        highlightColor: Appearance.colors.colPrimary
        trackColor: Appearance.colors.colLayer2
    }
}
