import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/** 0–100 on the clock's filled field surface; empty means "not set" (null). */
Rectangle {
    id: root

    property var value: null

    signal committed(var value)

    implicitWidth: 80
    implicitHeight: 40
    radius: ClockStyle.radiusSmall
    color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.gap - 2
            rightMargin: ClockStyle.gap - 2
        }
        spacing: 2

        StyledTextInput {
            id: input
            Layout.fillWidth: true
            horizontalAlignment: TextInput.AlignRight
            verticalAlignment: TextInput.AlignVCenter
            text: root.value === null || root.value === undefined ? "" : String(root.value)
            color: ClockStyle.colOnSurface
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: ClockStyle.textLarge + 1
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
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colSubtext
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: root.radius / 2
            rightMargin: root.radius / 2
        }
        height: 2
        radius: 1
        color: ClockStyle.colPrimary
        opacity: input.activeFocus ? 1 : 0
    }
}
