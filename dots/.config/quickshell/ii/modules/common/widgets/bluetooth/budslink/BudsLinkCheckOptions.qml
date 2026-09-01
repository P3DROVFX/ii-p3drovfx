pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property var checkButtons: []
    signal checkToggled(int checkIndex, bool state)

    Layout.fillWidth: true
    spacing: 8

    Repeater {
        model: root.checkButtons
        delegate: RowLayout {
            id: checkRow
            required property var modelData
            required property int index

            readonly property var checkObj: modelData

            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: checkRow.checkObj.title || ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
            }

            StyledSwitch {
                checked: Boolean(checkRow.checkObj.state)
                onToggled: {
                    root.checkToggled(checkRow.checkObj.index, checked);
                }
            }
        }
    }
}
