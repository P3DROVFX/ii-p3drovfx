import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property string displayText: ""
    property string iconName: ""
    colBackground: Appearance.colors.colLayer2

    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: contentRow.implicitWidth
        implicitHeight: label.implicitHeight
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 0
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 5
                Layout.rightMargin: 4
                visible: root.iconName.length > 0
                iconSize: Appearance.font.pixelSize.large
                text: root.iconName
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                id: label
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: root.iconName.length > 0 ? 0 : 5
                text: root.displayText
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.hugeass
                text: "arrow_drop_down"
                color: Appearance.colors.colOnLayer2
            }
        }
    }
}
