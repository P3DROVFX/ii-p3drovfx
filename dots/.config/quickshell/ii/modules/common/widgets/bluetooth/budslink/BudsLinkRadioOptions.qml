pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property string title: ""
    property int currentState: 0
    property var options: []

    signal radioSelected(int state)

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
        spacing: 8

        Repeater {
            model: root.options && root.options.length > 0 ? root.options : [
                { index: 1, label: Translation.tr("Option 1") },
                { index: 2, label: Translation.tr("Option 2") }
            ]

            delegate: RippleButton {
                id: radioBtn
                required property var modelData
                required property int index

                readonly property var opt: modelData
                readonly property bool isSelected: root.currentState === opt.index

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                buttonRadius: Appearance.rounding.full

                colBackground: radioBtn.isSelected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSurfaceContainerHighest

                property color colText: radioBtn.isSelected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSurfaceVariant

                onClicked: {
                    root.radioSelected(radioBtn.opt.index);
                }

                StyledText {
                    anchors.centerIn: parent
                    text: radioBtn.opt.label || ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: radioBtn.isSelected ? Font.Bold : Font.Normal
                    color: radioBtn.colText
                }
            }
        }
    }
}
