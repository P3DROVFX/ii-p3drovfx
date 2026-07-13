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
        }
        
        HourlyForecast {
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
        }

        MetricsGrid {
            visible: !root.compact

            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            uniformCellWidths: true
        }

        InDayForecast {
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
        }
    }
}