import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Column {
    width: parent?.width ?? 0
    spacing: 0
    topPadding: 4

    DialogConfigSwitch {
        anchors { left: parent.left; right: parent.right }
        buttonIcon: "memory"
        text: Translation.tr("Hardware encoding")
        checked: Config.options.screenRecord.hardwareEncoding
        onCheckedChanged: Config.options.screenRecord.hardwareEncoding = checked
    }

    DialogConfigSwitch {
        anchors { left: parent.left; right: parent.right }
        buttonIcon: "mic"
        text: Translation.tr("Record audio")
        checked: Config.options.screenRecord.recordAudio
        onCheckedChanged: Config.options.screenRecord.recordAudio = checked
    }

    DialogConfigSpinBox {
        anchors { left: parent.left; right: parent.right; leftMargin: 11; rightMargin: 9 }
        icon: "high_quality"
        text: Translation.tr("Quality (QP)")
        from: 0
        to: 51
        value: Config.options.screenRecord.qualityQp
        onValueChanged: Config.options.screenRecord.qualityQp = value
    }

    DialogConfigSpinBox {
        anchors { left: parent.left; right: parent.right; leftMargin: 11; rightMargin: 9 }
        icon: "speed"
        text: Translation.tr("Max FPS")
        from: 10
        to: 144
        value: Config.options.screenRecord.maxFps
        onValueChanged: Config.options.screenRecord.maxFps = value
    }
}
