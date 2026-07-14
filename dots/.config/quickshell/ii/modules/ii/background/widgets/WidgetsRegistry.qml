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
            "configPage": "widgets/DateDesktopWIdgetConfig.qml"
        }
    ]

    // List of user-installed widgets loaded dynamically
    property var userWidgets: []

    // Combined list of all available widgets
    readonly property var allWidgets: (builtinWidgets || []).concat(userWidgets || [])

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

    Process {
        id: listUserWidgetsProc
        command: ["python3", Directories.scriptPath + "/list_user_widgets.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let str = text.trim();
                if (!str) return;
                try {
                    let list = JSON.parse(str);
                    root.userWidgets = list;
                } catch(e) {
                    console.log("[WidgetsRegistry] Failed to parse user widgets JSON:", e, str);
                }
            }
        }
    }

    // Refresh function for registry (e.g. when widgets are installed/uninstalled)
    function refresh() {
        listUserWidgetsProc.running = false;
        listUserWidgetsProc.running = true;
    }
}
