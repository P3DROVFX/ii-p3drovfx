import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.cards

GridLayout {
    // Internal animation control
    property bool startAnim: false
    
    onStartAnimChanged: {
        if (startAnim) {
            // Reset all cards first
            sunriseCard.startAnim = false;
            sunsetCard.startAnim = false;
            precipCard.startAnim = false;
            humidityCard.startAnim = false;
            
            // Set delays and trigger animations
            sunriseCard.animDelay = 0;
            sunsetCard.animDelay = 60;
            precipCard.animDelay = 120;
            humidityCard.animDelay = 180;
            
            Qt.callLater(function() {
                sunriseCard.startAnim = true;
                sunsetCard.startAnim = true;
                precipCard.startAnim = true;
                humidityCard.startAnim = true;
            });
        }
    }

    MetricCard {
        id: sunriseCard
        title: Translation.tr("Sunrise")
        symbol: "wb_twilight"
        value: Weather.data.sunrise
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
    }
    MetricCard {
        id: sunsetCard
        title: Translation.tr("Sunset")
        symbol: "bedtime"
        value: Weather.data.sunset
        accentColor: Appearance.colors.colSecondaryContainer
        symbolColor: Appearance.colors.colOnSecondaryContainer
    }
    MetricCard {
        id: precipCard
        title: Translation.tr("Precipitation")
        symbol: "rainy_light"
        value: Weather.data.precip
        accentColor: Appearance.colors.colPrimaryContainer
        symbolColor: Appearance.colors.colOnPrimaryContainer
    }
    MetricCard {
        id: humidityCard
        title: Translation.tr("Humidity")
        symbol: "humidity_low"
        value: Weather.data.humidity
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
    }
}