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
            "widgetId": "date_default",
            "name": Translation.tr("Date Card"),
            "category": "Date",
            "qmlPath": Qt.resolvedUrl("DateWidget/DateWidget.qml"),
            "icon": "calendar_today",
            "description": Translation.tr("A simple card showing current month and day."),
            "configPage": "widgets/DateDesktopWidgetConfig.qml"
        },
        {
            "widgetId": "photo_default",
            "name": Translation.tr("Photo"),
            "category": "Photo",
            "qmlPath": Qt.resolvedUrl("photo/PhotoWidget.qml"),
            "icon": "image",
            "description": Translation.tr("Display a personal photo on your desktop."),
            "configPage": "widgets/DesktopPhotoWidgetConfig.qml"
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
