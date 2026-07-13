import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

GridLayout {

    MetricCard {
        title: Translation.tr("Sunrise")
        symbol: "wb_twilight"
        value: Weather.data.sunrise
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
    }
    MetricCard {
        title: Translation.tr("Sunset")
        symbol: "bedtime"
        value: Weather.data.sunset
        accentColor: Appearance.colors.colSecondaryContainer
        symbolColor: Appearance.colors.colOnSecondaryContainer
    }
    MetricCard {
        title: Translation.tr("Precipitation")
        symbol: "rainy_light"
        value: Weather.data.precip
        accentColor: Appearance.colors.colPrimaryContainer
        symbolColor: Appearance.colors.colOnPrimaryContainer
    }
    MetricCard {
        title: Translation.tr("Humidity")
        symbol: "humidity_low"
        value: Weather.data.humidity
        accentColor: Appearance.colors.colTertiaryContainer
        symbolColor: Appearance.colors.colOnTertiaryContainer
    }
}