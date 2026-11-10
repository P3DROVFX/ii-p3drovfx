import QtQuick
import qs.services

/*
 * A colour per weather family (WeatherMood.family), from the widget colour
 * scheme only: the sun in the accent, clouds on the inner shape colour, rain
 * on the pill fill, storms on the warning colour. `on()` is the colour that
 * reads on it.
 */
QtObject {
    function fill(fam) {
        switch (fam) {
        case "clear": return WidgetColorScheme.accentColor;
        case "partly": return WidgetColorScheme.highlightCircleColor;
        case "cloud": return WidgetColorScheme.innerShapeColor;
        case "fog": return WidgetColorScheme.surfaceVariantColor;
        case "rain": return WidgetColorScheme.pillFillColor;
        case "snow": return WidgetColorScheme.subtextColorOnBg;
        case "storm": return WidgetColorScheme.warningColor;
        }
        return WidgetColorScheme.innerShapeColor;
    }

    function on(fam) {
        switch (fam) {
        case "clear": return WidgetColorScheme.onAccentColor;
        case "partly": return WidgetColorScheme.highlightTextColor;
        case "rain": return WidgetColorScheme.textColorOnPillFill;
        case "snow": return WidgetColorScheme.cardBgColor;
        }
        return WidgetColorScheme.textColorOnBg;
    }
}
