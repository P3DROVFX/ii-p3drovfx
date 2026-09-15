pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.desktop.widgets

WidgetCard {
    id: root
    minSize: 150

    readonly property var wd: Weather.data
    readonly property real tempFontSize: Math.max(Appearance.font.pixelSize.huge, Math.min(64, Math.round(Math.min(root.width, root.height) * 0.24)))
    readonly property real chipSize: Math.max(38, Math.round(root.tempFontSize * 1.2))
    readonly property bool statsVisible: root.height >= 190

    function reading(value: var, fallback: string): string {
        return typeof value === "string" && value.length > 0 ? value : fallback;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: root.reading(root.wd.temp, "--°")
                    font.pixelSize: root.tempFontSize
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Feels like %1").arg(root.reading(root.wd.tempFeelsLike, "--°"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            Squircle {
                implicitWidth: root.chipSize
                implicitHeight: root.chipSize
                radius: Appearance.rounding.normal
                smoothing: AkebonoAppearance.squircleSmoothing
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: Icons.getWeatherIcon(root.wd.wCode) ?? "cloud"
                    fill: 1
                    iconSize: Math.round(root.chipSize * 0.55)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.reading(root.wd.city, "")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.statsVisible
            spacing: 4

            WeatherStat {
                icon: "humidity_percentage"
                value: root.reading(root.wd.humidity, "--")
            }
            WeatherStat {
                icon: "air"
                value: root.reading(root.wd.wind, "--")
            }
            WeatherStat {
                icon: "rainy"
                value: root.reading(root.wd.precip, "--")
            }
        }
    }

    component WeatherStat: RowLayout {
        id: stat
        property string icon: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 3

        MaterialSymbol {
            text: stat.icon
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            text: stat.value
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }
}
