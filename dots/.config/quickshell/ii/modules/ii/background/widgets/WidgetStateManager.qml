import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

QtObject {
    id: manager

    property ListModel model: ListModel {
        id: widgetListModel
        onCountChanged: console.log("[Background] widgetListModel count changed to: " + count)
    }
    property var widgetSizes: ({})  // instanceId → {width, height} — mutated in-place by widgets
    property int widgetSizesVersion: 0  // bumped by widgets after mutating widgetSizes
    property int syncVersion: 0
    property bool staggerTransitionActive: false

    property Timer staggerTransitionReset: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            manager.staggerTransitionActive = false;
            for (let i = 0; i < widgetListModel.count; i++) {
                widgetListModel.get(i).staggerDelay = 0;
            }
        }
    }

    // ── Deferred removal ─────────────────────────────────────────────────────
    // `exiting` is set on the model entry, the delegate plays its exit, and this
    // timer runs the sync a second time with `reapDue` set so the entry is
    // actually dropped. Kept slightly longer than the exit animation so the
    // widget is never destroyed mid-fade.
    property bool reapDue: false
    property Timer reapTimer: Timer {
        interval: Math.round(260 * Appearance.animMultiplier)
        repeat: false
        onTriggered: {
            manager.reapDue = true;
            manager.syncActiveWidgets();
            manager.reapDue = false;
        }
    }
    function scheduleReap() {
        manager.reapTimer.restart();
    }

    function syncActiveWidgets() {
        let configList = Config.options.background.activeWidgets || [];
        console.log("[Background] syncActiveWidgets called. Config activeWidgets count: " + configList.length + ", current model count: " + widgetListModel.count);

        let addCount = 0;
        let moveCount = 0;

        // 1. Remove items from ListModel that are no longer in Config
        for (let i = widgetListModel.count - 1; i >= 0; i--) {
            let modelId = widgetListModel.get(i).instanceId;
            let found = false;
            for (let j = 0; j < configList.length; j++) {
                if (configList[j].id === modelId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Deferred removal: the Repeater destroys a delegate the moment
                // it leaves the model, so an exit animation had nowhere to run.
                // Flag it, let the widget animate itself out, and reap it after.
                if (!widgetListModel.get(i).exiting) {
                    widgetListModel.setProperty(i, "exiting", true);
                    manager.scheduleReap();
                } else if (manager.reapDue) {
                    widgetListModel.remove(i);
                }
            }
        }

        // 2. Add or update items in ListModel
        for (let j = 0; j < configList.length; j++) {
            let configItem = configList[j];
            let modelIndex = -1;
            for (let i = 0; i < widgetListModel.count; i++) {
                if (widgetListModel.get(i).instanceId === configItem.id) {
                    modelIndex = i;
                    break;
                }
            }

            if (modelIndex === -1) {
                widgetListModel.append({
                    "instanceId": configItem.id,
                    "widgetId": configItem.widgetId,
                    "widgetX": configItem.x,
                    "widgetY": configItem.y,
                    "placementStrategy": configItem.placementStrategy || "free",
                    "lockBehavior": configItem.lockBehavior || "hide",
                    "staggerDelay": addCount * 60,
                    "scale": configItem.scale ?? 1.0,
                    "exiting": false
                });
                addCount++;
            } else {
                let modelItem = widgetListModel.get(modelIndex);
                if (modelItem.widgetId !== configItem.widgetId) {
                    modelItem.widgetId = configItem.widgetId;
                }
                if (Math.abs(modelItem.widgetX - configItem.x) > 0.01) {
                    modelItem.widgetX = configItem.x;
                    moveCount++;
                }
                if (Math.abs(modelItem.widgetY - configItem.y) > 0.01) {
                    modelItem.widgetY = configItem.y;
                    moveCount++;
                }
                if (modelItem.placementStrategy !== configItem.placementStrategy) {
                    modelItem.placementStrategy = configItem.placementStrategy || "free";
                }
                if (modelItem.lockBehavior !== (configItem.lockBehavior || "hide")) {
                    modelItem.lockBehavior = configItem.lockBehavior || "hide";
                }
                if (Math.abs((modelItem.scale ?? 1.0) - (configItem.scale ?? 1.0)) > 0.001) {
                    modelItem.scale = configItem.scale ?? 1.0;
                }
                if (moveCount > 0 || addCount > 0) {
                    modelItem.staggerDelay = j * 60;
                }
            }
        }

        let isBulkChange = (addCount + moveCount) > 0;
        if (isBulkChange) {
            manager.staggerTransitionActive = true;
            staggerTransitionReset.restart();
        }
        manager.syncVersion++;
    }

    function maybeMigrateWidgets() {
        if (!Persistent.ready || Persistent.states.background.widgetsMigrated)
            return;

        console.log("[Background] Migrating legacy desktop widgets configuration...");
        let migrated = [];
        let centerWidget = "none";

        // Clock widget (legacy migration from unified "clock" to separate entries)
        if (Config.options.background.widgets.clock && Config.options.background.widgets.clock.enable) {
            let style = Config.options.background.widgets.clock.style || "cookie";
            let widgetId = "clock_" + style;
            let lockBehavior = (centerWidget === "clock") ? "center" : "hide";
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.clock.x ?? 1518.98,
                "y": Config.options.background.widgets.clock.y ?? 168.8,
                "placementStrategy": Config.options.background.widgets.clock.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
            // Migrate settings to new config paths
            if (style === "cookie") {
                let oldCookie = Config.options.background.widgets.clock.cookie;
                if (oldCookie) {
                    Config.options.background.widgets.clock_cookie.aiStyling = oldCookie.aiStyling;
                    Config.options.background.widgets.clock_cookie.aiStylingModel = oldCookie.aiStylingModel;
                    Config.options.background.widgets.clock_cookie.sides = oldCookie.sides;
                    Config.options.background.widgets.clock_cookie.backgroundStyle = oldCookie.backgroundStyle;
                    Config.options.background.widgets.clock_cookie.backgroundShape = oldCookie.backgroundShape;
                    Config.options.background.widgets.clock_cookie.dialNumberStyle = oldCookie.dialNumberStyle;
                    Config.options.background.widgets.clock_cookie.hourHandStyle = oldCookie.hourHandStyle;
                    Config.options.background.widgets.clock_cookie.minuteHandStyle = oldCookie.minuteHandStyle;
                    Config.options.background.widgets.clock_cookie.secondHandStyle = oldCookie.secondHandStyle;
                    Config.options.background.widgets.clock_cookie.dateStyle = oldCookie.dateStyle;
                    Config.options.background.widgets.clock_cookie.timeIndicators = oldCookie.timeIndicators;
                    Config.options.background.widgets.clock_cookie.hourMarks = oldCookie.hourMarks;
                    Config.options.background.widgets.clock_cookie.dateInClock = oldCookie.dateInClock;
                    Config.options.background.widgets.clock_cookie.constantlyRotate = oldCookie.constantlyRotate;
                }
                let oldQuote = Config.options.background.widgets.clock.quote;
                if (oldQuote) {
                    Config.options.background.widgets.clock_cookie.quoteEnable = oldQuote.enable;
                    Config.options.background.widgets.clock_cookie.quoteText = oldQuote.text;
                }
                Config.options.background.widgets.clock_cookie.disableAnimationOnLock = Config.options.background.widgets.clock.disableAnimationOnLock;
            } else if (style === "digital") {
                let oldDigital = Config.options.background.widgets.clock.digital;
                if (oldDigital) {
                    Config.options.background.widgets.clock_digital.adaptiveAlignment = oldDigital.adaptiveAlignment;
                    Config.options.background.widgets.clock_digital.showDate = oldDigital.showDate;
                    Config.options.background.widgets.clock_digital.animateChange = oldDigital.animateChange;
                    Config.options.background.widgets.clock_digital.vertical = oldDigital.vertical;
                    Config.options.background.widgets.clock_digital.colorful = oldDigital.colorful;
                    Config.options.background.widgets.clock_digital.showColon = oldDigital.showColon;
                    if (oldDigital.font) {
                        Config.options.background.widgets.clock_digital.font.weight = oldDigital.font.weight;
                        Config.options.background.widgets.clock_digital.font.width = oldDigital.font.width;
                        Config.options.background.widgets.clock_digital.font.size = oldDigital.font.size;
                        Config.options.background.widgets.clock_digital.font.roundness = oldDigital.font.roundness;
                    }
                }
                let oldQuote = Config.options.background.widgets.clock.quote;
                if (oldQuote) {
                    Config.options.background.widgets.clock_digital.quoteEnable = oldQuote.enable;
                    Config.options.background.widgets.clock_digital.quoteText = oldQuote.text;
                }
            } else if (style === "dial") {
                let oldDial = Config.options.background.widgets.clock.dial;
                if (oldDial) {
                    Config.options.background.widgets.clock_dial.showTicks = oldDial.showTicks;
                    Config.options.background.widgets.clock_dial.showMinuteHand = oldDial.showMinuteHand;
                    Config.options.background.widgets.clock_dial.enableShadows = oldDial.enableShadows;
                    Config.options.background.widgets.clock_dial.enableInnerShadow = oldDial.enableInnerShadow;
                    Config.options.background.widgets.clock_dial.expressiveColors = oldDial.expressiveColors;
                }
            }
            // Disable the old clock entry to prevent re-migration
            Config.options.background.widgets.clock.enable = false;
        }

        // Media widget
        if (Config.options.background.widgets.media.enable) {
            let style = Config.options.background.widgets.media.style || "circular";
            let widgetId = "media_" + style;
            let lockBehavior = (centerWidget === "media") ? "center" : "hide";
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.media.x ?? 249.21,
                "y": Config.options.background.widgets.media.y ?? 612.92,
                "placementStrategy": Config.options.background.widgets.media.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
        }

        // Circular Media widget
        if (Config.options.background.widgets.circular_media && Config.options.background.widgets.circular_media.enable) {
            let lockBehavior = (centerWidget === "media") ? "center" : "hide";
            migrated.push({
                "id": "widget_circular_media_migrated",
                "widgetId": "circular_media",
                "x": Config.options.background.widgets.circular_media.x ?? 249.21,
                "y": Config.options.background.widgets.circular_media.y ?? 612.92,
                "placementStrategy": Config.options.background.widgets.circular_media.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
        }

        // Weather widget
        if (Config.options.background.widgets.weather.enable) {
            let style = Config.options.background.widgets.weather.style || "default";
            let widgetId = "weather_" + style;
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.weather.x ?? 400,
                "y": Config.options.background.widgets.weather.y ?? 100,
                "placementStrategy": Config.options.background.widgets.weather.placementStrategy || "free",
                "lockBehavior": "hide"
            });
        }

        // Date widget
        if (Config.options.background.widgets.date.enable) {
            migrated.push({
                "id": "widget_date_default_migrated",
                "widgetId": "date_default",
                "x": Config.options.background.widgets.date.x ?? 100,
                "y": Config.options.background.widgets.date.y ?? 100,
                "placementStrategy": Config.options.background.widgets.date.placementStrategy || "free",
                "lockBehavior": "hide"
            });
        }

        // Calendar Minimal widget
        if (Config.options.background.widgets.calendar_minimal && Config.options.background.widgets.calendar_minimal.enable) {
            migrated.push({
                "id": "widget_calendar_minimal_migrated",
                "widgetId": "calendar_minimal",
                "x": Config.options.background.widgets.calendar_minimal.x ?? 200,
                "y": Config.options.background.widgets.calendar_minimal.y ?? 200,
                "placementStrategy": Config.options.background.widgets.calendar_minimal.placementStrategy || "free",
                "lockBehavior": "hide"
            });
        }

        Config.options.background.activeWidgets = migrated;
        Persistent.states.background.widgetsMigrated = true;
        console.log("[Background] Widget migration complete. Migrated widgets count: " + migrated.length);
    }

    property Connections activeWidgetsConn: Connections {
        target: Config.ready ? Config.options.background : null
        ignoreUnknownSignals: true
        function onActiveWidgetsChanged() {
            manager.syncActiveWidgets();
        }
    }

    // Both migrations below decide whether they have already run by reading a flag out of
    // Persistent, and a JsonAdapter serves its QML defaults - false, here - until the file behind
    // it has loaded. config.json and states.json load independently of each other, so on a boot
    // where the config wins that race the legacy migration runs a second time and rebuilds
    // activeWidgets from the old per-widget keys, discarding every lock behaviour the user had
    // set. Migrate only once Persistent has actually spoken. The plain sync is not gated on it,
    // so widgets still appear as soon as the config is readable.
    function syncNow() {
        if (!Config.ready)
            return;
        if (Persistent.ready) {
            manager.maybeMigrateWidgets();
            Config.migrateWidgetLockBehavior();
        }
        manager.syncActiveWidgets();
    }

    property Connections configConn: Connections {
        target: Config
        ignoreUnknownSignals: true
        function onReadyChanged() {
            manager.syncNow();
        }
    }

    property Connections persistentConn: Connections {
        target: Persistent
        ignoreUnknownSignals: true
        function onReadyChanged() {
            manager.syncNow();
        }
    }

    Component.onCompleted: manager.syncNow()
}
