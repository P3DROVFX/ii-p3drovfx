import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: false

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather Service")

        ConfigSwitch {
            buttonIcon: "assistant_navigation"
            text: Translation.tr("Enable GPS location")
            checked: Config.options.bar.weather.enableGPS
            onCheckedChanged: {
                Config.options.bar.weather.enableGPS = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "thermometer"
            text: Translation.tr("Fahrenheit unit")
            checked: Config.options.bar.weather.useUSCS
            onCheckedChanged: {
                Config.options.bar.weather.useUSCS = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }
}
