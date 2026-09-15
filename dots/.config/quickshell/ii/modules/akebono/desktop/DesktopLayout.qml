pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string revision: layoutAdapter.data

    function _all() {
        try {
            return JSON.parse(layoutAdapter.data) ?? ({});
        } catch (e) {
            return ({});
        }
    }

    function cellOf(screenName, fileName) {
        const s = root._all()[screenName];
        return (s && s[fileName]) ? s[fileName] : null;
    }

    function setCell(screenName, fileName, col, row) {
        const all = root._all();
        if (!all[screenName])
            all[screenName] = ({});
        all[screenName][fileName] = { "col": col, "row": row };
        layoutAdapter.data = JSON.stringify(all);
    }

    function setCells(screenName, assignments) {
        const all = root._all();
        if (!all[screenName])
            all[screenName] = ({});
        for (const k in assignments)
            all[screenName][k] = assignments[k];
        layoutAdapter.data = JSON.stringify(all);
    }

    function forget(screenName, fileName) {
        const all = root._all();
        if (all[screenName] && (fileName in all[screenName])) {
            delete all[screenName][fileName];
            layoutAdapter.data = JSON.stringify(all);
        }
    }

    function prune(screenName, names) {
        if (names.length === 0)
            return;
        const all = root._all();
        const s = all[screenName];
        if (!s)
            return;
        const live = new Set(names);
        let changed = false;
        for (const k of Object.keys(s)) {
            if (live.has(k))
                continue;
            delete s[k];
            changed = true;
        }
        if (changed)
            layoutAdapter.data = JSON.stringify(all);
    }

    function clearScreen(screenName) {
        const all = root._all();
        all[screenName] = ({});
        layoutAdapter.data = JSON.stringify(all);
    }

    FileView {
        id: layoutView
        path: Directories.desktopLayoutPath(Config.options.desktopFamily)
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: layoutAdapter
            property string data: "{}"
        }
    }

    Timer {
        id: writeTimer
        interval: 120
        onTriggered: layoutView.writeAdapter()
    }
}
