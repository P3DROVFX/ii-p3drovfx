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
        id: component_photo_default
        PhotoWidget {
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
        "weather_default": component_weather_default,
        "weather_expressive": component_weather_expressive,
        "date_default": component_date_default,
        "photo_default": component_photo_default
    })

    function getExtUrl(extId) {
        let entry = WidgetExtensionManager.installedWidgets[extId];
        if (!entry) return "";
        let wj = entry.widgetJson || {};
        let qmlFile = wj.component ||
            (wj.widget && wj.widget.component ? wj.widget.component : "main.qml");
        return "file://" + entry.installedPath + "/" + qmlFile;
    }

    FadeLoader {
        id: widgetLoader
        shown: !delegateRoot.lockAnimationActive 
            ? (delegateRoot.lockBehavior !== "lockOnly")
            : (delegateRoot.lockBehavior === "center" || delegateRoot.lockBehavior === "keep" || delegateRoot.lockBehavior === "lockOnly")
        
        source: delegateRoot.widgetId.startsWith("ext:")
            ? delegateRoot.getExtUrl(delegateRoot.widgetId.substring(4))
            : ""

        sourceComponent: delegateRoot.widgetId.startsWith("ext:")
            ? null
            : (delegateRoot.widgetComponentMap[delegateRoot.widgetId] || null)

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
                if (!delegateRoot.widgetId.startsWith("ext:")) return null;
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
    }

    MissingWidgetPlaceholder {
        widgetId: delegateRoot.widgetId
        widgetX: delegateRoot.widgetX
        widgetY: delegateRoot.widgetY
    }
}
