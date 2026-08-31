import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.DateWidget
import qs.modules.ii.background.widgets.bluetooth
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.photo
import qs.modules.ii.background.widgets.system
import qs.modules.ii.background.widgets.utility
import qs.modules.ii.background.widgets.weather
import qs.services

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
    // Set by WidgetStateManager one animation before the model entry is dropped,
    // so the widget has something to animate out with.
    required property bool exiting
    readonly property var widgetComponentMap: ({
        "clock_cookie": component_clock_cookie,
        "clock_digital": component_clock_digital,
        "nagasaki_text": component_nagasaki_text,
        "clock_word": component_clock_word,
        "clock_flex": component_clock_flex,
        "clock_hori": component_clock_hori,
        "clock_nothing": component_clock_nothing,
        "nothing_wheel_clock": component_nothing_wheel_clock,
        "clock_dial": component_clock_dial,
        "clock_wearos": component_clock_wearos,
        "wearos_arc_clock": component_wearos_arc_clock,
        "concentric_clock": component_concentric_clock,
        "month_clock": component_month_clock,
        "scallop_dot_clock": component_scallop_dot_clock,
        "scallop_number_clock": component_scallop_number_clock,
        "circle_pointer_clock": component_circle_pointer_clock,
        "triple_ring_clock": component_triple_ring_clock,
        "grid_card_clock": component_grid_card_clock,
        "clock_expressive_card": component_clock_expressive_card,
        "circular_media": component_circular_media,
        "media_circular": component_media_circular,
        "media_expressive": component_media_expressive,
        "media_android": component_media_android,
        "media_cd": component_media_cd,
        "nothing_ring_media": component_nothing_ring_media,
        "compact_media": component_compact_media,
        "weather_default": component_weather_default,
        "weather_expressive": component_weather_expressive,
        "weather_forecast": component_weather_forecast,
        "weather_card": component_weather_card,
        "weather_icon": component_weather_icon,
        "weather_pill": component_weather_pill,
        "weather_circle": component_weather_circle,
        "nothing_weather_circle": component_nothing_weather_circle,
        "volume_mute_pill": component_volume_mute_pill,
        "wifi_pill": component_wifi_pill,
        "bluetooth_pill": component_bluetooth_pill,
        "mic_pill": component_mic_pill,
        "dark_mode_pill": component_dark_mode_pill,
        "screen_record_pill": component_screen_record_pill,
        "easy_effects_pill": component_easy_effects_pill,
        "weather_typography": component_weather_typography,
        "weather_hourly": component_weather_hourly,
        "date_default": component_date_default,
        "calendar_minimal": component_calendar_minimal,
        "calendar_grid": component_calendar_grid,
        "calendar_agenda": component_calendar_agenda,
        "calendar_next_event": component_calendar_next_event,
        "calendar_pill": component_calendar_pill,
        "calendar_upcoming_3days": component_calendar_upcoming_3days,
        "photo": component_photo,
        "photo_1x1": component_photo_1x1,
        "photo_weather_2x1": component_photo_weather_2x1,
        "photo_pill_2x1": component_photo_pill_2x1,
        "photo_minimal_temp_2x1": component_photo_minimal_temp_2x1,
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
        "email_inbox_2x1": component_email_inbox_2x1,
        "ai_chat": component_ai_chat,
        "android_search_bar": component_android_search_bar,
        "search_pill": component_search_pill,
        "notes_widget": component_notes_widget,
        "notes_widget_2x1": component_notes_widget_2x1,
        "quick_actions": component_quick_actions,
        "quote": component_quote,
        "water_reminder": component_water_reminder,
        "at_a_glance": component_at_a_glance,
        "resource_cpu_pill": component_resource_cpu_pill,
        "resource_ram_pill": component_resource_ram_pill,
        "resource_disk_pill": component_resource_disk_pill,
        "resource_fill_cards": component_resource_fill_cards,
        "resource_nothing_disk": component_resource_nothing_disk,
        "resource_nothing_cpu": component_resource_nothing_cpu,
        "resource_nothing_ram": component_resource_nothing_ram
    })

    function getExtUrl(extId) {
        let entry = WidgetExtensionManager.installedWidgets[extId];
        if (!entry)
            return "";

        let wj = entry.widgetJson || {
        };
        let qmlFile = wj.component || (wj.widget && wj.widget.component ? wj.widget.component : "main.qml");
        return "file://" + entry.installedPath + "/" + qmlFile;
    }

    // Static Component Definitions for built-in widgets
    Component {
        id: component_clock_cookie

        CookieClockWidget {
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

        DigitalClockWidget {
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

        NagasakiClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_nagasaki_text

        NagasakiTextClock {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_clock_word

        WordClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_clock_flex

        FlexClock {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_clock_hori

        HoriClock {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_clock_nothing

        NothingDigitalClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_nothing_wheel_clock

        NothingWheelClockWidget {
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

        DialClockWidget {
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
        id: component_wearos_arc_clock

        WearOSArcClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_concentric_clock

        ConcentricClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_month_clock

        MonthClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_scallop_dot_clock

        ScallopDotClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_scallop_number_clock

        ScallopNumberClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_circle_pointer_clock

        CirclePointerClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_triple_ring_clock

        TripleRingClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_grid_card_clock

        GridCardClockWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_clock_expressive_card

        ExpressiveCardClockWidget {
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
        id: component_nothing_ring_media

        NothingRingMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
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
        id: component_nothing_weather_circle

        NothingWeatherWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_volume_mute_pill

        VolumeMutePillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_wifi_pill

        WifiPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_bluetooth_pill

        BluetoothPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_mic_pill

        MicPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_dark_mode_pill

        DarkModePillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_screen_record_pill

        ScreenRecordPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
        }

    }

    Component {
        id: component_easy_effects_pill

        EasyEffectsPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
            wallpaperSafetyTriggered: delegateRoot.wallpaperSafetyTriggered
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
        id: component_photo

        PhotoWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_photo_1x1

        Photo1x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_photo_weather_2x1

        PhotoWeather2x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_photo_pill_2x1

        PhotoPill2x1Widget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_photo_minimal_temp_2x1

        PhotoMinimalTemp2x1Widget {
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

    Component {
        id: component_ai_chat

        AiChatWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_android_search_bar

        AndroidSearchBarWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_search_pill

        SearchPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_notes_widget

        NotesWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_notes_widget_2x1

        NotesWidget2x1 {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_compact_media

        CompactMediaWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_quick_actions

        QuickActionsWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_quote

        QuoteWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_water_reminder

        WaterReminderWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_at_a_glance

        AtAGlanceWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_cpu_pill

        CpuPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_ram_pill

        RamPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_disk_pill

        DiskPillWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_fill_cards

        ResourceFillCardsWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_nothing_disk

        NothingDiskWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_nothing_cpu

        NothingCpuWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

    }

    Component {
        id: component_resource_nothing_ram

        NothingRamWidget {
            screenWidth: delegateRoot.screenWidth
            screenHeight: delegateRoot.screenHeight
            scaledScreenWidth: delegateRoot.screenWidth
            scaledScreenHeight: delegateRoot.screenHeight
            wallpaperScale: delegateRoot.wallpaperScale
        }

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
                return WidgetExtensionManager.widgetConfigs[extId] || ({
                });
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

        Binding {
            target: widgetLoader.item
            property: "exiting"
            value: delegateRoot.exiting
            // A handful of entries map straight to a plain component rather than
            // to an AbstractBackgroundWidget, and those have no lifecycle to
            // drive — binding blindly just logs on every one of them.
            when: widgetLoader.status == Loader.Ready
                && widgetLoader.item !== null
                && widgetLoader.item.hasOwnProperty("exiting")
        }

        Binding {
            target: widgetLoader.item
            property: "screenWidth"
            value: delegateRoot.screenWidth
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }
        
        Binding {
            target: widgetLoader.item
            property: "screenHeight"
            value: delegateRoot.screenHeight
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }
        
        Binding {
            target: widgetLoader.item
            property: "scaledScreenWidth"
            value: delegateRoot.screenWidth
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }
        
        Binding {
            target: widgetLoader.item
            property: "scaledScreenHeight"
            value: delegateRoot.screenHeight
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }
        
        Binding {
            target: widgetLoader.item
            property: "wallpaperScale"
            value: delegateRoot.wallpaperScale
            when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
        }

    }

    MissingWidgetPlaceholder {
        widgetId: delegateRoot.widgetId
        widgetX: delegateRoot.widgetX
        widgetY: delegateRoot.widgetY
    }

}
