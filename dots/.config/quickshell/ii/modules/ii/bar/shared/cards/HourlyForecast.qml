import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.cards

SectionCard {
    id: hourlyForecastCard
    property int hourlyChartHeight: 145
    
    // Internal animation control
    property bool startAnim: false

    onStartAnimChanged: {
        if (startAnim) {
            // Reset all bars to 0 height first
            for (var i = 0; i < barRepeater.count; i++) {
                var item = barRepeater.itemAt(i);
                if (item) {
                    item.barOpacity = 0.0;
                    item.barScale = 0.8;
                    item.barHeightAnim = 0;
                }
            }
            
            // Start staggered animations after a brief delay
            Qt.callLater(function() {
                for (var j = 0; j < barRepeater.count; j++) {
                    var barItem = barRepeater.itemAt(j);
                    if (barItem) {
                        barItem.barAnimDelay = j * 60;
                        barItem.startBarAnim();
                    }
                }
            });
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: hourlyForecastCard.hourlyChartHeight
        visible: !root.forecastLoading && root.filteredHourlyData.length > 0

        property var tempRange: root.getHourlyTempRange()
        property real tempSpan: Math.max(tempRange.max - tempRange.min, 1)

        RowLayout {
            anchors.fill: parent
            spacing: 6

            Repeater {
                id: barRepeater
                model: root.filteredHourlyData

                Item {
                    id: barItem
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    required property var modelData
                    required property int index

                    property int hourValue: Math.floor(parseInt(modelData.time) / 100)
                    property bool isCurrentHour: index === 0
                    property real temp: Weather.useUSCS ? parseInt(modelData.tempF) : parseInt(modelData.tempC)
                    property var parentTempRange: root.getHourlyTempRange()
                    property real parentTempSpan: Math.max(parentTempRange.max - parentTempRange.min, 1)
                    property real normalized: (temp - parentTempRange.min) / parentTempSpan
                    // Bar height: 45% min to 100% max for better visual contrast
                    property real availableBarSpace: parent.height - timeLabel.height + 10
                    property real barHeight: availableBarSpace * (0.45 + normalized * 0.55)
                    
                    // Animation properties
                    property real barOpacity: 1.0
                    property real barScale: 1.0
                    property real barHeightAnim: barHeight
                    property int barAnimDelay: 0
                    
                    function startBarAnim() {
                        barAnim.start();
                    }

                    SequentialAnimation {
                        id: barAnim
                        PauseAnimation { duration: barItem.barAnimDelay }
                        ParallelAnimation {
                            NumberAnimation { target: barItem; property: "barOpacity"; from: 0.0; to: 1.0; duration: 280 }
                            NumberAnimation { target: barItem; property: "barScale"; from: 0.8; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: barItem; property: "barHeightAnim"; from: 0; to: barItem.barHeight; duration: 450; easing.type: Easing.OutCubic }
                        }
                    }

                    StyledText {
                        id: timeLabel
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.formatHour(modelData.time)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: isCurrentHour ? Font.Bold : Font.Normal
                        color: isCurrentHour ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        opacity: barItem.barOpacity
                    }

                    Rectangle {
                        id: barRect
                        anchors.bottom: timeLabel.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: barItem.barHeightAnim
                        radius: Appearance.rounding.normal
                        color: isCurrentHour ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                        opacity: barItem.barOpacity
                        scale: barItem.barScale
                        transformOrigin: Item.Bottom

                        ColumnLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 8
                            spacing: 2

                            Image {
                                id: weatherIcon
                                Layout.alignment: Qt.AlignHCenter
                                source: WeatherIcons.getWeatherIcon(modelData.code ?? 113, false)
                                sourceSize: Qt.size(Appearance.font.pixelSize.large, Appearance.font.pixelSize.large)
                                opacity: barItem.barOpacity
                                scale: barItem.barScale
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: barItem.temp + "°"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: isCurrentHour ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                opacity: barItem.barOpacity
                            }
                        }

                        Rectangle {
                            visible: isCurrentHour
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            width: 20
                            height: 20
                            radius: 10
                            color: Appearance.colors.colPrimary
                            opacity: barItem.barOpacity

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    LoadingPlaceholder {
        Layout.preferredHeight: hourlyForecastCard.hourlyChartHeight
        visible: root.forecastLoading || root.filteredHourlyData.length === 0
        loading: root.forecastLoading
        loadingText: Translation.tr("Loading forecast...")
        emptyText: Translation.tr("No forecast data")
    }
}