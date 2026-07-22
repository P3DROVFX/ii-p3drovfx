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
                widgetListModel.remove(i);
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
                    "staggerDelay": addCount * 60
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
        if (Persistent.states.background.widgetsMigrated) return;
        
        console.log("[Background] Migrating legacy desktop widgets configuration...");
        let migrated = [];
        let centerWidget = "none";
        
        // Clock widget
        if (Config.options.background.widgets.clock.enable) {
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

    property Connections configConn: Connections {
        target: Config
        ignoreUnknownSignals: true
        function onReadyChanged() {
            if (Config.ready) {
                manager.maybeMigrateWidgets();
                Config.migrateWidgetLockBehavior();
                manager.syncActiveWidgets();
            }
        }
    }

    Component.onCompleted: {
        if (Config.ready) {
            manager.maybeMigrateWidgets();
            Config.migrateWidgetLockBehavior();
            manager.syncActiveWidgets();
        }
    }
}
