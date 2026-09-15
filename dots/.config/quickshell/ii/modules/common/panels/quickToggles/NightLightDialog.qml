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
        buttonIcon: "check"
        text: Translation.tr("Enable now")
        checked: Hyprsunset.temperatureActive
        onCheckedChanged: Hyprsunset.toggleTemperature(checked)
    }

    DialogConfigSwitch {
        anchors { left: parent.left; right: parent.right }
        buttonIcon: "night_sight_auto"
        text: Translation.tr("Automatic")
        checked: Config.options.light.night.automatic
        onCheckedChanged: Config.options.light.night.automatic = checked
    }

    WindowDialogSlider {
        anchors { left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
        text: Translation.tr("Intensity")
        from: 6500
        to: 1200
        stopIndicatorValues: [5000, to]
        value: Config.options.light.night.colorTemperature
        onMoved: Config.options.light.night.colorTemperature = value
        tooltipContent: `${Math.round(value)}K`
    }

    DialogConfigSwitch {
        anchors { left: parent.left; right: parent.right }
        buttonIcon: "filter"
        text: Translation.tr("Content adjustment")
        checked: Config.options.light.antiFlashbang.enable
        onCheckedChanged: Config.options.light.antiFlashbang.enable = checked
    }

    DialogConfigSwitch {
        anchors { left: parent.left; right: parent.right }
        buttonIcon: "light_mode"
        text: Translation.tr("Brightness adjustment")
        checked: Config.options.light.antiFlashbang.enableBrightness
        onCheckedChanged: Config.options.light.antiFlashbang.enableBrightness = checked
    }

    WindowDialogSlider {
        anchors { left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
        text: Translation.tr("Gamma")
        from: Hyprsunset.gammaLowerLimit / 100
        value: Hyprsunset.gamma / 100
        onMoved: Hyprsunset.setGamma(value * 100)
        tooltipContent: `${Math.round(value * 100)}%`
    }
}
