import qs.modules.ii.bar.shared
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../shared/cards"

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.ii.bar

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large
    stickyHover: true

    required property bool compact
    property bool compactMode: Config.options.bar.tooltips.compactPopups
    property int cardMargins: 14

    // Forecast data model bound to central Weather singleton
    property var forecastData: Weather.forecastData
    property var hourlyData: Weather.hourlyData
    property bool forecastLoading: Weather.forecastLoading
    property int maxHourlyBars: 5

    property var filteredHourlyData: {
        const now = new Date();
        const currentHr = now.getHours();
        // Round down to nearest 3-hour slot (API intervals: 0, 3, 6, 9, 12, 15, 18, 21)
        const currentSlot = Math.floor(currentHr / 3) * 3;
        let futureHours = [];
        let passedMidnight = false;

        for (let i = 0; i < hourlyData.length; i++) {
            const item = hourlyData[i];
            const itemHour = Math.floor(parseInt(item.time) / 100);

            if (i > 0 && itemHour < Math.floor(parseInt(hourlyData[i - 1].time) / 100)) {
                passedMidnight = true;
            }

            if (passedMidnight || itemHour >= currentSlot) {
                futureHours.push(item);
            }
        }
        return futureHours.slice(0, maxHourlyBars);
    }

    readonly property string city: Config.options.bar.weather.city
    onCityChanged: {
        if (Config.options.bar.weather.city)
            Weather.getData();
    }

    function fetchForecast() {
        Weather.getData();
    }

    function getDayName(dateStr, index) {
        if (index === 0)
            return Translation.tr("Today");
        if (index === 1)
            return Translation.tr("Tomorrow");
        const date = new Date(dateStr);
        const days = [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")];
        return days[date.getUTCDay()];
    }

    function formatHour(timeStr) {
        const hour = Math.floor(parseInt(timeStr) / 100);
        return hour.toString().padStart(2, '0') + ":00";
    }

    function getHourlyTempRange() {
        const data = filteredHourlyData.length > 0 ? filteredHourlyData : hourlyData;
        if (data.length === 0)
            return {
                min: 0,
                max: 100
            };
        const temps = data.map(h => Weather.useUSCS ? parseInt(h.tempF) : parseInt(h.tempC));
        const min = Math.min(...temps);
        const max = Math.max(...temps);
        // Add 20% padding (minimum 2°) to make small differences more visible
        const padding = Math.max(2, (max - min) * 0.2);
        return {
            min: min - padding,
            max: max + padding
        };
    }

    Component.onCompleted: fetchForecast()

    contentItem: ColumnLayout {
        id: contentLayout
        anchors.centerIn: parent
        spacing: 12

        // Dynamic vis index delays
        readonly property var _visList: [
            weatherHero.visible,
            hourlyForecast.visible,
            metricsGrid.visible,
            inDayForecast.visible
        ]

        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i]) visIndex++;
            }
            const delays = [40, 100, 160, 220];
            return delays[Math.min(visIndex, delays.length - 1)];
        }

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
        
        onStartAnimChanged: {
            if (startAnim) {
                weatherHero.opacity = 0.0;
                weatherHero.scale = 0.85;
                weatherHeroTransform.y = 25;
                
                hourlyForecast.opacity = 0.0;
                hourlyForecast.scale = 0.85;
                hourlyForecastTransform.y = 25;
                
                metricsGrid.opacity = 0.0;
                metricsGrid.scale = 0.85;
                metricsGridTransform.y = 25;
                
                inDayForecast.opacity = 0.0;
                inDayForecast.scale = 0.85;
                inDayForecastTransform.y = 25;
                
                Qt.callLater(function() {
                    weatherHeroAnim.start();
                    hourlyForecastAnim.start();
                    metricsGridAnim.start();
                    inDayForecastAnim.start();
                });
            }
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root && root.popupOpenProgress === 0.0) {
                    weatherHeroAnim.stop();
                    hourlyForecastAnim.stop();
                    metricsGridAnim.stop();
                    inDayForecastAnim.stop();

                    weatherHero.opacity = 0.0;
                    weatherHero.scale = 0.85;
                    weatherHeroTransform.y = 25;
                    
                    hourlyForecast.opacity = 0.0;
                    hourlyForecast.scale = 0.85;
                    hourlyForecastTransform.y = 25;
                    
                    metricsGrid.opacity = 0.0;
                    metricsGrid.scale = 0.85;
                    metricsGridTransform.y = 25;
                    
                    inDayForecast.opacity = 0.0;
                    inDayForecast.scale = 0.85;
                    inDayForecastTransform.y = 25;
                }
            }
        }

        HeroCard {
            id: weatherHero
            Layout.minimumWidth: 320
            margins: 20
            iconSize: 100
            icon: Icons.getWeatherIcon(Weather.data.wCode)
            pillText: Weather.data.city || "--"
            pillIcon: Weather.data.city ? "location_on" : ""
            title: Weather.data.temp
            subtitle: Weather.data.wDesc
            startAnim: contentLayout.startAnim

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: weatherHeroTransform
                y: 25
            }
            
            SequentialAnimation {
                id: weatherHeroAnim
                PauseAnimation { duration: contentLayout.getDelay(0) }
                ParallelAnimation {
                    NumberAnimation { target: weatherHero; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: weatherHero; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: weatherHeroTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }
        
        HourlyForecast {
            id: hourlyForecast
            visible: !root.compact
            showDivider: false
            spacing: 6
            
            icon: "schedule"
            title: Translation.tr("Hourly")
            headerExtraText: Translation.tr("Last refresh: %1").arg(Weather.data.lastRefresh || "--").slice(0, 20)
            
            shapeString: "Clover4Leaf"
            shapeColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer
            
            Layout.minimumWidth: 360
            margins: root.cardMargins
            startAnim: contentLayout.startAnim

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: hourlyForecastTransform
                y: 25
            }
            
            SequentialAnimation {
                id: hourlyForecastAnim
                PauseAnimation { duration: contentLayout.getDelay(1) }
                ParallelAnimation {
                    NumberAnimation { target: hourlyForecast; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: hourlyForecast; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: hourlyForecastTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        MetricsGrid {
            id: metricsGrid
            visible: !root.compact

            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            uniformCellWidths: true
            startAnim: contentLayout.startAnim

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: metricsGridTransform
                y: 25
            }
            
            SequentialAnimation {
                id: metricsGridAnim
                PauseAnimation { duration: contentLayout.getDelay(2) }
                ParallelAnimation {
                    NumberAnimation { target: metricsGrid; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: metricsGrid; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: metricsGridTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        InDayForecast {
            id: inDayForecast
            visible: !root.compact

            Layout.minimumWidth: 360
            margins: root.cardMargins
            spacing: 8
            shapeString: "Cookie6Sided"
            shapeColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer
            showDivider: false
            title: Translation.tr("Forecast")
            icon: "calendar_month"
            startAnim: contentLayout.startAnim

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: inDayForecastTransform
                y: 25
            }
            
            SequentialAnimation {
                id: inDayForecastAnim
                PauseAnimation { duration: contentLayout.getDelay(3) }
                ParallelAnimation {
                    NumberAnimation { target: inDayForecast; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: inDayForecast; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: inDayForecastTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}