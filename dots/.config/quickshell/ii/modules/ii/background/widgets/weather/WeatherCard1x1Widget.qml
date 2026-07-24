import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_card"

    implicitWidth: 240
    implicitHeight: 240

    readonly property var currentData: Weather.data
    readonly property var forecastList: Weather.forecastData

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    StyledDropShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: root.cardBgColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            StyledText {
                text: root.currentData?.city || ""
                color: root.textColorOnBg
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: root.currentData?.temp ? root.currentData.temp.replace("°C", "°").replace("°F", "°") : ""
                    color: root.textColorOnBg
                    font.pixelSize: Appearance.font.pixelSize.huge * 2.2
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 2

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignRight
                        iconSize: 34
                        text: Icons.getWeatherIcon(root.currentData?.wCode) ?? "partly_cloudy_day"
                        color: Appearance.colors.colPrimary
                        fill: 1.0
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 0

                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: {
                                const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                if (!firstFc) return "";
                                const h = Weather.useUSCS ? firstFc.maxF : firstFc.maxC;
                                return "H " + h + "°";
                            }
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: {
                                const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                if (!firstFc) return "";
                                const l = Weather.useUSCS ? firstFc.minF : firstFc.minC;
                                return "L " + l + "°";
                            }
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: 3

                    delegate: RowLayout {
                        id: dayRow
                        required property int index

                        Layout.fillWidth: true
                        spacing: 8

                        readonly property var dayFc: root.forecastList && root.forecastList.length > index ? root.forecastList[index] : null

                        readonly property string dayLabel: {
                            if (!dayFc || !dayFc.date) return "";
                            const dateObj = new Date(dayFc.date);
                            return dateObj.toLocaleDateString(Qt.locale(), "ddd");
                        }

                        StyledText {
                            Layout.preferredWidth: 60
                            text: dayRow.dayLabel
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }

                        Item { Layout.fillWidth: true }

                        MaterialSymbol {
                            iconSize: 20
                            text: Icons.getWeatherIcon(dayRow.dayFc?.code) ?? "clear_day"
                            color: Appearance.colors.colPrimary
                            fill: 1.0
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: {
                                if (!dayRow.dayFc) return "";
                                const min = Weather.useUSCS ? dayRow.dayFc.minF : dayRow.dayFc.minC;
                                const max = Weather.useUSCS ? dayRow.dayFc.maxF : dayRow.dayFc.maxC;
                                return min + "°  " + max + "°";
                            }
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
