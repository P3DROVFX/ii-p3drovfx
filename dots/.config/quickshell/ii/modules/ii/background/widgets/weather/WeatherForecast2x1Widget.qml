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

    configEntryName: "weather_forecast"

    readonly property bool expressive: Config.options.background.widgets.weather_forecast.expressiveColors ?? false

    implicitWidth: 492
    implicitHeight: 240

    readonly property var currentData: Weather.data
    readonly property var forecastList: Weather.forecastData
    readonly property string cityLocation: currentData?.city ? currentData.city : ""

    readonly property color cardBgColor: expressive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    readonly property color textColorOnBg: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant

    readonly property color leftPanelBgColor: expressive 
        ? ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.35)
        : Appearance.colors.colSurfaceContainerHighest

    readonly property color pillBgColor: expressive
        ? ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.25)
        : Appearance.colors.colSurfaceContainerHighest

    readonly property color heroTextColor: expressive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant

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
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Rectangle {
                    id: leftHeroCard
                    Layout.fillHeight: true
                    Layout.preferredWidth: 210
                    radius: Appearance.rounding.windowRounding
                    color: root.leftPanelBgColor

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 58
                                    text: Icons.getWeatherIcon(root.currentData?.wCode) ?? "partly_cloudy_day"
                                    color: Appearance.colors.colPrimary
                                    fill: 1.0
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Column {
                                Layout.alignment: Qt.AlignRight | Qt.AlignTop
                                spacing: 2

                                StyledText {
                                    text: {
                                        const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                        if (!firstFc) return "";
                                        const h = Weather.useUSCS ? firstFc.maxF : firstFc.maxC;
                                        return "H. " + h + "°";
                                    }
                                    color: root.heroTextColor
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }

                                StyledText {
                                    text: {
                                        const firstFc = root.forecastList && root.forecastList.length > 0 ? root.forecastList[0] : null;
                                        if (!firstFc) return "";
                                        const l = Weather.useUSCS ? firstFc.minF : firstFc.minC;
                                        return "L. " + l + "°";
                                    }
                                    color: root.heroTextColor
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        StyledText {
                            text: root.currentData?.wDesc || ""
                            color: root.heroTextColor
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            opacity: 0.95
                        }

                        StyledText {
                            text: root.currentData?.temp || ""
                            color: root.heroTextColor
                            font.pixelSize: Appearance.font.pixelSize.huge * 1.5
                            font.weight: Font.Bold
                        }
                    }
                }

                Repeater {
                    model: 3

                    delegate: Rectangle {
                        id: dayPill
                        required property int index

                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        radius: Appearance.rounding.full
                        color: root.pillBgColor

                        readonly property var dayFc: root.forecastList && root.forecastList.length > index ? root.forecastList[index] : null

                        readonly property string dayLabel: {
                            if (!dayFc || !dayFc.date) return "";
                            const dateObj = new Date(dayFc.date);
                            return dateObj.toLocaleDateString(Qt.locale(), "ddd");
                        }

                        readonly property string dayTempStr: {
                            if (!dayFc) return "";
                            const t = Weather.useUSCS ? dayFc.maxF : dayFc.maxC;
                            return t + "°";
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 16
                            anchors.bottomMargin: 16
                            spacing: 8

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: dayPill.dayLabel
                                color: root.heroTextColor
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                            }

                            Item { Layout.fillHeight: true }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                iconSize: 44
                                text: Icons.getWeatherIcon(dayPill.dayFc?.code) ?? "rainy"
                                color: Appearance.colors.colPrimary
                                fill: 1.0
                            }

                            Item { Layout.fillHeight: true }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: dayPill.dayTempStr
                                color: root.heroTextColor
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 8

                StyledText {
                    text: root.cityLocation
                    color: root.textColorOnBg
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitWidth: 24
                    implicitHeight: 24
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                    colRipple: Qt.rgba(1, 1, 1, 0.2)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 16
                        color: root.textColorOnBg
                    }

                    onClicked: {
                        Weather.getData(true);
                    }
                }
            }
        }
    }
}
