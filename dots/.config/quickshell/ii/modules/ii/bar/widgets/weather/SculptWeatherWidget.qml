pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.weather
import qs.services

/**
 * Sculpt weather — three type-led takes on the forecast, chosen in the
 * widget's page (`bar.weatherWidget.sculptVariant`):
 *
 *   poster     the temperature as a poster numeral, tall and condensed, whose
 *              weight *is* the warmth: hairline when it is freezing, black when
 *              it is hot. The condition in a slanted voice, the city in caps.
 *   stamp      the condition as one display word — SUN, RAIN, STORM — on a card,
 *              stamped with the temperature inside a shape that is the weather
 *              itself (a sunburst, a puff of cloud, a spiky storm)
 *   daylight   the day as an arc: the sun travels it from sunrise to sunset and
 *              the night arc below it after dark; the temperature and the next
 *              sunrise/sunset beside it
 *
 * This file owns the data, the click (right = refresh) and the popup.
 */
MouseArea {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.weatherWidget.sculptVariant ?? "poster"
    readonly property bool showDetails: Config.options.bar.weatherWidget.sculptShowDetails ?? true
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    // ── The forecast, normalised ─────────────────────────────────────────────
    // Plain rather than readonly so a preview can hand in a forecast.
    property var forecast: Weather.data
    property string clock: DateTime.time

    readonly property int code: Number(root.forecast?.wCode ?? 113)
    readonly property string tempText: String(root.forecast?.temp ?? "--°")
    readonly property int tempValue: parseInt(root.tempText)
    readonly property bool fahrenheit: root.tempText.indexOf("F") >= 0
    readonly property real celsius: root.fahrenheit ? (root.tempValue - 32) * 5 / 9 : root.tempValue
    // 0 at -5 °C, 1 at 35 °C.
    readonly property real warmth: isNaN(root.celsius) ? 0.5 : Math.max(0, Math.min(1, (root.celsius + 5) / 40))
    readonly property string digits: isNaN(root.tempValue) ? "--" : String(root.tempValue)
    readonly property string description: String(root.forecast?.wDesc ?? "")
    readonly property string city: String(root.forecast?.city ?? "")

    function minutesOf(text: string): int {
        const match = String(text ?? "").match(/(\d{1,2}):(\d{2})\s*([AaPp][Mm])?/);
        if (!match)
            return -1;
        let hours = parseInt(match[1]) % 24;
        const meridiem = (match[3] ?? "").toLowerCase();
        if (meridiem === "pm" && hours < 12)
            hours += 12;
        if (meridiem === "am" && hours === 12)
            hours = 0;
        return hours * 60 + parseInt(match[2]);
    }
    readonly property int sunrise: root.minutesOf(root.forecast?.sunrise ?? "06:00")
    readonly property int sunset: root.minutesOf(root.forecast?.sunset ?? "18:00")
    readonly property int now: {
        root.clock;
        const date = new Date();
        return date.getHours() * 60 + date.getMinutes();
    }
    readonly property bool night: root.sunrise >= 0 && root.sunset > root.sunrise
        ? (root.now < root.sunrise || root.now >= root.sunset)
        : (new Date().getHours() >= 18 || new Date().getHours() < 6)
    // Through the day while it is light, through the night after dark.
    readonly property real dayProgress: {
        if (root.sunrise < 0 || root.sunset <= root.sunrise)
            return 0.5;
        if (!root.night)
            return (root.now - root.sunrise) / (root.sunset - root.sunrise);
        const nightLength = 1440 - (root.sunset - root.sunrise);
        const since = root.now >= root.sunset ? root.now - root.sunset : root.now + 1440 - root.sunset;
        return since / nightLength;
    }
    readonly property url icon: WeatherIcons.getWeatherIcon(root.code, root.night)

    // One word per family of conditions (WWO codes).
    readonly property string condition: {
        const c = root.code;
        if (c === 200 || (c >= 386 && c <= 395))
            return "storm";
        if ([179, 182, 185, 227, 230, 350].indexOf(c) >= 0 || (c >= 317 && c <= 338) || (c >= 362 && c <= 377))
            return "snow";
        if (c === 176 || (c >= 263 && c <= 314) || (c >= 353 && c <= 359))
            return "rain";
        if (c === 143 || c === 248 || c === 260)
            return "fog";
        if (c === 116 || c === 119 || c === 122)
            return "cloud";
        return root.night ? "clear" : "sun";
    }
    readonly property string conditionWord: ({
        "storm": Translation.tr("Storm"),
        "snow": Translation.tr("Snow"),
        "rain": Translation.tr("Rain"),
        "fog": Translation.tr("Fog"),
        "cloud": Translation.tr("Cloud"),
        "clear": Translation.tr("Clear"),
        "sun": Translation.tr("Sun")
    })[root.condition]

    BarWidgetPalette {
        id: weatherTones
        colorMode: Config.options.bar.weatherWidget.colorMode ?? "tonal"
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : (variantLoader.item?.implicitWidth ?? 0)
    implicitHeight: root.vertical ? (variantLoader.item?.implicitHeight ?? 0) : Appearance.sizes.baseBarHeight
    hoverEnabled: !BarInteraction.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton)
            Weather.refreshManually();
    }

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        sourceComponent: root.variant === "stamp"
            ? stampVariant
            : root.variant === "daylight" ? daylightVariant : posterVariant
    }

    Component {
        id: posterVariant
        SculptWeatherPoster {
            vertical: root.vertical
            thickness: root.thickness
            tones: weatherTones
            hovered: root.containsMouse
            icon: root.icon
            digits: root.digits
            warmth: root.warmth
            description: root.description
            city: root.city
            showDetails: root.showDetails
        }
    }

    Component {
        id: stampVariant
        SculptWeatherStamp {
            vertical: root.vertical
            thickness: root.thickness
            tones: weatherTones
            hovered: root.containsMouse
            condition: root.condition
            word: root.conditionWord
            digits: root.digits
        }
    }

    Component {
        id: daylightVariant
        SculptWeatherDaylight {
            vertical: root.vertical
            thickness: root.thickness
            tones: weatherTones
            hovered: root.containsMouse
            digits: root.digits
            night: root.night
            progress: root.dayProgress
            nextEvent: root.night
                ? Translation.tr("Sunrise %1").arg(root.forecast?.sunrise ?? "")
                : Translation.tr("Sunset %1").arg(root.forecast?.sunset ?? "")
            showDetails: root.showDetails
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        sourceComponent: WeatherPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: root
        }
    }
}
