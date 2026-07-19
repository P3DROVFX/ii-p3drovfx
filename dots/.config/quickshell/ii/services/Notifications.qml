pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

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
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
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
            if (notification === null) {
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
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
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
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
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
                root.list = root.list.concat(pending);
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
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app reactively via reassignment
        const nextLatestTime = Object.assign({}, root.latestTimeForApp);
        root.list.forEach((notif) => {
            if (!nextLatestTime[notif.appName] || notif.time > nextLatestTime[notif.appName]) {
                nextLatestTime[notif.appName] = Math.max(nextLatestTime[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(nextLatestTime).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
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
        const conf = Config.options.sounds.notificationApps;
        const lower = (appName || "").toLowerCase();
        if (conf.neverPlayApps.some(app => app.toLowerCase() === lower)) return "mute";
        if (conf.alwaysPlayApps.some(app => app.toLowerCase() === lower)) return "play";
        return conf.defaultPolicy;
    }

    function appSoundsMuted(appName) {
        const conf = Config.options.sounds.notificationApps;
        const lower = (appName || "").toLowerCase();
        return conf.neverPlayApps.some(app => app.toLowerCase() === lower);
    }

    function toggleAppSoundMute(appName) {
        if (!appName) return;
        const conf = Config.options.sounds.notificationApps;
        const lower = appName.toLowerCase();
        if (root.appSoundsMuted(appName)) {
            conf.neverPlayApps = conf.neverPlayApps.filter(app => app.toLowerCase() !== lower);
        } else {
            conf.alwaysPlayApps = conf.alwaysPlayApps.filter(app => app.toLowerCase() !== lower);
            conf.neverPlayApps = [...conf.neverPlayApps, appName];
        }
    }

    // Follows the fdo notification spec: apps can suppress the sound or request
    // a specific one via hints. Do-not-disturb (silent) mutes everything.
    function playNotificationSound(notification) {
        if (root.silent) return;
        const hints = notification.hints ?? {};
        if (hints["suppress-sound"]) return;
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
            root.playNotificationSound(notification);
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });

            // Batch notifications to avoid rapid list updates
            root._pendingNotifications.push(newNotifObject);
            batchNotificationTimer.restart();

            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                if (notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
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

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
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
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].timer.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
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

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        atomicWrites: true
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map((notif) => {
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
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.initDone()
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
