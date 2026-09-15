pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Who is using the camera, the microphone, the screen or the location right now.
 *
 * `scripts/privacy_probe.py` runs as a bridge and writes one JSON line
 * whenever the picture changes, so this service is event-driven from QML's
 * side even though the probe itself polls. Which kinds are watched at all is
 * a setting, and changing it restarts the probe with a narrower job rather
 * than filtering afterwards — an unwatched kind should cost nothing.
 */
Singleton {
    id: root

    property var items: []
    property bool available: true
    property string errorMessage: ""

    property string _lastSerialized: ""
    property int _restartAttempts: 0
    readonly property int _maxRestartAttempts: 5

    readonly property var _cfg: Config.options?.bar?.privacyPill ?? null

    readonly property bool enabled: root._cfg?.enabled ?? true
    readonly property real pollInterval: Math.max(0.4, (root._cfg?.pollInterval ?? 1200) / 1000)

    readonly property var watchedKinds: {
        const cfg = root._cfg;
        const kinds = [];
        if (cfg?.watchCamera ?? true)
            kinds.push("camera");
        if (cfg?.watchMicrophone ?? true)
            kinds.push("microphone");
        if (cfg?.watchScreen ?? true)
            kinds.push("screen");
        if (cfg?.watchLocation ?? false)
            kinds.push("location");
        return kinds;
    }

    // Kinds in a fixed order, so the pill never reshuffles its icons just
    // because the probe happened to list a stream first this time.
    readonly property var kindOrder: ["camera", "microphone", "screen", "location"]

    readonly property var activeItems: {
        const ignored = String(root._cfg?.ignoreApps ?? "")
            .split(",")
            .map(part => part.trim().toLowerCase())
            .filter(part => part.length > 0);
        return root.items.filter(item => {
            if (root.watchedKinds.indexOf(String(item.kind)) < 0)
                return false;
            const app = String(item.app ?? "").toLowerCase();
            return app.length === 0 || ignored.indexOf(app) < 0;
        });
    }

    readonly property var activeKinds: {
        const seen = {};
        for (const item of root.activeItems)
            seen[String(item.kind)] = true;
        return root.kindOrder.filter(kind => seen[kind] === true);
    }

    readonly property bool active: root.enabled && root.activeKinds.length > 0

    function iconFor(kind: string): string {
        switch (kind) {
        case "camera":
            return "photo_camera";
        case "microphone":
            return "mic";
        case "screen":
            return "screen_share";
        case "location":
            return "location_on";
        default:
            return "shield";
        }
    }

    function labelFor(kind: string): string {
        switch (kind) {
        case "camera":
            return Translation.tr("Camera");
        case "microphone":
            return Translation.tr("Microphone");
        case "screen":
            return Translation.tr("Screen");
        case "location":
            return Translation.tr("Location");
        default:
            return Translation.tr("Sensor");
        }
    }

    // "Microphone & Camera", the way Android titles the sheet.
    function summaryTitle(): string {
        const labels = root.activeKinds.map(kind => root.labelFor(kind));
        if (labels.length === 0)
            return Translation.tr("No sensor in use");
        if (labels.length === 1)
            return labels[0];
        return labels.slice(0, -1).join(", ") + Translation.tr(" & ") + labels[labels.length - 1];
    }

    function _handleLine(line): void {
        const text = String(line ?? "").trim();
        if (text.length === 0)
            return;
        try {
            const payload = JSON.parse(text);
            root.available = payload.ok ?? false;
            root.errorMessage = String(payload.error ?? "");
            const next = payload.items ?? [];
            const serialized = JSON.stringify(next);
            if (serialized !== root._lastSerialized) {
                root._lastSerialized = serialized;
                root.items = next;
            }
        } catch (error) {
            console.error("[Privacy] Invalid probe payload:", error);
        }
    }

    function _reset(): void {
        root._lastSerialized = "";
        root.items = [];
    }

    onEnabledChanged: root._restart()
    onWatchedKindsChanged: root._restart()
    onPollIntervalChanged: root._restart()

    function _restart(): void {
        probe.running = false;
        root._reset();
        root._restartAttempts = 0;
        // A deliberate restart must not inherit the backoff a crash left behind.
        restartTimer.interval = 200;
        if (root.enabled && root.watchedKinds.length > 0)
            restartTimer.restart();
    }

    Component.onCompleted: {
        if (root.enabled && root.watchedKinds.length > 0)
            probe.running = true;
    }

    Timer {
        id: restartTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.enabled && root.watchedKinds.length > 0)
                probe.running = true;
        }
    }

    Process {
        id: probe

        command: [
            "python3",
            Directories.scriptPath + "/privacy_probe.py",
            "--interval",
            String(root.pollInterval),
            "--kinds",
            root.watchedKinds.join(",")
        ]

        // process-lifecycle: restart-safe -- capped backoff; no running binding,
        // so a settings change restarts it deliberately instead of thrashing.
        stdout: SplitParser {
            onRead: data => root._handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[Privacy]", data)
        }

        onExited: (code, status) => {
            root._reset();
            if (!root.enabled || root.watchedKinds.length === 0)
                return;
            if (root._restartAttempts >= root._maxRestartAttempts) {
                root.available = false;
                root.errorMessage = Translation.tr("The privacy probe stopped responding.");
                return;
            }
            root._restartAttempts += 1;
            restartTimer.interval = 400 * root._restartAttempts;
            restartTimer.restart();
        }
    }
}
