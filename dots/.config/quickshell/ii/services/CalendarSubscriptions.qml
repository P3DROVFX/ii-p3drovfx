pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Read-only HTTP ICS subscriptions for the timetable.
 *
 * The Python bridge owns the two small marked regions in the user's khal and
 * vdirsyncer configs. Keeping that text manipulation out of QML gives it an
 * atomic, testable path and ensures neither config is rewritten wholesale.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.ready
    readonly property string helperPath: Directories.scriptPath + "/calendar/subscriptions.py"
    readonly property string configRoot: FileUtils.trimFileProtocol(Directories.config)
    readonly property string stateRoot: FileUtils.trimFileProtocol(Directories.state)
    readonly property string vdirsyncerConfigPath: root.configRoot + "/vdirsyncer/config"
    readonly property string khalConfigPath: root.configRoot + "/khal/config"
    readonly property string vdirsyncerStatusPath: root.stateRoot + "/vdirsyncer/status"
    readonly property string subscriptionRoot: root.stateRoot + "/vdirsyncer/timetable-subscriptions"
    readonly property string outlookRoot: root.stateRoot + "/calendar/timetable-outlook"

    property string lastError: ""
    property bool applying: false
    property bool syncInProgress: false
    property bool applyQueued: false
    property var managedCalendars: []
    readonly property bool importsEnabled: Config.options?.calendar?.timetable?.imports?.enable ?? false
    readonly property bool outlookEnabled: root.importsEnabled
        && (Config.options?.calendar?.timetable?.imports?.outlook?.enable ?? false)

    function subscriptionUrls() {
        return Array.from(Config.options?.calendar?.timetable?.subscriptions ?? []);
    }

    function effectiveSubscriptionUrls() {
        return root.importsEnabled ? root.subscriptionUrls() : [];
    }

    function normalizeUrl(value) {
        const url = String(value ?? "").trim();
        return /^https?:\/\/[^\s"\\]+$/i.test(url) ? url : "";
    }

    function addSubscription(value) {
        const url = root.normalizeUrl(value);
        if (!url) {
            root.lastError = Translation.tr("Enter a valid HTTP(S) calendar URL.");
            return false;
        }
        const current = root.subscriptionUrls();
        if (!current.includes(url))
            Config.options.calendar.timetable.subscriptions = current.concat([url]);
        root.lastError = "";
        return true;
    }

    function removeSubscription(url) {
        const value = String(url ?? "");
        Config.options.calendar.timetable.subscriptions = root.subscriptionUrls().filter(item => item !== value);
        root.lastError = "";
    }

    function requestApply() {
        if (!root.enabled)
            return;
        if (subscriptionApplyProcess.running) {
            root.applyQueued = true;
            return;
        }
        root.applying = true;
        root.lastError = "";
        subscriptionApplyProcess.replyText = "";
        subscriptionApplyProcess.stdinEnabled = true;
        subscriptionApplyProcess.running = true;
    }

    function requestPayload() {
        return {
            "vdirsyncerConfigPath": root.vdirsyncerConfigPath,
            "khalConfigPath": root.khalConfigPath,
            "statusPath": root.vdirsyncerStatusPath,
            "subscriptionRoot": root.subscriptionRoot,
            "outlookRoot": root.outlookRoot,
            "outlookEnabled": root.outlookEnabled,
            "subscriptions": root.effectiveSubscriptionUrls()
        };
    }

    function finishApply(reply) {
        root.applying = false;
        if (!reply?.ok) {
            root.lastError = String(reply?.error ?? Translation.tr("Could not configure calendar subscriptions."));
            return;
        }
        root.managedCalendars = reply.subscriptions ?? [];
        root.lastError = "";
        if (reply.syncRequired)
            root.syncSubscriptions();
        else {
            CalendarService.loadCalendarList();
            CalendarService.loadEvents();
        }
    }

    function syncSubscriptions() {
        if (subscriptionSyncProcess.running)
            return;
        root.syncInProgress = true;
        subscriptionSyncProcess.running = true;
    }

    Component.onCompleted: root.requestApply()

    Connections {
        target: Config

        function onReadyChanged() {
            if (Config.ready)
                root.requestApply();
        }
    }

    Connections {
        target: Config.options?.calendar?.timetable

        function onSubscriptionsChanged() {
            root.requestApply();
        }
    }

    Connections {
        target: Config.options?.calendar?.timetable?.imports

        function onEnableChanged() {
            root.requestApply();
        }
    }

    Connections {
        target: Config.options?.calendar?.timetable?.imports?.outlook

        function onEnableChanged() {
            root.requestApply();
        }
    }

    Process {
        id: subscriptionApplyProcess

        command: ["python3", root.helperPath]
        stdinEnabled: true
        property string replyText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify(root.requestPayload()) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: subscriptionApplyProcess.replyText = text.trim()
        }

        onExited: exitCode => {
            let reply = null;
            try {
                reply = JSON.parse(subscriptionApplyProcess.replyText);
            } catch (error) {
                reply = {
                    ok: false,
                    error: exitCode === 0
                        ? Translation.tr("Calendar subscriptions returned an unreadable response.")
                        : Translation.tr("Calendar subscriptions could not update the configuration.")
                };
            }
            root.finishApply(reply);
            if (root.applyQueued) {
                root.applyQueued = false;
                Qt.callLater(root.requestApply);
            }
        }
    }

    Process {
        id: subscriptionSyncProcess

        command: ["vdirsyncer", "sync"]
        onExited: exitCode => {
            root.syncInProgress = false;
            if (exitCode !== 0) {
                root.lastError = Translation.tr("The subscription was saved, but vdirsyncer could not synchronize it yet.");
                return;
            }
            CalendarService.loadCalendarList();
            CalendarService.loadEvents();
        }
    }
}
