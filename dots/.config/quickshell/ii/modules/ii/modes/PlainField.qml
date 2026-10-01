import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick

/**
 * A single-line text field on the clock's filled field surface. The value is committed
 * on Enter or when focus leaves, never per keystroke, so a half typed command is not
 * saved (and applied) mid-way.
 *
 * `text` is what is typed right now; `clear()` empties it — for "type, then Add" rows
 * whose `value` never changes.
 */
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool monospace: false
    readonly property alias text: input.text

    signal committed(string value)

    function clear(): void {
        input.text = "";
    }

    implicitHeight: 40
    implicitWidth: 200
    radius: ClockStyle.radiusSmall
    color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    StyledTextInput {
        id: input
        anchors {
            fill: parent
            leftMargin: ClockStyle.gap + 2
            rightMargin: ClockStyle.gap + 2
        }
        verticalAlignment: TextInput.AlignVCenter
        text: root.value
        color: ClockStyle.colOnSurface
        clip: true
        selectByMouse: true
        font.pixelSize: ClockStyle.textNormal
        font.family: root.monospace ? Appearance.font.family.monospace : ClockStyle.fontMain
        onEditingFinished: {
            if (input.text !== root.value)
                root.committed(input.text);
        }

        StyledText {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !input.text.length
            text: root.placeholder
            elide: Text.ElideRight
            font.pixelSize: ClockStyle.textNormal
            color: Appearance.colors.colOnLayer1Inactive
        }
    }

    // The filled field's active indicator, kept inside the straight part of the edge.
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

        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }
    }
}
