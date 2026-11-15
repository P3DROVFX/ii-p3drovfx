import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
// Widget subdir imports stay although no type below names them: they keep the
// widget folders in the module scan, so the files load by URL (see widgetUrl).
import qs.modules.ii.background.widgets.DateWidget
import qs.modules.ii.background.widgets.bluetooth
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.phone
import qs.modules.ii.background.widgets.photo
import qs.modules.ii.background.widgets.productivity
import qs.modules.ii.background.widgets.system
import qs.modules.ii.background.widgets.utility
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.wellbeing
import qs.modules.ii.background.widgets.people
import qs
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
    // Monitor this delegate draws on. Position and scale are resolved per
    // monitor from the config entry (see WidgetPlacement); the widgetX/widgetY
    // roles only carry the legacy, unforked coordinates.
    property string monitorName: ""
    // Edit Mode's lock preview is the edited screen's alone (GlobalStates.lockLookFor).
    readonly property bool editLockHere: GlobalStates.editLockLayout
        && (delegateRoot.monitorName === "" || GlobalStates.editModeMonitor === delegateRoot.monitorName)
    readonly property bool lockLookHere: GlobalStates.screenLocked || delegateRoot.editLockHere
    // While the lock look is up (a real lock or Edit Mode's Lockscreen tab)
    // the lock fork is read, which follows the desktop until forked.
    readonly property var placement: {
        const list = Config.options.background.activeWidgets;
        return WidgetPlacement.resolveIn(list, delegateRoot.instanceId, delegateRoot.monitorName, delegateRoot.lockLookHere, delegateRoot.screenWidth, delegateRoot.screenHeight);
    }
    // The entry itself, for the flags that are not placement (pinned).
    readonly property var configEntry: WidgetPlacement.findEntry(Config.options.background.activeWidgets, delegateRoot.instanceId)
    // Every screen's Repeater walks the shared model; only the screens this copy
    // is assigned to build its widget (WidgetPlacement.showsOn). The others keep
    // an empty, invisible delegate.
    readonly property bool onThisMonitor: WidgetPlacement.showsOn(delegateRoot.configEntry, delegateRoot.monitorName)
    visible: delegateRoot.onThisMonitor
    required property real wallpaperScale
    required property bool wallpaperSafetyTriggered
    required property bool lockAnimationActive
    // The desktop is covered: widgets hold their continuous updates (AbstractBackgroundWidget.live).
    property bool widgetsPaused: false
    required property var widgetSizes
    required property int widgetSizesVersion
    required property int staggerDelay
    // Set by WidgetStateManager one animation before the model entry is dropped,
    // so the widget has something to animate out with.
    required property bool exiting
    // Built-in widgets load by URL (WidgetsRegistry's qmlPath) through
    // Loader.setSource, so compiling this delegate compiles only the widget it
    // shows instead of all ~150 built-in widget types. Every built-in gets the
    // screen and wallpaper-scale bindings; the ids listed here also take the
    // properties beside them.
    readonly property var widgetExtraProps: ({
        "clock_cookie": "safety",
        "clock_digital": "safety",
        "clock_nothing": "safety",
        "nothing_wheel_clock": "safety",
        "clock_dial": "safety",
        "nothing_ring_media": "safety",
        "volume_mute_pill": "safety",
        "easyeffects_preset_portrait": "portrait",
        "easyeffects_preset_landscape": "landscape",
        "wifi_pill": "safety",
        "bluetooth_pill": "safety",
        "mic_pill": "safety",
        "dark_mode_pill": "safety",
        "screen_record_pill": "safety",
        "easy_effects_pill": "safety"
    })
    // Registry ids this delegate does not build (no inline Component was mapped
    // to them before the URL switch either).
    readonly property var unbuiltWidgetIds: ({
        "clock_nagasaki": true
    })
    readonly property string widgetUrl: {
        const id = delegateRoot.widgetId;
        if (id.startsWith("ext:"))
            return delegateRoot.getExtUrl(id.substring(4));
        if (delegateRoot.unbuiltWidgetIds[id] === true)
            return "";
        const url = WidgetsRegistry.getQmlPath(id);
        return url ? url.toString() : "";
    }
    // What the loader holds: id and URL, since the two EasyEffects preset ids
    // share one file and differ only in `landscape`.
    property string _loadedWidgetKey: ""
    property string _loadedWidgetUrl: ""
    property bool _widgetLoaderReady: false

    onWidgetUrlChanged: delegateRoot.syncWidgetLoader()
    onWidgetIdChanged: delegateRoot.syncWidgetLoader()

    function syncWidgetLoader() {
        if (!delegateRoot._widgetLoaderReady)
            return;
        const url = delegateRoot.widgetUrl;
        const key = url === "" ? "" : delegateRoot.widgetId + "|" + url;
        if (key === delegateRoot._loadedWidgetKey)
            return;
        delegateRoot._loadedWidgetKey = key;
        delegateRoot._loadedWidgetUrl = url;
        if (url === "") {
            widgetLoader.source = "";
            return;
        }
        // Extension widgets get their inputs from the Bindings on widgetLoader,
        // as before.
        if (delegateRoot.widgetId.startsWith("ext:")) {
            widgetLoader.setSource(url, {});
            return;
        }
        const props = {
            "screenWidth": Qt.binding(() => delegateRoot.screenWidth),
            "screenHeight": Qt.binding(() => delegateRoot.screenHeight),
            "scaledScreenWidth": Qt.binding(() => delegateRoot.screenWidth),
            "scaledScreenHeight": Qt.binding(() => delegateRoot.screenHeight),
            "wallpaperScale": Qt.binding(() => delegateRoot.wallpaperScale)
        };
        const extra = delegateRoot.widgetExtraProps[delegateRoot.widgetId];
        if (extra) {
            props.wallpaperSafetyTriggered = Qt.binding(() => delegateRoot.wallpaperSafetyTriggered);
            if (extra === "portrait" || extra === "landscape")
                props.landscape = extra === "landscape";
        }
        widgetLoader.setSource(url, props);
    }

    function getExtUrl(extId) {
        let entry = WidgetExtensionManager.installedWidgets[extId];
        if (!entry)
            return "";

        let wj = entry.widgetJson || {
        };
        let qmlFile = wj.component || (wj.widget && wj.widget.component ? wj.widget.component : "main.qml");
        return "file://" + entry.installedPath + "/" + qmlFile;
    }

    FadeLoader {
        id: widgetLoader

        // Whether the widget takes `paused` (extension widgets may not). Read once per
        // item: an `in` test inside the Binding's `when` would read the very property
        // that Binding writes.
        property bool takesPause: false
        onItemChanged: takesPause = item !== null && ("paused" in item)

        // Which widgets are built at all. Off the lock that is everything but
        // the lock-only ones; on it - a real lock, or Edit Mode's Lockscreen
        // tab, which draws the same layout with no lock session behind it -
        // it is the ones the lock shows. Without the tab named here a
        // lock-only widget added from it is written to the config and never
        // built, so the tab looks like it ignored the click.
        readonly property bool lockLayout: delegateRoot.lockAnimationActive || delegateRoot.editLockHere
        active: delegateRoot.onThisMonitor && (widgetLoader.keepAlive || widgetLoader.shown)
        shown: !widgetLoader.lockLayout ? (delegateRoot.lockBehavior !== "lockOnly")
            : (delegateRoot.lockBehavior === "center" || delegateRoot.lockBehavior === "keep" || delegateRoot.lockBehavior === "custom"
                || delegateRoot.lockBehavior === "lockOnly")
        // source is set by delegateRoot.syncWidgetLoader(); a URL that fails to
        // load leaves the loader empty, like an unknown id did before.
        Component.onCompleted: {
            delegateRoot._widgetLoaderReady = true;
            delegateRoot.syncWidgetLoader();
        }
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("[WidgetDelegate] could not load widget", delegateRoot.widgetId, "from", delegateRoot._loadedWidgetUrl);
        }

        Binding {
            target: widgetLoader.item
            property: "widgetInstance"
            value: {
                return {
                    "id": delegateRoot.instanceId,
                    "widgetId": delegateRoot.widgetId,
                    "x": delegateRoot.placement.x,
                    "y": delegateRoot.placement.y,
                    "scale": delegateRoot.placement.scale,
                    "monitorName": delegateRoot.monitorName,
                    "placementStrategy": delegateRoot.placementStrategy,
                    "lockBehavior": delegateRoot.lockBehavior,
                    "pinned": delegateRoot.configEntry ? delegateRoot.configEntry.pinned === true : false
                };
            }
            when: widgetLoader.status == Loader.Ready
        }

        Binding {
            target: widgetLoader.item
            property: "paused"
            value: delegateRoot.widgetsPaused
            when: widgetLoader.status == Loader.Ready && widgetLoader.takesPause
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
        widgetX: delegateRoot.placement.x
        widgetY: delegateRoot.placement.y
    }

}
