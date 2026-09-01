pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        // Internal notifications have no freedesktop sender to keep alive.
        // They still use the same cards/actions/popup path as server traffic.
        property bool internal: false
        property list<var> customActions: []
        property string _qsFilePath: ""
        property var internalActionPayload: ({})
        property int internalExpireTimeout: -1
        property list<var> actions: {
            var base = notification ? notification.actions.map(function(action) {
                return { "identifier": action.identifier, "text": action.text };
            }) : [];
            if (customActions.length > 0) return base.concat(customActions);
            return base;
        }
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        onNotificationChanged: {
            if (notification === null && !internal) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif && notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject) {
                if (notifObject.isTransient) root.discardNotification(notificationId);
                else root.timeoutNotification(notificationId);
            }
            destroy()
        }
    }

    property bool silent: false
    readonly property bool focusedWindowFullscreen: {
        // 1. Direct ToplevelManager check
        if (ToplevelManager.activeToplevel?.wayland?.fullscreen) return true;

        // 2. Active workspace on focused monitor via Hyprland service
        const focusedWsToplevels = Hyprland.focusedMonitor?.activeWorkspace?.toplevels?.values ?? [];
        if (focusedWsToplevels.some(t => t.wayland?.fullscreen)) return true;

        // 3. Active window address in HyprlandData
        const activeAddress = ToplevelManager.activeToplevel?.HyprlandToplevel?.address;
        if (activeAddress) {
            const win = HyprlandData.windowByAddress[`0x${activeAddress}`];
            if (win && (win.fullscreen || (win.fullscreenMode !== undefined && win.fullscreenMode > 0))) return true;
        }

        // 4. Any window on current workspace marked fullscreen in HyprlandData
        const activeWsId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? HyprlandData.activeWorkspace?.id;
        if (activeWsId !== undefined && HyprlandData.windowList) {
            const fsWin = HyprlandData.windowList.find(w => w.workspace?.id === activeWsId && (w.fullscreen || (w.fullscreenMode !== undefined && w.fullscreenMode > 0)));
            if (fsWin) return true;
        }

        return false;
    }
    readonly property bool autoSilent: (Config?.options.notifications.autoDndFullscreen ?? true) && focusedWindowFullscreen
    readonly property bool effectiveSilent: silent || autoSilent
    property int unread: 0
    property var filePath: Directories.notificationsPath
    // Keep the list typed to the stable Qt base class. A list<Notif> retains the
    // generated QML type revision in its element type; after a hot reload, existing
    // Notif objects then fail assignment to the regenerated Notif type and become
    // null entries ("Cannot append Notif(...) to a QML list").
    property list<QtObject> list: []
    property var popupList: list.filter((notif) => notif && notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || effectiveSilent
    property var latestTimeForApp: ({})
    // See Config.qml for the rationale on these guards.
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500

    // Debounced disk write timer - batches rapid notification changes
    property bool _pendingDiskWrite: false
    Timer {
        id: diskWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            notifFileView.setText(stringifyList(root.list));
            root._pendingDiskWrite = false;
        }
    }
    function scheduleDiskWrite() {
        root._pendingDiskWrite = true;
        diskWriteTimer.restart();
    }
    function flushDiskWrite() {
        diskWriteTimer.stop();
        if (root._pendingDiskWrite) {
            notifFileView.setText(stringifyList(root.list));
            root._pendingDiskWrite = false;
        }
    }

    // Pending notifications queue for batching
    property var _pendingNotifications: []
    Timer {
        id: batchNotificationTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (root._pendingNotifications.length > 0) {
                const pending = root._pendingNotifications.slice();
                root._pendingNotifications = [];
                root.list = [...root.list, ...pending];
                root.scheduleDiskWrite();
            }
        }
    }
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.filter((notif) => notif).map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app reactively via reassignment
        const nextLatestTime = Object.assign({}, root.latestTimeForApp);
        root.list.forEach((notif) => {
            if (!notif) return;
            if (!nextLatestTime[notif.appName] || notif.time > nextLatestTime[notif.appName]) {
                nextLatestTime[notif.appName] = Math.max(nextLatestTime[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(nextLatestTime).forEach((appName) => {
            if (!root.list.some((notif) => notif && notif.appName === appName)) {
                delete nextLatestTime[appName];
            }
        });
        root.latestTimeForApp = nextLatestTime;
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!notif) return;
            const appNameLower = (notif.appName || "").toLowerCase();
            const isKdeConnect = appNameLower === "kdeconnect"
                || appNameLower === "kde connect"
                || appNameLower === "org.kde.kdeconnect"
                || KdeConnectService.devices.some(d => d.name && d.name.toLowerCase() === appNameLower);

            if (isKdeConnect && KdeConnectService._enabled && KdeConnectService.activeReachable) {
                return;
            }

            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    // Computed group bindings - automatically cached by the QML engine and re-evaluated reactively.
    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // fdo notification categories → sound naming spec events. Exact match is
    // tried first, then the part before the first dot ("im.received" → "im").
    readonly property var categorySoundMap: ({
        "im.received": "message-new-instant",
        "im": "message",
        "email.arrived": "message-new-email",
        "email": "message-new-email",
        "call.incoming": "phone-incoming-call",
        "device.added": "device-added",
        "device.removed": "device-removed",
        "device.error": "dialog-error",
        "network.connected": "network-connectivity-established",
        "network.disconnected": "network-connectivity-lost",
        "transfer.complete": "complete",
        "transfer.error": "dialog-error"
    })

    function soundPolicyFor(appName) {
        const conf = Config.options?.sounds;
        if (!conf) return "play";
        const lower = (appName || "").toLowerCase();
        const neverApps = conf.neverPlayApps ?? [];
        const alwaysApps = conf.alwaysPlayApps ?? [];
        if (neverApps.some(app => app.toLowerCase() === lower)) return "mute";
        if (alwaysApps.some(app => app.toLowerCase() === lower)) return "play";
        return conf.notificationDefaultPolicy ?? "play";
    }

    function appSoundsMuted(appName) {
        const conf = Config.options?.sounds;
        if (!conf) return false;
        const lower = (appName || "").toLowerCase();
        const neverApps = conf.neverPlayApps ?? [];
        return neverApps.some(app => app.toLowerCase() === lower);
    }

    function toggleAppSoundMute(appName) {
        if (!appName) return;
        const conf = Config.options?.sounds;
        if (!conf) return;
        const lower = appName.toLowerCase();
        const neverApps = conf.neverPlayApps ?? [];
        const alwaysApps = conf.alwaysPlayApps ?? [];
        if (root.appSoundsMuted(appName)) {
            conf.neverPlayApps = neverApps.filter(app => app.toLowerCase() !== lower);
        } else {
            conf.alwaysPlayApps = alwaysApps.filter(app => app.toLowerCase() !== lower);
            conf.neverPlayApps = [...neverApps, appName];
        }
    }

    // Follows the fdo notification spec: apps can suppress the sound or request
    // a specific one via hints. Do-not-disturb (silent) mutes everything.
    function playNotificationSound(notification) {
        if (root.effectiveSilent) return;
        const hints = notification.hints ?? {};
        if (hints["suppress-sound"] || notification.expireTimeout === 0) return;
        if (root.soundPolicyFor(notification.appName) === "mute") return;

        if (hints["sound-file"]) {
            SoundService.playEventFile("notifications", hints["sound-file"]);
            return;
        }

        const events = [];
        if (hints["sound-name"]) events.push(hints["sound-name"]);
        const category = hints["category"] ?? "";
        if (category !== "") {
            if (root.categorySoundMap[category]) events.push(root.categorySoundMap[category]);
            const prefix = category.split(".")[0];
            if (root.categorySoundMap[prefix]) events.push(root.categorySoundMap[prefix]);
        }
        if (notification.urgency === NotificationUrgency.Critical) events.push("dialog-warning");
        events.push("message-new-instant");
        SoundService.playEvent("notifications", events);
    }

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);
    // The sender of an internal notification is this process, so custom action
    // identifiers come back here rather than trying to call a dead notify-send.
    signal internalActionInvoked(string identifier, int notificationId, var payload);

    // A replacement notification keeps the freedesktop notification id. Keep
    // the same wrapper too, otherwise a long-running task such as an Ollama
    // pull would fill the center with one entry per percentage update.
    function findTrackedNotification(notificationId: int): var {
        const listed = root.list.find(notif => notif && notif.notificationId === notificationId);
        if (listed)
            return listed;
        return root._pendingNotifications.find(notif => notif && notif.notificationId === notificationId) ?? null;
    }

    function armNotificationTimeout(notifObject, notification) {
        const expireTimeout = notification?.expireTimeout ?? notifObject?.internalExpireTimeout ?? -1;
        if (root.popupInhibited || expireTimeout === 0)
            return;
        const interval = expireTimeout < 0
            ? (Config?.options.notifications.timeout ?? 7000)
            : expireTimeout;
        notifObject.popup = true;
        if (notifObject.timer) {
            notifObject.timer.interval = interval;
            notifObject.timer.restart();
        } else {
            notifObject.timer = notifTimerComponent.createObject(root, {
                "notificationId": notifObject.notificationId,
                "interval": interval,
            });
        }
    }

    function nextInternalNotificationId(): int {
        let candidate = -1;
        const used = new Set(Array.from(root.list ?? []).concat(root._pendingNotifications ?? [])
            .filter(notif => notif !== null && notif !== undefined)
            .map(notif => Number(notif.notificationId)));
        while (used.has(candidate))
            candidate--;
        return candidate;
    }

    /**
     * Adds a shell-owned notification without spawning notify-send. Actions
     * are regular `customActions`, so every notification surface dispatches
     * them through executeShellAction and the caller receives one signal.
     */
    function publishInternalNotification(options: var): var {
        if (root.effectiveSilent)
            return null;
        const notificationId = root.nextInternalNotificationId();
        const appName = String(options?.appName ?? "Quickshell");
        const notifObject = notifComponent.createObject(root, {
            "notificationId": notificationId,
            "internal": true,
            "appName": appName,
            "appIcon": String(options?.appIcon ?? ""),
            "summary": String(options?.summary ?? ""),
            "body": String(options?.body ?? ""),
            "urgency": String(options?.urgency ?? "normal"),
            "time": Date.now(),
            "internalExpireTimeout": Number(options?.expireTimeout ?? -1)
        });
        if (!notifObject)
            return null;
        notifObject.customActions = Array.from(options?.actions ?? []).filter(action => {
            return String(action?.identifier ?? "").startsWith("__qs_")
                && String(action?.text ?? "").length > 0;
        });
        notifObject.internalActionPayload = options?.actionPayload ?? ({});
        root._pendingNotifications.push(notifObject);
        batchNotificationTimer.restart();
        if (!root.popupInhibited) {
            root.armNotificationTimeout(notifObject, null);
            root.unread++;
        }
        if (options?.sound === true && !root.appSoundsMuted(appName))
            SoundService.playEvent("notifications", ["message-new-instant"]);
        root.notify(notifObject);
        root.scheduleDiskWrite();
        return notificationId;
    }

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            const appNameLower = (notification.appName || "").toLowerCase();
            const isKdeConnect = appNameLower === "kdeconnect"
                || appNameLower === "kde connect"
                || appNameLower === "org.kde.kdeconnect"
                || KdeConnectService.devices.some(d => d.name && d.name.toLowerCase() === appNameLower);

            if (isKdeConnect && KdeConnectService._enabled && KdeConnectService.activeReachable) {
                notification.tracked = true;
                return;
            }

            notification.tracked = true
            const notificationId = notification.id + root.idOffset;
            const existingNotifObject = root.findTrackedNotification(notificationId);
            if (existingNotifObject) {
                existingNotifObject.notification = notification;
                existingNotifObject.time = Date.now();
                root._handleShellNotification(existingNotifObject);
                root.armNotificationTimeout(existingNotifObject, notification);
                root.notify(existingNotifObject);
                root.triggerListChange();
                root.scheduleDiskWrite();
                return;
            }

            try {
                root.playNotificationSound(notification);
            } catch (e) {
                console.log("[Notifications] Sound playback error: " + e);
            }
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notificationId,
                "notification": notification,
                "time": Date.now(),
            });

            root._handleShellNotification(newNotifObject);

            // Batch notifications to avoid rapid list updates
            root._pendingNotifications.push(newNotifObject);
            batchNotificationTimer.restart();

            // Popup
            if (!root.popupInhibited) {
                root.armNotificationTimeout(newNotifObject, notification);
                root.unread++;
            }
            root.notify(newNotifObject);
            // Schedule disk write instead of immediate write
            root.scheduleDiskWrite();
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    // Inject QML-handled action buttons for shell-internal notifications (screenshots, recordings).
    // Actions prefixed with "__qs_" are handled directly in QML via Quickshell.execDetached
    // instead of action.invoke(), since the original sender (notify-send) has already exited.
    function _handleShellNotification(notifObj) {
        var appName = notifObj.appName || "";
        var appIcon = notifObj.appIcon || "";
        var body = notifObj.body || "";

        // notify-send -i camera-photo → appIcon === "camera-photo"
        var isScreenshot = appIcon === "camera-photo";
        // notify-send -a 'Recorder' → appName === "Recorder"
        var isRecording = appName === "Recorder";

        // The "Keep awake" timer warns before it expires and offers to push the deadline out.
        // Matched on a private hint rather than the icon: notify-send's -i doesn't reach appIcon.
        if (notifObj.notification?.hints?.["x-qs-notif"] === "keepawake-warn") {
            notifObj.customActions = [
                { "identifier": "__qs_keepawake_extend", "text": Translation.tr("Extend %1").arg(Idle.formatMinutes(Idle.extendMinutes)) },
                { "identifier": "__qs_keepawake_off", "text": Translation.tr("Stop") }
            ];
            return;
        }

        if (!isScreenshot && !isRecording) return;

        // Parse file path from body: "Saved to: /path" or "Saved to /path"
        var match = body.match(/(?:Saved to:?|Copied to)\s*(.+)/i);
        if (!match) return;
        var filePath = match[1].trim();
        if (!filePath || filePath.charAt(0) !== "/") return;

        var actions = [];
        if (isScreenshot) {
            actions.push(
                { "identifier": "__qs_open_file", "text": Translation.tr("Open") },
                { "identifier": "__qs_open_folder", "text": Translation.tr("Folder") },
                { "identifier": "__qs_delete_file", "text": Translation.tr("Delete") }
            );
        } else if (isRecording) {
            actions.push(
                { "identifier": "__qs_open_file", "text": Translation.tr("Open") },
                { "identifier": "__qs_open_folder", "text": Translation.tr("Folder") }
            );
        }

        notifObj.customActions = actions;
        notifObj._qsFilePath = filePath;
    }

    // Execute a QML-handled notification action (identified by "__qs_" prefix).
    function executeShellAction(notifObj, identifier) {
        if (String(identifier).startsWith("__qs_calendar_")) {
            root.internalActionInvoked(identifier, notifObj?.notificationId ?? 0, notifObj?.internalActionPayload ?? ({}));
            return;
        }
        // Keep-awake actions carry no file, so they're handled before the file-path guard
        if (identifier === "__qs_keepawake_extend") {
            Idle.extendBy(Idle.extendMinutes);
            return;
        } else if (identifier === "__qs_keepawake_off") {
            Idle.toggleInhibit(false);
            return;
        }

        var filePath = notifObj._qsFilePath || "";
        if (!filePath) return;

        if (identifier === "__qs_open_file") {
            Quickshell.execDetached(["bash", "-c", 'xdg-open "$1"', "_", filePath]);
        } else if (identifier === "__qs_open_folder") {
            var dirPath = filePath.replace(/\/[^\/]*$/, "");
            Quickshell.execDetached(["bash", "-c", 'xdg-open "$1"', "_", dirPath]);
        } else if (identifier === "__qs_delete_file") {
            Quickshell.execDetached(["bash", "-c", 'rm -f "$1"', "_", filePath]);
        }
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif && notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            root.list.splice(index, 1);
            root.scheduleDiskWrite();
            triggerListChange()
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardMultipleNotifications(ids) {
        if (!ids || ids.length === 0) return;
        const idSet = new Set(ids);
        root.list = root.list.filter(notif => notif && !idSet.has(notif.notificationId));
        root.scheduleDiskWrite();
        triggerListChange();
        notifServer.trackedNotifications.values.forEach(notif => {
            if (idSet.has(notif.id + root.idOffset)) {
                notif.dismiss();
            }
        });
        ids.forEach(id => root.discard(id));
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        root.scheduleDiskWrite();
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif && notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].timer.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif && notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            action.invoke()
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    property bool _initialized: false

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        atomicWrites: true
        onLoaded: {
            if (root._initialized) return;
            const fileContents = notifFileView.text();
            try {
                const parsed = JSON.parse(fileContents || "[]");
                root.list = parsed.map((notif) => {
                    return notifComponent.createObject(root, {
                        "notificationId": notif.notificationId,
                        "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                        "appIcon": notif.appIcon,
                        "appName": notif.appName,
                        "body": notif.body,
                        "image": notif.image,
                        "summary": notif.summary,
                        "time": notif.time,
                        "urgency": notif.urgency,
                    });
                });
            } catch (e) {
                console.log("[Notifications] Error parsing notifications JSON: " + e);
            }
            // Find largest notificationId
            let maxId = 0;
            root.list.forEach((notif) => {
                if (!notif) return;
                maxId = Math.max(maxId, notif.notificationId);
            });

            console.log("[Notifications] File loaded");
            root.idOffset = maxId;
            root._initialized = true;
            root.initDone();
        }
        onLoadFailed: (error) => {
            if(error != FileViewError.FileNotFound) {
                console.log("[Notifications] Error loading file: " + error);
                return;
            }
            // Lazy-rstoration: a transient missing file (hot-reload / restart /
            // partial disk I/O) should not erase the user's existing
            // notifications history. Only seed an empty list past the grace
            // window if the file is genuinely absent.
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                console.log("[Notifications] File genuinely missing, creating new file.")
                root.list = []
                root.scheduleDiskWrite();
            } else {
                missingFileRetryTimer.restart()
            }
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: notifFileView.reload()
    }
}
