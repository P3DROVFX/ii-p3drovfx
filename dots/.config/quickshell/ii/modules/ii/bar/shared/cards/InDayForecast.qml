import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.cards

SectionCard {
    id: inDayForecastCard
    property int forecastCardHeight: 125

    // Internal animation control
    property bool startAnim: false

    onStartAnimChanged: {
        if (startAnim) {
            flickable.contentX = 0;

            // Reset all cards
            for (var i = 0; i < dayRepeater.count; i++) {
                var item = dayRepeater.itemAt(i);
                if (item) {
                    item.cardOpacity = 0.0;
                    item.cardTranslateX = 50;
                    item.iconScale = 0.7;
                }
            }
            
            // Start staggered animations with initial delay
            Qt.callLater(function() {
                for (var j = 0; j < dayRepeater.count; j++) {
                    var cardItem = dayRepeater.itemAt(j);
                    if (cardItem) {
                        cardItem.cardAnimDelay = 200 + (j * 120);
                        cardItem.startCardAnim();
                    }
                }
            });
        }
    }

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
                id: dayRepeater
                model: root.forecastData

                Rectangle {
                    id: dayCard
                    width: 85
                    height: inDayForecastCard.forecastCardHeight
                    radius: Appearance.rounding.normal
                    
                    // Animation properties
                    property real cardOpacity: 1.0
                    property real cardTranslateX: 0
                    property real iconScale: 1.0
                    property int cardAnimDelay: 0
                    
                    function startCardAnim() {
                        // Force a real running:false->true transition; calling start() while
                        // already running (e.g. popup reopened before the previous entrance
                        // animation finished) is a no-op and leaves the card stuck invisible.
                        cardAnim.stop();
                        cardAnim.start();
                    }

                    SequentialAnimation {
                        id: cardAnim
                        PauseAnimation { duration: dayCard.cardAnimDelay }
                        ParallelAnimation {
                            NumberAnimation { target: dayCard; property: "cardOpacity"; from: 0.0; to: 1.0; duration: 400 }
                            NumberAnimation { target: dayCard; property: "cardTranslateX"; from: 50; to: 0; duration: 500; easing.type: Easing.OutCubic }
                            NumberAnimation { target: dayCard; property: "iconScale"; from: 0.7; to: 1.0; duration: 450; easing.type: Easing.OutBack }
                        }
                    }

                    opacity: dayCard.cardOpacity
                    transform: Translate {
                        x: dayCard.cardTranslateX
                    }

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
                            id: iconShape
                            Layout.alignment: Qt.AlignHCenter
                            shapeString: {
                                const shapes = ["Cookie9Sided", "Flower", "Clover4Leaf", "Pentagon", "Hexagon", "Octagon", "Arch"];
                                return shapes[index % shapes.length];
                            }
                            implicitSize: 48
                            color: Qt.rgba(dayCard.textColor.r, dayCard.textColor.g, dayCard.textColor.b, 0.15)
                            scale: dayCard.iconScale

                            Image {
                                anchors.centerIn: parent
                                source: WeatherIcons.getWeatherIcon(modelData.code ?? 113, false)
                                sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
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