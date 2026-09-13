pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string controlKind: ""
    property var controlValue: null
    property var onToggled: null
    property real rowHeight: 52

    implicitHeight: rowHeight

    StyledSwitch {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.controlKind === "switch"
        checked: Boolean(root.controlValue)
        onCheckedChanged: {
            if (typeof root.onToggled === "function")
                root.onToggled(checked);
        }
    }
}
