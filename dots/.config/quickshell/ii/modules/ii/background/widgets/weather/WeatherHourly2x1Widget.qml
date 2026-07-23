import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_hourly"

    readonly property bool expressive: Config.options.background.widgets.weather_hourly.expressiveColors ?? false

    implicitWidth: 492
    implicitHeight: 240

    readonly property var currentData: Weather.data
    readonly property var forecastList: Weather.forecastData
    readonly property var hourlyList: Weather.hourlyData

    readonly property color cardBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color textColorOnBg: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
    readonly property color containerBgColor: expressive 
        ? ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.20)
        : Appearance.colors.colSurfaceContainerHighest

    readonly property var filteredHourly: {
        if (!hourlyList || hourlyList.length === 0) return [];
        const now = new Date();
        const currentHr = now.getHours();
        let list = [];
        for (let i = 0; i < hourlyList.length; i++) {
            const item = hourlyList[i];
            const itemHr = Math.floor(parseInt(item.time) / 100);
            if (itemHr >= currentHr || list.length > 0) {
                list.push(item);
                if (list.length >= 4) break;
            }
        }
        if (list.length < 4 && hourlyList.length >= 4) {
            return hourlyList.slice(0, 4);
        }
        return list;
    }

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
            anchors.margins: 18
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    spacing: 0
                    Layout.alignment: Qt.AlignTop

                    MaterialSymbol {
                        iconSize: 34
                        text: Icons.getWeatherIcon(root.currentData?.wCode) ?? "sunny"
                        color: Appearance.colors.colPrimary
                        fill: 1.0
                    }

                    StyledText {
                        text: root.currentData?.temp || ""
                        color: root.textColorOnBg
                        font.pixelSize: Appearance.font.pixelSize.huge * 1.9
                        font.weight: Font.Bold
                    }

                    RowLayout {
                        spacing: 8

                        StyledText {
                            text: {
                                const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                if (!firstFc) return "";
                                const h = Weather.useUSCS ? firstFc.maxF : firstFc.maxC;
                                return h + "°";
                            }
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            text: {
                                const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                if (!firstFc) return "";
                                const l = Weather.useUSCS ? firstFc.minF : firstFc.minC;
                                return l + "°";
                            }
                            color: ColorUtils.applyAlpha(root.textColorOnBg, 0.65)
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 8
                    Layout.alignment: Qt.AlignTop | Qt.AlignRight

                    Column {
                        Layout.alignment: Qt.AlignRight
                        spacing: 0

                        StyledText {
                            anchors.right: parent.right
                            text: root.currentData?.city || ""
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            anchors.right: parent.right
                            text: root.currentData?.wDesc || ""
                            color: root.textColorOnBg
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 16

                        Repeater {
                            model: root.filteredHourly

                            delegate: ColumnLayout {
                                required property var modelData
                                spacing: 2

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (Weather.useUSCS ? modelData.tempF : modelData.tempC) + "°"
                                    color: ColorUtils.applyAlpha(root.textColorOnBg, 0.75)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                }

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    iconSize: 24
                                    text: Icons.getWeatherIcon(modelData.code) ?? "sunny"
                                    color: Appearance.colors.colPrimary
                                    fill: 1.0
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: {
                                        const hr = Math.floor(parseInt(modelData.time) / 100);
                                        return hr.toString().padStart(2, '0') + ":00";
                                    }
                                    color: ColorUtils.applyAlpha(root.textColorOnBg, 0.65)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.windowRounding
                color: root.containerBgColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 0

                    Repeater {
                        model: Math.min(2, root.forecastList ? root.forecastList.length : 0)

                        delegate: RowLayout {
                            id: dayFcRow
                            required property int index

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            readonly property var fcItem: root.forecastList[index]

                            readonly property string dayNameStr: {
                                if (!fcItem || !fcItem.date) return "";
                                const dateObj = new Date(fcItem.date);
                                return dateObj.toLocaleDateString(Qt.locale(), "dddd");
                            }

                            StyledText {
                                text: dayFcRow.dayNameStr
                                color: root.textColorOnBg
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                Layout.fillWidth: true
                            }

                            MaterialSymbol {
                                iconSize: 22
                                text: Icons.getWeatherIcon(dayFcRow.fcItem?.code) ?? "partly_cloudy_day"
                                color: Appearance.colors.colPrimary
                                fill: 1.0
                            }

                            Item { Layout.preferredWidth: 12 }

                            StyledText {
                                text: (Weather.useUSCS ? dayFcRow.fcItem?.maxF : dayFcRow.fcItem?.maxC) + "°"
                                color: root.textColorOnBg
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                            }

                            Item { Layout.preferredWidth: 16 }

                            StyledText {
                                text: (Weather.useUSCS ? dayFcRow.fcItem?.minF : dayFcRow.fcItem?.minC) + "°"
                                color: ColorUtils.applyAlpha(root.textColorOnBg, 0.65)
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }
    }
}
