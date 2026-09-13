pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `nightLightTemp` action: a colour temperature in
 * kelvin. `row` is the ActionRow this form unfolds from; every change
 * goes back through it.
 */
ColumnLayout {
    id: tempCol
    required property var row

    spacing: 10

    RowLayout {
        spacing: 12

        StyledSlider {
            id: tempSlider
            Layout.fillWidth: true
            from: 1000
            to: 10000
            stepSize: 100
            value: Number(row.value) || 4000
            tooltipContent: `${Math.round(value)} K`
            onPressedChanged: {
                if (!pressed)
                    row.setValue(Math.round(value / 100) * 100);
            }
        }

        StyledText {
            text: `${Math.round(tempSlider.value)} K`
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer2
        }

        SmallButton {
            buttonText: Translation.tr("Use current")
            onClicked: row.setValue(Config.options.light.night.colorTemperature)
        }
    }

    FormHint {
        text: Translation.tr("Lower is warmer. Only visible while Night Light is on — pair it with the Night Light action")
    }
}
