pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property string title: ""
    property var buttons: []
    property int currentState: 1

    signal toggleSelected(int index)

    Layout.fillWidth: true
    spacing: 6

    StyledText {
        visible: root.title.length > 0
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colOnSurface
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.buttons
            delegate: RippleButton {
                id: btn
                required property var modelData
                required property int index

                readonly property var btnObj: modelData
                readonly property bool isSelected: root.currentState === (btnObj.index !== undefined ? btnObj.index : index + 1)

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                buttonRadius: Appearance.rounding.full

                colBackground: btn.isSelected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSurfaceContainerHighest

                property color colText: btn.isSelected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSurfaceVariant

                onClicked: {
                    root.toggleSelected(btnObj.index !== undefined ? btnObj.index : index + 1);
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        visible: Boolean(btn.btnObj.icon)
                        text: btn.btnObj.icon || "tune"
                        iconSize: 16
                        color: btn.colText
                    }

                    StyledText {
                        text: btn.btnObj.name || ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: btn.isSelected ? Font.Bold : Font.Normal
                        color: btn.colText
                    }
                }
            }
        }
    }
}
