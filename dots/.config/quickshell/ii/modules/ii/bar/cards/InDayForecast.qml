import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

SectionCard {
    id: inDayForecastCard
    property int forecastCardHeight: 125

    Flickable {
        id: flickable
        Layout.fillWidth: true
        Layout.preferredHeight: inDayForecastCard.forecastCardHeight
        contentWidth: rowLayout.implicitWidth
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickableDirection: Flickable.HorizontalFlick
        visible: !root.forecastLoading && root.forecastData.length > 0

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                let delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                flickable.contentX = Math.max(0, Math.min(flickable.contentWidth - flickable.width, flickable.contentX - delta));
            }
        }

        RowLayout {
            id: rowLayout
            spacing: 12
            height: parent.height

            Repeater {
                model: root.forecastData

                Rectangle {
                    id: dayCard
                    width: 85
                    height: inDayForecastCard.forecastCardHeight
                    radius: Appearance.rounding.normal

                    color: {
                        const colors = [Appearance.colors.colPrimaryContainer, Appearance.colors.colSecondaryContainer, Appearance.colors.colTertiaryContainer];
                        return colors[index % 3];
                    }

                    property color textColor: {
                        const colors = [Appearance.colors.colOnPrimaryContainer, Appearance.colors.colOnSecondaryContainer, Appearance.colors.colOnTertiaryContainer];
                        return colors[index % 3];
                    }

                    ColumnLayout {
                        id: dayColumn
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.getDayName(modelData.date, index)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: dayCard.textColor
                        }

                        MaterialShape {
                            Layout.alignment: Qt.AlignHCenter
                            shapeString: {
                                const shapes = ["Cookie9Sided", "Flower", "Clover4Leaf", "Pentagon", "Hexagon", "Octagon", "Arch"];
                                return shapes[index % shapes.length];
                            }
                            implicitSize: 48
                            color: Qt.rgba(dayCard.textColor.r, dayCard.textColor.g, dayCard.textColor.b, 0.15)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: Icons.getWeatherIcon(modelData.code)
                                iconSize: Appearance.font.pixelSize.large
                                color: dayCard.textColor
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Weather.useUSCS ? modelData.maxF + "°" : modelData.maxC + "°"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: dayCard.textColor
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Weather.useUSCS ? modelData.minF + "°" : modelData.minC + "°"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Qt.rgba(dayCard.textColor.r, dayCard.textColor.g, dayCard.textColor.b, 0.7)
                            }
                        }
                    }
                }
            }
        }
    }

    LoadingPlaceholder {
        Layout.preferredHeight: inDayForecastCard.forecastCardHeight
        visible: root.forecastLoading || root.forecastData.length === 0
        loading: root.forecastLoading
        loadingText: Translation.tr("Loading forecast...")
        emptyText: Translation.tr("No forecast data")
    }
}