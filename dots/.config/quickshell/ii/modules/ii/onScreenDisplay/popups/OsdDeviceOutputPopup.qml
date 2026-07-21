import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    property real contentHeight: 460

    contentItem: Item {
        implicitWidth: 320
        implicitHeight: root.contentHeight

        StyledFlickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: deviceColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: deviceColumn
                width: parent.width
                spacing: 8

                Repeater {
                    model: Audio.outputDevices
                    delegate: OsdDeviceOutputItem {
                        required property var modelData
                        node: modelData
                    }
                }
            }
        }
    }
}
