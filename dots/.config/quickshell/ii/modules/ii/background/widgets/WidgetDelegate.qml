import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.DateWidget
import qs.modules.ii.background.widgets.photo
import qs.modules.ii.background.widgets.bluetooth
import qs.modules.ii.background.widgets.utility

Item {
    id: delegateRoot

    // Required model properties
    required property int index
    required property string widgetId
    required property string instanceId
    required property real widgetX
    required property real widgetY
    required property string placementStrategy
    required property string lockBehavior
    required property var widgetListModel

    // External inputs
    required property int screenWidth
    required property int screenHeight
    required property real wallpaperScale
    required property bool wallpaperSafetyTriggered
    required property bool lockAnimationActive
    required property var widgetSizes
    required property int widgetSizesVersion
    required property int staggerDelay

    // Static Component Definitions for built-in widgets
    Component {
        id: component_clock_cookie
        ClockWidget {
            styleOverride: "cookie"
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }
    }

    Component {
        id: component_clock_digital
        ClockWidget {
            styleOverride: "digital"
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }
    }

    Component {
        id: component_clock_nagasaki
        ClockWidget {
            styleOverride: "nagasaki"
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }
    }

    Component {
        id: component_clock_dial
        ClockWidget {
            styleOverride: "dial"
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }
    }

    Component {
        id: component_circular_media
        CircularMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_clock_wearos
        WearOSClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_media_circular
        MediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_media_expressive
        ExpressiveMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_media_android
        AndroidMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_media_cd
        CdMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_default
        WeatherWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_expressive
        ExpressiveWeatherWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_forecast
        WeatherForecast2x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_card
        WeatherCard1x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_icon
        WeatherIconWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_pill
        WeatherPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_circle
        WeatherCircleWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_typography
        WeatherTypographyWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_weather_hourly
        WeatherHourly2x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_date_default
        DateWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_minimal
        CalendarMinimalWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_grid
        CalendarGrid2x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_agenda
        CalendarAgendaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_next_event
        CalendarNextEventWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_pill
        CalendarPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_calendar_upcoming_3days
        CalendarUpcoming3DaysWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_photo_default
        PhotoWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_bluetooth_battery
        BluetoothBatteryWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_bluetooth_headphone
        BluetoothHeadphoneWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_mobile_battery
        MobileBatteryWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_bluetooth_headphone_cookie
        BluetoothHeadphoneCookieWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_bluetooth_fill_cards
        BluetoothFillCardsWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_pc_battery_bars
        PcBatteryBarsWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_pc_battery_cable
        PcBatteryCableWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_devices_battery_list
        DevicesBatteryListWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_devices_battery_list_1x1
        DevicesBatteryList1x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_bluetooth_earbuds_stem
        BluetoothEarbudsStemWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_email_inbox
        EmailWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    Component {
        id: component_email_inbox_2x1
        EmailWidget2x1 {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }
    }

    readonly property var widgetComponentMap: ({
            "clock_cookie": component_clock_cookie,
            "clock_digital": component_clock_digital,
            "clock_nagasaki": component_clock_nagasaki,
            "clock_dial": component_clock_dial,
            "clock_wearos": component_clock_wearos,
            "circular_media": component_circular_media,
            "media_circular": component_media_circular,
            "media_expressive": component_media_expressive,
            "media_android": component_media_android,
            "media_cd": component_media_cd,
            "weather_default": component_weather_default,
            "weather_expressive": component_weather_expressive,
            "weather_forecast": component_weather_forecast,
            "weather_card": component_weather_card,
            "weather_icon": component_weather_icon,
            "weather_pill": component_weather_pill,
            "weather_circle": component_weather_circle,
            "weather_typography": component_weather_typography,
            "weather_hourly": component_weather_hourly,
            "date_default": component_date_default,
            "calendar_minimal": component_calendar_minimal,
            "calendar_grid": component_calendar_grid,
            "calendar_agenda": component_calendar_agenda,
            "calendar_next_event": component_calendar_next_event,
            "calendar_pill": component_calendar_pill,
            "calendar_upcoming_3days": component_calendar_upcoming_3days,
            "photo_default": component_photo_default,
            "bluetooth_battery": component_bluetooth_battery,
            "bluetooth_headphone": component_bluetooth_headphone,
            "mobile_battery": component_mobile_battery,
            "bluetooth_headphone_cookie": component_bluetooth_headphone_cookie,
            "bluetooth_fill_cards": component_bluetooth_fill_cards,
            "pc_battery_bars": component_pc_battery_bars,
            "pc_battery_cable": component_pc_battery_cable,
            "devices_battery_list": component_devices_battery_list,
            "devices_battery_list_1x1": component_devices_battery_list_1x1,
            "bluetooth_earbuds_stem": component_bluetooth_earbuds_stem,
            "email_inbox": component_email_inbox,
            "email_inbox_2x1": component_email_inbox_2x1
        })

    function getExtUrl(extId) {
        let entry = WidgetExtensionManager.installedWidgets[extId];
        if (!entry)
            return "";
        let wj = entry.widgetJson || {};
        let qmlFile = wj.component || (wj.widget && wj.widget.component ? wj.widget.component : "main.qml");
        return "file://" + entry.installedPath + "/" + qmlFile;
    }

    FadeLoader {
        id: widgetLoader
        shown: !delegateRoot.lockAnimationActive ? (delegateRoot.lockBehavior !== "lockOnly") : (delegateRoot.lockBehavior === "center" || delegateRoot.lockBehavior === "keep" || delegateRoot.lockBehavior === "lockOnly")

        source: delegateRoot.widgetId.startsWith("ext:") ? delegateRoot.getExtUrl(delegateRoot.widgetId.substring(4)) : ""

        sourceComponent: delegateRoot.widgetId.startsWith("ext:") ? null : (delegateRoot.widgetComponentMap[delegateRoot.widgetId] || null)

        Binding {
            target: widgetLoader.item
            property: "widgetInstance"
            value: {
                return {
                    "id": delegateRoot.instanceId,
                    "widgetId": delegateRoot.widgetId,
                    "x": delegateRoot.widgetX,
                    "y": delegateRoot.widgetY,
                    "placementStrategy": delegateRoot.placementStrategy,
                    "lockBehavior": delegateRoot.lockBehavior
                };
            }
            when: widgetLoader.status == Loader.Ready
        }

        Binding {
            target: widgetLoader.item
            property: "widgetExtensionId"
            value: delegateRoot.widgetId.startsWith("ext:") ? delegateRoot.widgetId.substring(4) : ""
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }

        Binding {
            target: widgetLoader.item
            property: "widgetConfig"
            value: {
                if (!delegateRoot.widgetId.startsWith("ext:"))
                    return null;
                let extId = delegateRoot.widgetId.substring(4);
                return WidgetExtensionManager.widgetConfigs[extId] || ({});
            }
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }

        Binding {
            target: widgetLoader.item
            property: "widgetListModel"
            value: delegateRoot.widgetListModel
            when: widgetLoader.status == Loader.Ready
        }

        Binding {
            target: widgetLoader.item
            property: "widgetSizes"
            value: delegateRoot.widgetSizes
            when: widgetLoader.status == Loader.Ready
        }

        Binding {
            target: widgetLoader.item
            property: "widgetSizesVersion"
            value: delegateRoot.widgetSizesVersion
            when: widgetLoader.status == Loader.Ready
        }

        Binding {
            target: widgetLoader.item
            property: "staggerDelay"
            value: delegateRoot.staggerDelay
            when: widgetLoader.status == Loader.Ready
        }
    }

    MissingWidgetPlaceholder {
        widgetId: delegateRoot.widgetId
        widgetX: delegateRoot.widgetX
        widgetY: delegateRoot.widgetY
    }
}
