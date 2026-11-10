import QtQuick

/**
 * Covers a preview so the real dock items under it take no click, hover or wheel —
 * but hands the wheel on to the page's StyledFlickable, so the page still scrolls
 * with the pointer over a preview. Clicks go to `clicked` for whoever wants them.
 */
MouseArea {
    id: root

    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true

    onWheel: wheel => {
        let page = root.parent;
        while (page && typeof page.scrollByWheel !== "function")
            page = page.parent;
        if (page && page.interactive && page.canScrollVertically)
            page.scrollByWheel(wheel);
        wheel.accepted = true;
    }
}
