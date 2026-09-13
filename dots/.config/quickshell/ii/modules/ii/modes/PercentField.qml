import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/** 0–100 field in the pill style; empty means "not set" (null). */
Rectangle {
    id: root
    property var value: null
    signal committed(var value)

    implicitWidth: 72
    implicitHeight: 36
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer3
    border.width: input.activeFocus ? 2 : 0
    border.color: Appearance.colors.colPrimary

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 2

        StyledTextInput {
            id: input
            Layout.fillWidth: true
            horizontalAlignment: TextInput.AlignRight
            verticalAlignment: TextInput.AlignVCenter
            text: root.value === null || root.value === undefined ? "" : String(root.value)
            color: Appearance.colors.colOnLayer3
            font.family: Appearance.font.family.numbers
            validator: IntValidator {
                bottom: 0
                top: 100
            }
            onEditingFinished: {
                const next = input.text.trim().length ? Number(input.text) : null;
                if (next !== root.value)
                    root.committed(next);
            }
        }

        StyledText {
            text: "%"
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
