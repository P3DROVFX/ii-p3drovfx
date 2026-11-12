pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Launcher icons for the Android apps listed in the phone panel.
 *
 * Android has no way to hand an icon to the desktop, so a helper resolves each
 * one out of the installed APK over adb. That costs a couple of seconds per
 * app, so it never starts on its own: only an explicit app-list refresh kicks
 * off a fetch. Results are cached on disk, which makes it a one-off — every
 * later shell start, reconnect or device switch just reads the cache back.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.phone?.scrcpy?.appMode?.showAppIcons ?? true
    readonly property string deviceId: KdeConnectService.activeDeviceId || "default"

    // package name -> icon file path, "" for apps whose icon cannot be resolved
    property var icons: ({})
    property bool available: true
    property string unavailableReason: ""

    readonly property var pending: new Set()
    // Progress of the running fetch, so the panel can show something meanwhile
    property int outstanding: 0
    property int batchSize: 0
    readonly property bool fetching: root.outstanding > 0
    readonly property int fetched: root.batchSize - root.outstanding

    function iconFor(packageName: string): string {
        return root.icons[packageName] ?? "";
    }

    /**
     * Pull the icons of every listed app that has none yet. Only ever called
     * from a user-initiated refresh — nothing here reacts to the phone coming
     * back on its own.
     */
    function fetchMissing(packages: var): void {
        if (!root.enabled) return;

        const wanted = Array.from(packages ?? []).filter(name => name && !root.icons[name] && !root.pending.has(name));
        if (wanted.length === 0) return;

        // An ii tools phone draws its own icons and sends them over the link: fast,
        // the launcher's look, and no adb needed.
        if (root.viaLink) {
            if (!IiLinkService.requestLauncherIcons(wanted)) return;
            wanted.forEach(name => root.pending.add(name));
            root.batchSize += wanted.length;
            root.outstanding = root.pending.size;
            linkTimeout.restart();
            return;
        }

        if (!root.available) return;
        if (!KdeConnectService.adbReachable) return;

        wanted.forEach(name => {
            root.pending.add(name);
            root._sendToDevice({
                "cmd": "fetch",
                "package": name,
                "deviceId": root.deviceId
            });
        });
        root.batchSize += wanted.length;
        root.outstanding = root.pending.size;
    }

    function loadCached(): void {
        root._send({
            "cmd": "cached",
            "deviceId": root.deviceId
        });
    }

    /** Throw away every extracted icon, so the next refresh re-reads them all. */
    function clearCache(): void {
        root.icons = ({});
        root._resetProgress();
        root._send({
            "cmd": "clear",
            "deviceId": root.deviceId
        });
    }

    function _send(message: var): void {
        if (!iconProc.running) return;
        message.target_args = KdeConnectService.adbTargetArgs() || [];
        iconProc.write(JSON.stringify(message) + "\n");
    }

    /** Same as _send, but re-resolves the ADB target first — the phone's
     *  wireless-debugging port can change between two polls of the prober,
     *  and pulling icons against a stale one just returns nothing. Only used
     *  for commands that actually reach the device; cache reads stay sync. */
    function _sendToDevice(message: var): void {
        if (!iconProc.running) return;
        KdeConnectService.withAdbTarget(args => {
            if (!iconProc.running) return;
            message.target_args = args || [];
            iconProc.write(JSON.stringify(message) + "\n");
        });
    }

    function _resetProgress(): void {
        root.pending.clear();
        root.outstanding = 0;
        root.batchSize = 0;
    }

    function _settle(packageName: string): void {
        root.pending.delete(packageName);
        root.outstanding = root.pending.size;
        if (root.outstanding === 0) root.batchSize = 0;
    }

    function _store(packageName: string, path: string): void {
        root._settle(packageName);
        // Reassign rather than mutate so bindings on the map re-evaluate.
        const next = Object.assign({}, root.icons);
        next[packageName] = path;
        root.icons = next;
    }

    readonly property bool viaLink: KdeConnectService.activeIsIi && IiLinkService.launcherIconDev !== ""

    Connections {
        target: IiLinkService
        function onLauncherIconReady(pkg, path) {
            if (root.viaLink)
                root._store(pkg, path);
        }
    }

    // Over the link icons are cheap: the listed apps get theirs without a refresh.
    Connections {
        target: root.viaLink && root.enabled ? PhoneScrcpyService : null
        function onAppsChanged() {
            root._fetchListed();
        }
    }
    function _fetchListed(): void {
        if (root.viaLink && root.enabled)
            root.fetchMissing((PhoneScrcpyService.apps || []).map(a => a.package));
    }
    onViaLinkChanged: root._fetchListed()
    // Created only when the Android Apps page first opens, maybe with the list there.
    Component.onCompleted: Qt.callLater(root._fetchListed)

    // An app the phone cannot draw sends nothing: stop waiting for it.
    Timer {
        id: linkTimeout
        interval: 20000
        onTriggered: root._resetProgress()
    }

    onDeviceIdChanged: {
        root.icons = ({});
        root._resetProgress();
        root.loadCached();
    }

    Process {
        id: iconProc
        stdinEnabled: true
        command: ProcUtils.pdeath(["python3", Quickshell.shellPath("scripts/phone/android_icon_extractor.py")])
        running: root.enabled && (Config.options?.phone?.kdeconnectEnabled ?? true) && KdeConnectService.available

        onRunningChanged: {
            if (running) Qt.callLater(() => root.loadCached());
        }

        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data);
                    if (msg.event === "icon") {
                        // A retry means the phone went away mid-fetch, not that the app
                        // has no icon — leave it unresolved so the next refresh picks it
                        // up again instead of remembering the failure.
                        if (msg.retry) root._settle(msg.package);
                        else root._store(msg.package, msg.path || "");
                    } else if (msg.event === "cached") {
                        root.icons = Object.assign({}, root.icons, msg.icons || {});
                    } else if (msg.event === "cleared") {
                        root.icons = ({});
                    } else if (msg.event === "unavailable") {
                        root.available = false;
                        root.unavailableReason = msg.reason || "";
                        console.warn("[PhoneAppIconService] icons disabled:", root.unavailableReason);
                    }
                } catch (e) {
                    console.warn("[PhoneAppIconService] JSON error:", e, "Data:", data);
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) console.warn("[PhoneAppIconService stderr]", data);
            }
        }
    }
}
