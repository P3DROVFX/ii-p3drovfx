pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

Singleton {
    id: root

    // List of built-in widgets
    readonly property var builtinWidgets: [
        {
            "widgetId": "clock_cookie",
            "name": Translation.tr("Cookie Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ClockWidget.qml"),
            "styleOverride": "cookie",
            "icon": "schedule",
            "description": Translation.tr("A beautiful analog clock with Material You shapes and customization."),
            "configPage": "widgets/DesktopClockWidgetConfig.qml"
        },
        {
            "widgetId": "clock_digital",
            "name": Translation.tr("Digital Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ClockWidget.qml"),
            "styleOverride": "digital",
            "icon": "schedule",
            "description": Translation.tr("A modern, resizable digital clock with date and adaptive alignment."),
            "configPage": "widgets/DesktopClockWidgetConfig.qml"
        },
        {
            "widgetId": "clock_nagasaki",
            "name": Translation.tr("Nagasaki Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ClockWidget.qml"),
            "styleOverride": "nagasaki",
            "icon": "schedule",
            "description": Translation.tr("A classic Nagasaki styled clock widget."),
            "configPage": "widgets/DesktopClockWidgetConfig.qml"
        },
        {
            "widgetId": "clock_dial",
            "name": Translation.tr("Dial Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ClockWidget.qml"),
            "styleOverride": "dial",
            "icon": "schedule",
            "description": Translation.tr("A beautiful analog clock with tick marks and capsule hands."),
            "configPage": "widgets/DesktopDialClockConfig.qml"
        },
        {
            "widgetId": "clock_wearos",
            "name": Translation.tr("WearOS Clock (Watch)"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/WearOSClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A circular analog clock widget styled like a Wear OS watch face."),
            "configPage": "widgets/DesktopWearOSClockWidgetConfig.qml"
        },
        {
            "widgetId": "circular_media",
            "name": Translation.tr("Circular Media (Watch)"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/CircularMediaWidget.qml"),
            "icon": "play_circle",
            "description": Translation.tr("Circular media player widget styled like a smartwatch interface."),
            "configPage": "widgets/DesktopCircularMediaWidgetConfig.qml"
        },
        {
            "widgetId": "media_circular",
            "name": Translation.tr("Circular Media"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/MediaWidget.qml"),
            "icon": "play_circle",
            "description": Translation.tr("Circular media player widget with album art support."),
            "configPage": "widgets/DesktopMediaWidgetConfig.qml"
        },
        {
            "widgetId": "media_expressive",
            "name": Translation.tr("Expressive Media"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/ExpressiveMediaWidget.qml"),
            "icon": "music_note",
            "description": Translation.tr("Expressive and large media player widget with dynamic glow and lyrics."),
            "configPage": "widgets/DesktopMediaWidgetConfig.qml"
        },
        {
            "widgetId": "media_android",
            "name": Translation.tr("Android Media"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/AndroidMediaWidget.qml"),
            "icon": "play_circle",
            "description": Translation.tr("Beautiful Android style media player widget with dynamic colors, artwork, lyrics, and visualizer."),
            "configPage": "widgets/DesktopMediaWidgetConfig.qml"
        },
        {
            "widgetId": "media_cd",
            "name": Translation.tr("CD Media 1x1"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/CdMediaWidget.qml"),
            "icon": "album",
            "description": Translation.tr("1x1 CD media player widget with top cutout album art circle, equalizer icon, song details, and line progress slider."),
            "configPage": "widgets/DesktopCdMediaConfig.qml"
        },
        {
            "widgetId": "weather_default",
            "name": Translation.tr("Default Weather"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherWidget.qml"),
            "icon": "cloud",
            "description": Translation.tr("Compact current weather status widget."),
            "configPage": "widgets/DesktopWeatherWidgetConfig.qml"
        },
        {
            "widgetId": "weather_expressive",
            "name": Translation.tr("Expressive Weather"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/ExpressiveWeatherWidget.qml"),
            "icon": "sunny",
            "description": Translation.tr("Detailed and stylized weather card with future forecast."),
            "configPage": "widgets/DesktopWeatherWidgetConfig.qml"
        },
        {
            "widgetId": "weather_forecast",
            "name": Translation.tr("Forecast Weather 2x1"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherForecast2x1Widget.qml"),
            "icon": "partly_cloudy_day",
            "description": Translation.tr("2x1 layout weather card with hero current weather and 3-day pill forecast."),
            "configPage": "widgets/DesktopWeatherForecastConfig.qml"
        },
        {
            "widgetId": "weather_card",
            "name": Translation.tr("Weather Card 1x1"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherCard1x1Widget.qml"),
            "icon": "cloud",
            "description": Translation.tr("1x1 layout compact weather card with 3-day list forecast."),
            "configPage": "widgets/DesktopWeatherCardConfig.qml"
        },
        {
            "widgetId": "weather_icon",
            "name": Translation.tr("Weather Icon Shape"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherIconWidget.qml"),
            "icon": "sunny",
            "description": Translation.tr("1x1 Material Shape cookie weather icon widget."),
            "configPage": "widgets/DesktopWeatherIconConfig.qml"
        },
        {
            "widgetId": "weather_pill",
            "name": Translation.tr("Weather Pill 1x0.5"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherPillWidget.qml"),
            "icon": "cloud",
            "description": Translation.tr("Compact 1x0.5 weather pill widget."),
            "configPage": "widgets/DesktopWeatherPillConfig.qml"
        },
        {
            "widgetId": "weather_circle",
            "name": Translation.tr("Weather Circle Cookie"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherCircleWidget.qml"),
            "icon": "sunny",
            "description": Translation.tr("Circular weather widget with inner Cookie12Sided shape."),
            "configPage": "widgets/DesktopWeatherCircleConfig.qml"
        },
        {
            "widgetId": "weather_typography",
            "name": Translation.tr("Weather Typography"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherTypographyWidget.qml"),
            "icon": "cloud",
            "description": Translation.tr("Apple-style typography weather card widget."),
            "configPage": "widgets/DesktopWeatherTypographyConfig.qml"
        },
        {
            "widgetId": "weather_hourly",
            "name": Translation.tr("Weather Hourly 2x1"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/WeatherHourly2x1Widget.qml"),
            "icon": "sunny",
            "description": Translation.tr("2x1 weather card with hourly forecast and multi-day list."),
            "configPage": "widgets/DesktopWeatherHourlyConfig.qml"
        },
        {
            "widgetId": "date_default",
            "name": Translation.tr("Date Card"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/DateWidget.qml"),
            "icon": "calendar_today",
            "description": Translation.tr("A simple card showing current month and day."),
            "configPage": "widgets/DateDesktopWidgetConfig.qml"
        },
        {
            "widgetId": "calendar_minimal",
            "name": Translation.tr("Calendar Minimal 1x1"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarMinimalWidget.qml"),
            "icon": "calendar_month",
            "description": Translation.tr("A clean 1x1 calendar widget with weekday, day number, and month name."),
            "configPage": "widgets/DesktopCalendarMinimalWidgetConfig.qml"
        },
        {
            "widgetId": "calendar_grid",
            "name": Translation.tr("Calendar Month Grid 2x1"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarGrid2x1Widget.qml"),
            "icon": "calendar_month",
            "description": Translation.tr("A 2x1 calendar widget with date hero on left and full month grid on right."),
            "configPage": "widgets/DesktopCalendarGrid2x1Config.qml"
        },
        {
            "widgetId": "calendar_agenda",
            "name": Translation.tr("Calendar Agenda 1x1"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarAgendaWidget.qml"),
            "icon": "event",
            "description": Translation.tr("A 1x1 agenda calendar widget displaying week strip, khal events list, and bottom vertical fade."),
            "configPage": "widgets/DesktopCalendarAgendaConfig.qml"
        },
        {
            "widgetId": "calendar_next_event",
            "name": Translation.tr("Calendar Next Event 2x1"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarNextEventWidget.qml"),
            "icon": "event",
            "description": Translation.tr("A 2x1 calendar widget with day info, time until next event, event cards, and IPC floating add button."),
            "configPage": "widgets/DesktopCalendarNextEventConfig.qml"
        },
        {
            "widgetId": "calendar_pill",
            "name": Translation.tr("Calendar Pill 1x0.5"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarPillWidget.qml"),
            "icon": "calendar_today",
            "description": Translation.tr("A 1x0.5 compact pill calendar widget displaying weekday name and day number in colPrimary circle."),
            "configPage": "widgets/DesktopCalendarPillConfig.qml"
        },
        {
            "widgetId": "calendar_upcoming_3days",
            "name": Translation.tr("Calendar Upcoming 3 Days 1x1"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/CalendarUpcoming3DaysWidget.qml"),
            "icon": "calendar_view_day",
            "description": Translation.tr("A 1x1 calendar widget listing events for the next 3 days with (+) add button on current day."),
            "configPage": "widgets/DesktopCalendarUpcoming3DaysConfig.qml"
        },
        {
            "widgetId": "photo_default",
            "name": Translation.tr("Photo"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoWidget.qml"),
            "icon": "image",
            "description": Translation.tr("Display a personal photo on your desktop."),
            "configPage": "widgets/DesktopPhotoWidgetConfig.qml"
        },
        {
            "widgetId": "bluetooth_battery",
            "name": Translation.tr("Bluetooth Device Battery"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/BluetoothBatteryWidget.qml"),
            "icon": "earbuds",
            "description": Translation.tr("1x1 widget displaying connected Bluetooth earbud battery percentage and visual."),
            "configPage": "widgets/DesktopBluetoothBatteryConfig.qml"
        },
        {
            "widgetId": "bluetooth_headphone",
            "name": Translation.tr("Bluetooth Headphone 1x2"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/BluetoothHeadphoneWidget.qml"),
            "icon": "headphones",
            "description": Translation.tr("1x2 vertical widget displaying full-bleed Bluetooth headphone visual and battery percentage."),
            "configPage": "widgets/DesktopBluetoothHeadphoneConfig.qml"
        },
        {
            "widgetId": "mobile_battery",
            "name": Translation.tr("Mobile Phone Battery"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/MobileBatteryWidget.qml"),
            "icon": "smartphone",
            "description": Translation.tr("1x1 widget displaying KDE Connect mobile phone battery percentage and 3D device visual."),
            "configPage": "widgets/DesktopMobileBatteryConfig.qml"
        },
        {
            "widgetId": "bluetooth_headphone_cookie",
            "name": Translation.tr("Bluetooth Headphone Cookie"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/BluetoothHeadphoneCookieWidget.qml"),
            "icon": "headphones",
            "description": Translation.tr("1x1 Material Shape Cookie widget displaying Bluetooth headphone depth layered visual and battery percentage."),
            "configPage": "widgets/DesktopBluetoothHeadphoneCookieConfig.qml"
        },
        {
            "widgetId": "bluetooth_fill_cards",
            "name": Translation.tr("Bluetooth Fill Cards"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/BluetoothFillCardsWidget.qml"),
            "icon": "bluetooth",
            "description": Translation.tr("Responsive multi-device cards widget scaling horizontally per connected Bluetooth device with liquid battery fill."),
            "configPage": "widgets/DesktopBluetoothFillCardsConfig.qml"
        },
        {
            "widgetId": "pc_battery_bars",
            "name": Translation.tr("PC Battery Bars"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/PcBatteryBarsWidget.qml"),
            "icon": "battery_charging_full",
            "description": Translation.tr("1x1 PC computer battery widget with 5 height-decreasing level bars and dynamic charging state styling."),
            "configPage": "widgets/DesktopPcBatteryBarsConfig.qml"
        },
        {
            "widgetId": "pc_battery_cable",
            "name": Translation.tr("PC Battery Cable"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/PcBatteryCableWidget.qml"),
            "icon": "power",
            "description": Translation.tr("1x1 PC computer battery widget with custom charger cable plug visual and percentage text."),
            "configPage": "widgets/DesktopPcBatteryCableConfig.qml"
        },
        {
            "widgetId": "devices_battery_list",
            "name": Translation.tr("Connected Devices Battery List (2x1)"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/DevicesBatteryListWidget.qml"),
            "icon": "battery_full",
            "description": Translation.tr("2x1 widget featuring 4 fixed pill slots displaying PC laptop, phone, and Bluetooth device batteries."),
            "configPage": "widgets/DesktopDevicesBatteryListConfig.qml"
        },
        {
            "widgetId": "devices_battery_list_1x1",
            "name": Translation.tr("Connected Devices Battery List (1x1)"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/DevicesBatteryList1x1Widget.qml"),
            "icon": "battery_full",
            "description": Translation.tr("Compact 1x1 widget featuring 4 fixed pill slots displaying PC laptop, phone, and Bluetooth device batteries."),
            "configPage": "widgets/DesktopDevicesBatteryList1x1Config.qml"
        },
        {
            "widgetId": "bluetooth_earbuds_stem",
            "name": Translation.tr("Bluetooth Earbuds Stem"),
            "category": "Devices",
            "qmlPath": Qt.resolvedUrl("bluetooth/BluetoothEarbudsStemWidget.qml"),
            "icon": "earbuds",
            "description": Translation.tr("1x1 audio earbuds widget using stem & cushion dual SVG layers with battery level display."),
            "configPage": "widgets/DesktopBluetoothEarbudsStemConfig.qml"
        },
        {
            "widgetId": "email_inbox",
            "name": Translation.tr("Email Inbox (1x1)"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/EmailWidget.qml"),
            "icon": "mail",
            "description": Translation.tr("1x1 email inbox widget displaying latest received emails and quick action button."),
            "configPage": "widgets/DesktopEmailWidgetConfig.qml"
        },
        {
            "widgetId": "email_inbox_2x1",
            "name": Translation.tr("Email Inbox (2x1)"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/EmailWidget2x1.qml"),
            "icon": "mail",
            "description": Translation.tr("2x1 wide email inbox widget displaying latest received emails and quick action button."),
            "configPage": "widgets/DesktopEmailWidgetConfig.qml"
        }
    ]

    // Extension widgets from WidgetExtensionManager
    property var extensionWidgets: WidgetExtensionManager.ready ? WidgetExtensionManager.getRegistryEntries() : []

    // Combined list of all available widgets
    readonly property var allWidgets: (builtinWidgets || []).concat(extensionWidgets || [])

    function getWidgetMetadata(widgetId) {
        let list = allWidgets;
        for (let i = 0; i < list.length; i++) {
            if (list[i].widgetId === widgetId) {
                return list[i];
            }
        }
        return null;
    }

    function getQmlPath(widgetId) {
        let meta = getWidgetMetadata(widgetId);
        return meta ? meta.qmlPath : "";
    }

    function getStyleOverride(widgetId) {
        let meta = getWidgetMetadata(widgetId);
        return meta ? meta.styleOverride : undefined;
    }

    Connections {
        target: WidgetExtensionManager
        function onExtensionsChanged() {
            root.extensionWidgets = WidgetExtensionManager.getRegistryEntries();
        }
    }

    // Refresh function kept for external callers that may exist
    function refresh() {
        root.extensionWidgets = WidgetExtensionManager.getRegistryEntries();
    }
}
