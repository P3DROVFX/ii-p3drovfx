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
            "qmlPath": Qt.resolvedUrl("clock/CookieClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A beautiful analog clock with Material You shapes and customization."),
            "configPage": "widgets/DesktopClockWidgetConfig.qml"
        },
        {
            "widgetId": "clock_digital",
            "name": Translation.tr("Digital Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/DigitalClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A modern, resizable digital clock with date and adaptive alignment."),
            "configPage": "widgets/DesktopDigitalClockConfig.qml"
        },
        {
            "widgetId": "clock_nagasaki",
            "name": Translation.tr("Nagasaki Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/NagasakiClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A classic Nagasaki styled clock widget."),
            "configPage": "widgets/DesktopNagasakiClockConfig.qml"
        },
        {
            "widgetId": "clock_flex",
            "name": Translation.tr("Flex Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/FlexClock.qml"),
            "icon": "schedule",
            "description": Translation.tr("A 1x1 2x2 grid clock with Google Sans Flex font, checkerboard diagonal colors, and die-cut sticker cutout effect."),
            "configPage": "widgets/DesktopFlexClockConfig.qml"
        },
        {
            "widgetId": "clock_hori",
            "name": Translation.tr("Hori Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/HoriClock.qml"),
            "icon": "schedule",
            "description": Translation.tr("A 1x1 horizontal interlocking clock with HH:MM layout, colon separator, and Google Sans Flex font."),
            "configPage": "widgets/DesktopHoriClockConfig.qml"
        },
        {
            "widgetId": "clock_nothing",
            "name": Translation.tr("Nothing Digital Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/NothingDigitalClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A 1x1 Nothing OS styled digital clock widget with Ndot dot-matrix typography, stacked hours/minutes, AM/PM chip, and date."),
            "configPage": "widgets/DesktopNothingClockConfig.qml"
        },
        {
            "widgetId": "nothing_wheel_clock",
            "name": Translation.tr("Nothing Wheel Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/NothingWheelClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("NothingOS style clock widget with date header, big hours, 3-dot indicator, and minute wheel."),
            "configPage": "widgets/DesktopNothingWheelClockConfig.qml"
        },
        {
            "widgetId": "nagasaki_text",
            "name": Translation.tr("Nagasaki Text Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/NagasakiTextClock.qml"),
            "icon": "schedule",
            "description": Translation.tr("A minimal 1x1 clock displaying time in Nagasaki font with solid color text."),
            "configPage": "widgets/DesktopNagasakiTextClockConfig.qml"
        },
        {
            "widgetId": "clock_word",
            "name": Translation.tr("Word Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/WordClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A 1x1 textual clock with the hour and minute written in words."),
            "configPage": "widgets/DesktopWordClockConfig.qml"
        },
        {
            "widgetId": "clock_dial",
            "name": Translation.tr("Dial Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/DialClockWidget.qml"),
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
            "widgetId": "wearos_arc_clock",
            "name": Translation.tr("WearOS Arc Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/WearOSArcClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A circular 1x1 clock inspired by Wear OS with customizable arc gauges, date-minutes vertical capsule selector, calendar/to-do bottom text, and premium glass reflections."),
            "configPage": "widgets/DesktopWearOSArcClockConfig.qml"
        },
        {
            "widgetId": "concentric_clock",
            "name": Translation.tr("Concentric Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ConcentricClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A Pixel Watch-inspired concentric dial clock with modular complications and interactive customization."),
            "configPage": "widgets/DesktopConcentricClockConfig.qml"
        },
        {
            "widgetId": "month_clock",
            "name": Translation.tr("Month Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/MonthClockWidget.qml"),
            "icon": "calendar_month",
            "description": Translation.tr("A three-ring calendar dial showing months, days, and weekdays with pill indicators for today."),
            "configPage": "widgets/DesktopMonthClockConfig.qml"
        },
        {
            "widgetId": "scallop_dot_clock",
            "name": Translation.tr("Scallop Dot Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ScallopDotClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("An organic Material You scallop clock face with discrete 5-minute apex minute bubbles and hour indicators."),
            "configPage": "widgets/DesktopScallopDotClockConfig.qml"
        },
        {
            "widgetId": "scallop_number_clock",
            "name": Translation.tr("Scallop Number Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ScallopNumberClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A Scallop clock face with outer 5-minute step numbers, inner 1-12 hour numbers, and a center date badge."),
            "configPage": "widgets/DesktopScallopNumberClockConfig.qml"
        },
        {
            "widgetId": "circle_pointer_clock",
            "name": Translation.tr("Circle Pointer Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/CirclePointerClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A concentric circle clock featuring outer minute step numbers, an intermediate circle with a smooth minute pointer tab, and a central two-digit hour circle."),
            "configPage": "widgets/DesktopCirclePointerClockConfig.qml"
        },
        {
            "widgetId": "triple_ring_clock",
            "name": Translation.tr("Triple Ring Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/TripleRingClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A concentric disc clock face with three rotating rings for hours, minutes, and seconds, and a fixed 3 o'clock readout pointer arrow."),
            "configPage": "widgets/DesktopTripleRingClockConfig.qml"
        },
        {
            "widgetId": "grid_card_clock",
            "name": Translation.tr("Grid Card Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/GridCardClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A stylized background clock with vertically stretched typography based on Material 3 cards.")
        },
        {
            "widgetId": "clock_expressive_card",
            "name": Translation.tr("Expressive Card Clock"),
            "category": "Clock",
            "qmlPath": Qt.resolvedUrl("clock/ExpressiveCardClockWidget.qml"),
            "icon": "schedule",
            "description": Translation.tr("A 1x1 clock with big time, month/day, temp & weather icon and expressive background.")
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
            "configPage": "widgets/DesktopExpressiveMediaConfig.qml"
        },
        {
            "widgetId": "media_android",
            "name": Translation.tr("Android Media"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/AndroidMediaWidget.qml"),
            "icon": "play_circle",
            "description": Translation.tr("Beautiful Android style media player widget with dynamic colors, artwork, lyrics, and visualizer.")
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
            "widgetId": "nothing_ring_media",
            "name": Translation.tr("Nothing Ring Media 1x1"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/NothingRingMediaWidget.qml"),
            "icon": "graphic_eq",
            "description": Translation.tr("1x1 Nothing OS style circular progress media widget with empty state support."),
            "configPage": "widgets/DesktopNothingRingMediaConfig.qml"
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
            "widgetId": "nothing_weather_circle",
            "name": Translation.tr("Nothing Weather Circle"),
            "category": "Weather",
            "qmlPath": Qt.resolvedUrl("weather/NothingWeatherWidget.qml"),
            "icon": "cloud",
            "description": Translation.tr("NothingOS style dot-matrix circular weather widget."),
            "configPage": "widgets/DesktopNothingWeatherConfig.qml"
        },
        {
            "widgetId": "volume_mute_pill",
            "name": Translation.tr("Volume Mute Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/VolumeMutePillWidget.qml"),
            "icon": "volume_off",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for volume mute."),
            "configPage": "widgets/DesktopVolumeMuteConfig.qml"
        },
        {
            "widgetId": "wifi_pill",
            "name": Translation.tr("Wi-Fi Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/WifiPillWidget.qml"),
            "icon": "wifi",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for Wi-Fi.")
        },
        {
            "widgetId": "bluetooth_pill",
            "name": Translation.tr("Bluetooth Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/BluetoothPillWidget.qml"),
            "icon": "bluetooth",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for Bluetooth.")
        },
        {
            "widgetId": "mic_pill",
            "name": Translation.tr("Microphone Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/MicPillWidget.qml"),
            "icon": "mic",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for microphone mute.")
        },
        {
            "widgetId": "dark_mode_pill",
            "name": Translation.tr("Dark Mode Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/DarkModePillWidget.qml"),
            "icon": "dark_mode",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for Dark Mode.")
        },
        {
            "widgetId": "screen_record_pill",
            "name": Translation.tr("Screen Record Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/ScreenRecordPillWidget.qml"),
            "icon": "videocam",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for screen recording.")
        },
        {
            "widgetId": "easy_effects_pill",
            "name": Translation.tr("EasyEffects Pill 1x0.5"),
            "category": "System",
            "qmlPath": Qt.resolvedUrl("system/EasyEffectsPillWidget.qml"),
            "icon": "graphic_eq",
            "description": Translation.tr("1x0.5 system quick toggle pill widget for EasyEffects.")
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
            "widgetId": "photo",
            "name": Translation.tr("Photo"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoWidget.qml"),
            "icon": "image",
            "description": Translation.tr("Display a personal photo on your desktop."),
            "configPage": "widgets/DesktopPhotoWidgetConfig.qml"
        },
        {
            "widgetId": "photo_1x1",
            "name": Translation.tr("Photo 1x1"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/Photo1x1Widget.qml"),
            "icon": "image",
            "description": Translation.tr("Compact 1x1 Photo widget masked inside any customizable MaterialShape."),
            "configPage": "widgets/DesktopPhoto1x1Config.qml"
        },
        {
            "widgetId": "photo_weather_2x1",
            "name": Translation.tr("Photo Weather (2x1)"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoWeather2x1Widget.qml"),
            "icon": "image",
            "description": Translation.tr("2x1 Photo widget with weather condition description, location, temperature, and condition icon."),
            "configPage": "widgets/DesktopPhotoWeather2x1WidgetConfig.qml"
        },
        {
            "widgetId": "photo_pill_2x1",
            "name": Translation.tr("Photo Pill Badge (2x1)"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoPill2x1Widget.qml"),
            "icon": "image",
            "description": Translation.tr("2x1 Photo widget with border and bottom-left Photos pill badge."),
            "configPage": "widgets/DesktopPhotoPill2x1WidgetConfig.qml"
        },
        {
            "widgetId": "photo_minimal_temp_2x1",
            "name": Translation.tr("Photo Minimal Temp (2x1)"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoMinimalTemp2x1Widget.qml"),
            "icon": "image",
            "description": Translation.tr("2x1 Photo widget with inner image container and bottom-right temperature badge."),
            "configPage": "widgets/DesktopPhotoMinimalTemp2x1WidgetConfig.qml"
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
        },
        {
            "widgetId": "ai_chat",
            "name": Translation.tr("AI Chat"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/AiChatWidget.qml"),
            "icon": "auto_awesome",
            "description": Translation.tr("1x1 AI assistant widget with spark icon and quick access to AI chat sidebar."),
            "configPage": "widgets/DesktopAiChatConfig.qml"
        },
        {
            "widgetId": "notes_widget",
            "name": Translation.tr("Notes (1x1)"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/NotesWidget.qml"),
            "icon": "note_stack",
            "description": Translation.tr("1x1 notes widget with vertical scroll and direct notes editor."),
            "configPage": "widgets/DesktopNotesWidgetConfig.qml"
        },
        {
            "widgetId": "notes_widget_2x1",
            "name": Translation.tr("Notes (2x1)"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/NotesWidget2x1.qml"),
            "icon": "note_stack",
            "description": Translation.tr("2x1 wide notes widget with header, vertical scroll, and direct notes editor."),
            "configPage": "widgets/DesktopNotesWidgetConfig.qml"
        },
        {
            "widgetId": "compact_media",
            "name": Translation.tr("Compact Media (2x1)"),
            "category": "Media",
            "qmlPath": Qt.resolvedUrl("media/CompactMediaWidget.qml"),
            "icon": "graphic_eq",
            "description": Translation.tr("Minimal 2x1 media widget with three colored sections: track title, play/pause, and skip next."),
            "configPage": "widgets/DesktopCompactMediaConfig.qml"
        },
        {
            "widgetId": "quick_actions",
            "name": Translation.tr("Quick Actions"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/QuickActionsWidget.qml"),
            "icon": "widgets",
            "description": Translation.tr("1x1 quick launch widget with configurable module shortcuts. Bottom buttons are customizable."),
            "configPage": "widgets/DesktopQuickActionsConfig.qml"
        },
        {
            "widgetId": "android_search_bar",
            "name": Translation.tr("Android Search Bar"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/AndroidSearchBarWidget.qml"),
            "icon": "search",
            "description": Translation.tr("0.5x2 Android Pixel search bar with Google logo, inner search pill, and customizable filled action buttons."),
            "configPage": "widgets/DesktopAndroidSearchBarConfig.qml"
        },
        {
            "widgetId": "search_pill",
            "name": Translation.tr("Search Pill"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/SearchPillWidget.qml"),
            "icon": "auto_awesome",
            "description": Translation.tr("Wide search pill with a dynamic sparkle action and three configurable provider buttons."),
            "configPage": "widgets/DesktopSearchPillConfig.qml"
        },
        {
            "widgetId": "quote",
            "name": Translation.tr("Quote"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/QuoteWidget.qml"),
            "icon": "format_quote",
            "description": Translation.tr("1x1 widget displaying a customizable quote with decorative quote marks."),
            "configPage": "widgets/DesktopQuoteConfig.qml"
        },
        {
            "widgetId": "water_reminder",
            "name": Translation.tr("Water Reminder"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/WaterReminderWidget.qml"),
            "icon": "water_drop",
            "description": Translation.tr("1x1 hydration tracker widget with a progress track, daily goal, and periodic water reminders."),
            "configPage": "widgets/DesktopWaterReminderConfig.qml"
        },
        {
            "widgetId": "at_a_glance",
            "name": Translation.tr("At a Glance"),
            "category": "Utility",
            "qmlPath": Qt.resolvedUrl("utility/AtAGlanceWidget.qml"),
            "icon": "dashboard",
            "description": Translation.tr("Android-inspired context widget combining media, calendar, sports, and current weather."),
            "configPage": "widgets/DesktopAtAGlanceConfig.qml"
        },
        {
            "widgetId": "resource_cpu_pill",
            "name": Translation.tr("CPU Resource Pill"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/CpuPillWidget.qml"),
            "icon": "memory",
            "description": Translation.tr("Capsule pill widget displaying real-time CPU usage percentage, temperature, and progress fill."),
            "configPage": "widgets/DesktopCpuPillConfig.qml"
        },
        {
            "widgetId": "resource_ram_pill",
            "name": Translation.tr("RAM Resource Pill"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/RamPillWidget.qml"),
            "icon": "memory_alt",
            "description": Translation.tr("Capsule pill widget displaying real-time RAM memory usage, GB stats, and progress fill."),
            "configPage": "widgets/DesktopRamPillConfig.qml"
        },
        {
            "widgetId": "resource_disk_pill",
            "name": Translation.tr("Disk Resource Pill"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/DiskPillWidget.qml"),
            "icon": "hard_drive",
            "description": Translation.tr("Capsule pill widget displaying real-time Disk storage usage, GB stats, and progress fill."),
            "configPage": "widgets/DesktopDiskPillConfig.qml"
        },
        {
            "widgetId": "resource_fill_cards",
            "name": Translation.tr("Resource Fill Cards"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/ResourceFillCardsWidget.qml"),
            "icon": "donut_large",
            "description": Translation.tr("Dynamic 1x1 fill cards widget combining CPU Usage, RAM Memory, and Disk Storage. Scales horizontally or vertically per active toggle (1x1, 2x1, or 3x1)."),
            "configPage": "widgets/DesktopResourceFillCardsConfig.qml"
        },
        {
            "widgetId": "resource_nothing_disk",
            "name": Translation.tr("Nothing Storage Widget"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/NothingDiskWidget.qml"),
            "icon": "hard_drive",
            "description": Translation.tr("Nothing OS styled 1x0.5 storage widget with segmented progress bar and Ndot font."),
            "configPage": ""
        },
        {
            "widgetId": "resource_nothing_cpu",
            "name": Translation.tr("Nothing CPU Widget"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/NothingCpuWidget.qml"),
            "icon": "memory",
            "description": Translation.tr("Nothing OS styled 1x0.5 CPU usage widget with segmented progress bar and Ndot font."),
            "configPage": ""
        },
        {
            "widgetId": "resource_nothing_ram",
            "name": Translation.tr("Nothing RAM Widget"),
            "category": "Resources",
            "qmlPath": Qt.resolvedUrl("utility/NothingRamWidget.qml"),
            "icon": "memory_alt",
            "description": Translation.tr("Nothing OS styled 1x0.5 RAM memory widget with segmented progress bar and Ndot font."),
            "configPage": ""
        },
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
