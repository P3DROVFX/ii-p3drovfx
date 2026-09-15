import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    contentHeight: content.implicitHeight
    clip: true

    Column {
        id: content
        width: root.width
        spacing: 0
        topPadding: 4

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "animation"
            text: Translation.tr("Disable animations")
            checked: Config.options.gameMode.disableAnimations
            onCheckedChanged: Config.options.gameMode.disableAnimations = checked
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "shadow"
            text: Translation.tr("Disable shadows")
            checked: Config.options.gameMode.disableShadows
            onCheckedChanged: Config.options.gameMode.disableShadows = checked
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "blur_off"
            text: Translation.tr("Disable blur")
            checked: Config.options.gameMode.disableBlur
            onCheckedChanged: Config.options.gameMode.disableBlur = checked
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "fullscreen"
            text: Translation.tr("Remove gaps")
            checked: Config.options.gameMode.removeGaps
            onCheckedChanged: Config.options.gameMode.removeGaps = checked
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "border_style"
            text: Translation.tr("Set border size")
            checked: Config.options.gameMode.setBorderSize
            onCheckedChanged: Config.options.gameMode.setBorderSize = checked
        }

        DialogConfigSpinBox {
            anchors { left: parent.left; right: parent.right; leftMargin: 11; rightMargin: 9 }
            icon: "border_outer"
            text: Translation.tr("Border size (px)")
            from: 0
            to: 10
            value: Config.options.gameMode.borderSize
            onValueChanged: Config.options.gameMode.borderSize = value
            enabled: Config.options.gameMode.setBorderSize
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "rounded_corner"
            text: Translation.tr("Disable rounding")
            checked: Config.options.gameMode.disableRounding
            onCheckedChanged: Config.options.gameMode.disableRounding = checked
        }

        DialogConfigSwitch {
            anchors { left: parent.left; right: parent.right }
            buttonIcon: "speed"
            text: Translation.tr("Enable tearing")
            checked: Config.options.gameMode.enableTearing
            onCheckedChanged: Config.options.gameMode.enableTearing = checked
        }
    }
}
