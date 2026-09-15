pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool editMode: false
    property bool textEditing: false
    signal releaseEditing()
    readonly property string revision: widgetsAdapter.data

    function _all() {
        try {
            return JSON.parse(widgetsAdapter.data) ?? ({});
        } catch (e) {
            return ({});
        }
    }
    function _save(all) {
        widgetsAdapter.data = JSON.stringify(all);
    }
    function _mutate(id, fn) {
        const all = root._all();
        for (const screen in all) {
            const arr = all[screen];
            if (!Array.isArray(arr))
                continue;
            for (let i = 0; i < arr.length; i++)
                if (arr[i].id === id) {
                    fn(arr[i]);
                    root._save(all);
                    return;
                }
        }
    }

    function widgetsFor(screen) {
        const s = root._all()[screen];
        return Array.isArray(s) ? s : [];
    }
    function get(id) {
        const all = root._all();
        for (const screen in all)
            if (Array.isArray(all[screen]))
                for (const w of all[screen])
                    if (w.id === id)
                        return w;
        return null;
    }

    readonly property var defaultSizes: ({
            "calendar": { "w": 260, "h": 280 },
            "media": { "w": 240, "h": 240 },
            "weather": { "w": 230, "h": 230 }
        })

    function add(screen, type, x, y) {
        const all = root._all();
        if (!Array.isArray(all[screen]))
            all[screen] = [];
        const id = "w" + Date.now();
        const size = root.defaultSizes[type] ?? ({ "w": 190, "h": 190 });
        all[screen].push({ "id": id, "type": type, "x": Math.round(x), "y": Math.round(y), "w": size.w, "h": size.h, "source": "" });
        root._save(all);
        return id;
    }
    function setPos(id, x, y) {
        root._mutate(id, w => {
            w.x = Math.round(x);
            w.y = Math.round(y);
        });
    }
    function setProp(id, key, val) {
        root._mutate(id, w => w[key] = val);
    }
    function remove(id) {
        const all = root._all();
        for (const screen in all) {
            if (!Array.isArray(all[screen]))
                continue;
            const before = all[screen].length;
            all[screen] = all[screen].filter(w => w.id !== id);
            if (all[screen].length !== before) {
                root._save(all);
                return;
            }
        }
    }

    FileView {
        id: widgetsView
        path: Directories.desktopWidgetsPath(Config.options.desktopFamily)
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: widgetsAdapter
            property string data: "{}"
        }
    }

    Timer {
        id: writeTimer
        interval: 120
        onTriggered: widgetsView.writeAdapter()
    }
}
