import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * Click handling shared by the Sculpt utility buttons: left click runs the
 * action, right click its alternative when it has one, and a tooltip names it.
 */
MouseArea {
    id: root

    property string key: ""
    property UtilButtonActions actionSet

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | (root.actionSet?.altFor(root.key) ? Qt.RightButton : Qt.NoButton)
    onClicked: event => {
        if (event.button === Qt.RightButton) {
            const alt = root.actionSet.altFor(root.key);
            if (alt)
                alt();
            return;
        }
        root.actionSet.invoke(root.key);
    }

    StyledToolTip {
        text: root.actionSet?.tooltipFor(root.key) ?? ""
        requireOverlay: false
    }
}
