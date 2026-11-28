pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

/**
 * Slim IPC bridge to the shell's PhoneGalleryService (`qs -c ii ipc call phoneGallery ...`).
 * Keeps zero IiLink / KdeConnect / Notification singletons inside the standalone Gallery process.
 * Polls only while the Phone tab is open or a download/mount is active.
 */
QtObject {
    id: bridge

    property bool active: false
    property bool connected: false
    property bool available: false
    property bool hasGalleryCap: false
    property bool hasFilesCap: false
    property string setupState: "offline"   // "offline" | "setup" | "ready"
    property string deviceName: ""
    property string activeDev: ""
    property string album: ""
    property var albums: []
    property var items: []
    property int totalCount: 0
    property bool more: false
    property bool loading: false
    property bool loadedOnce: false
    property string error: ""
    property string thumbDir: ""
    property int thumbRevision: 0
    property var _thumbsOnDisk: ({})
    property var fullPaths: ({})
    property var fullProgress: ({})
    property var fullErrors: ({})
    property var savedPaths: ({})
    property bool videoMounting: false
    property string mountDir: ""

    signal sendToPhoneFinished(bool ok, string message)
    signal saveToPcFinished(bool ok, string message)

    readonly property bool _hasActiveTransfer: Object.keys(bridge.fullProgress ?? {}).length > 0 || bridge.videoMounting

    onActiveChanged: {
        if (bridge.active) {
            bridge.openSession();
        } else {
            pollTimer.stop();
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "close"]);
        }
    }

    function checkStatusOnce(): void {
        if (statusProc.running)
            return;
        statusProc.running = true;
    }

    function openSession(): void {
        bridge.loading = true;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "open"]);
        bridge.checkStatusOnce();
        pollTimer.restart();
    }

    function refresh(): void {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "refresh"]);
        bridge.checkStatusOnce();
    }

    function setAlbum(bucketId): void {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "setAlbum", String(bucketId ?? "")]);
        bridge.album = String(bucketId ?? "");
        bridge.loading = true;
        Qt.callLater(bridge.checkStatusOnce);
    }

    function loadMore(): void {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "loadMore"]);
        bridge.loading = true;
        Qt.callLater(bridge.checkStatusOnce);
    }

    function wantThumbs(ids): void {
        if (!Array.isArray(ids) || ids.length === 0)
            return;
        const missing = [];
        for (const id of ids) {
            const sid = String(id);
            if (!bridge._thumbsOnDisk[sid])
                missing.push(sid);
        }
        if (missing.length === 0)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "wantThumbs", JSON.stringify(missing)]);
    }

    function hasThumb(id): bool {
        return !!bridge._thumbsOnDisk[String(id ?? "")];
    }

    function thumbPath(id): string {
        const sid = String(id ?? "");
        if (!bridge.thumbDir || !sid || !bridge._thumbsOnDisk[sid])
            return "";
        return `file://${bridge.thumbDir}/${sid}.jpg`;
    }

    function requestFull(id): void {
        const sid = String(id ?? "");
        if (!sid)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "get", sid]);
        if (!pollTimer.running)
            pollTimer.restart();
    }

    function prepareItem(id): void {
        const sid = String(id ?? "");
        if (!sid)
            return;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "prepare", sid]);
        if (!pollTimer.running)
            pollTimer.restart();
    }

    function localPathFor(item): string {
        if (!item)
            return "";
        const sid = String(item.id ?? "");
        if (item.kind === "video") {
            const rel = String(item.path ?? "");
            if (bridge.mountDir && rel)
                return `${bridge.mountDir}${rel.startsWith("/") ? "" : "/"}${rel}`;
            return "";
        }
        return String(bridge.fullPaths[sid] ?? "");
    }

    function saveItemToPc(id): void {
        const sid = String(id ?? "");
        if (!sid || saveProc.running)
            return;
        saveProc.command = ["qs", "-c", "ii", "ipc", "call", "phoneGallery", "save", sid];
        saveProc.running = true;
    }

    function sendFileToPhone(path): void {
        const p = String(path ?? "").trim();
        if (!p || sendProc.running)
            return;
        sendProc.command = ["qs", "-c", "ii", "ipc", "call", "phoneGallery", "sendToPhone", p];
        sendProc.running = true;
    }

    function sendFilesToPhone(paths): void {
        const list = Array.isArray(paths) ? paths.map(p => String(p ?? "").trim()).filter(Boolean) : [];
        if (list.length === 0)
            return;
        if (!bridge.connected) {
            bridge.sendToPhoneFinished(false, Translation.tr("No phone connected via ii tools"));
            return;
        }
        for (const p of list) {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "phoneGallery", "sendToPhone", p]);
        }
        bridge.sendToPhoneFinished(
            true,
            list.length === 1
                ? Translation.tr("Sent 1 item to phone")
                : Translation.tr("Sending %1 items to phone").arg(list.length)
        );
    }

    function _applySnapshot(raw): void {
        try {
            const d = JSON.parse(raw || "{}");
            bridge.connected = d.connected === true;
            bridge.available = d.available === true;
            bridge.hasGalleryCap = d.hasGalleryCap === true;
            bridge.hasFilesCap = d.hasFilesCap === true;
            bridge.setupState = String(d.setupState ?? "offline");
            bridge.deviceName = String(d.deviceName ?? "");
            bridge.activeDev = String(d.activeDev ?? "");
            bridge.album = String(d.album ?? "");
            bridge.albums = Array.isArray(d.albums) ? d.albums : [];
            bridge.items = Array.isArray(d.items) ? d.items : [];
            bridge.totalCount = Number(d.totalCount ?? 0);
            bridge.more = d.more === true;
            bridge.loading = d.loading === true;
            bridge.loadedOnce = d.loadedOnce === true;
            bridge.error = String(d.error ?? "");
            bridge.thumbDir = String(d.thumbDir ?? "");
            bridge.fullPaths = d.fullPaths ?? ({});
            bridge.fullProgress = d.fullProgress ?? ({});
            bridge.fullErrors = d.fullErrors ?? ({});
            bridge.savedPaths = d.savedPaths ?? ({});
            bridge.videoMounting = d.videoMounting === true;
            bridge.mountDir = String(d.mountDir ?? "");

            const map = {};
            if (Array.isArray(d.thumbsOnDisk)) {
                for (const sid of d.thumbsOnDisk)
                    map[String(sid)] = true;
            }
            bridge._thumbsOnDisk = map;
            bridge.thumbRevision = Number(d.thumbRevision ?? 0);
        } catch (e) {
            bridge.connected = false;
            bridge.setupState = "offline";
        }
    }

    property Timer _pollTimer: Timer {
        id: pollTimer
        interval: bridge._hasActiveTransfer || bridge.loading ? 450 : 1800
        repeat: true
        running: false
        onTriggered: {
            if (!bridge.active && !bridge._hasActiveTransfer) {
                pollTimer.stop();
                return;
            }
            bridge.checkStatusOnce();
        }
    }

    property Process _statusProc: Process {
        id: statusProc
        command: ["qs", "-c", "ii", "ipc", "call", "phoneGallery", "status"]
        stdout: StdioCollector {
            onStreamFinished: bridge._applySnapshot(this.text.trim())
        }
        onExited: code => {
            if (code !== 0) {
                bridge.connected = false;
                bridge.setupState = "offline";
            }
        }
    }

    property Process _sendProc: Process {
        id: sendProc
        stdout: StdioCollector {
            onStreamFinished: {
                const res = String(this.text ?? "").trim().replace(/^"|"$/g, "");
                if (res === "ok") {
                    bridge.sendToPhoneFinished(true, Translation.tr("Sent to phone"));
                } else if (res === "no_phone") {
                    bridge.sendToPhoneFinished(false, Translation.tr("No phone connected via ii tools"));
                } else {
                    bridge.sendToPhoneFinished(false, Translation.tr("Could not send file to phone"));
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                bridge.sendToPhoneFinished(false, Translation.tr("Shell ii link unavailable"));
        }
    }

    property Process _saveProc: Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                const res = String(this.text ?? "").trim().replace(/^"|"$/g, "");
                if (res === "ok") {
                    bridge.saveToPcFinished(true, Translation.tr("Saved to ~/Pictures/Phone"));
                    bridge.checkStatusOnce();
                } else {
                    bridge.saveToPcFinished(false, Translation.tr("Could not save item from phone"));
                }
            }
        }
    }

    Component.onCompleted: {
        // Single lightweight check on startup so the navbar/appbar knows if a phone is connected.
        bridge.checkStatusOnce();
    }
}
