pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common.functions
import qs.modules.common

Singleton {
    id: root
    property var items: []
    property int maxItems: 30
    // Shelf contents persist until reboot, following the same boot id policy
    // as the network usage totals.
    property string _bootId: ""
    property bool _restored: false

    Component.onCompleted: restoreFromDisk()

    FileView {
        id: bootIdFile
        path: "/proc/sys/kernel/random/boot_id"
        printErrors: false
        onLoaded: {
            root._bootId = text().trim()
            root.restoreFromDisk()
        }
    }

    function restoreFromDisk() {
        if (_restored || !Persistent.ready || _bootId === "")
            return;
        _restored = true;
        const stored = Persistent.states.dropShelf;
        if (stored.bootId === _bootId && stored.items && stored.items.length > 0) {
            root.items = Array.from(stored.items);
        } else {
            stored.items = [];
            stored.bootId = _bootId;
        }
    }

    function saveToDisk() {
        if (!_restored)
            return;
        const stored = Persistent.states.dropShelf;
        stored.bootId = _bootId;
        stored.items = Array.from(items);
    }

    function addItems(urls) {
        let arr = [...items]
        for (const url of urls) {
            const path = FileUtils.trimFileProtocol(decodeURIComponent(url.toString()))
            if (!arr.includes(path) && arr.length < root.maxItems) {
                arr.push(path)
            }
        }
        root.items = arr
        saveToDisk()
    }

    function show(urls, x, y) {
        root.addItems(urls)
        GlobalStates.dropShelfX = x
        GlobalStates.dropShelfY = y
        GlobalStates.dropShelfOpen = true
    }

    function copyAll() {
        const uriList = root.items.map(p => "file://" + p).join("\n")
        copyProc.payload = uriList
        copyProc.running = true
    }

    function clear() {
        root.items = []
        GlobalStates.dropShelfOpen = false
        saveToDisk()
    }

    function hide() {
        GlobalStates.dropShelfOpen = false
    }

    Process {
        id: copyProc
        property string payload: ""
        command: ["sh", "-c", `printf '%s\\n' "$QS_PAYLOAD" | wl-copy`, "sh"]
        environment: ({ QS_PAYLOAD: payload })
    }
}
