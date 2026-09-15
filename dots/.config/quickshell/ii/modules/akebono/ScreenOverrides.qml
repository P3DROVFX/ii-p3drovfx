pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string revision: overridesAdapter.data

    function _all() {
        try {
            return JSON.parse(overridesAdapter.data) ?? ({});
        } catch (e) {
            return ({});
        }
    }

    function has(screenName, key) {
        const s = root._all()[screenName];
        return !!s && (key in s);
    }

    function resolve(screenName, key, inherited) {
        const s = root._all()[screenName];
        return (s && (key in s)) ? s[key] : inherited;
    }

    function setEffective(screenName, key, value, inherited) {
        if (value === inherited)
            root.clear(screenName, key);
        else
            root.set(screenName, key, value);
    }

    function set(screenName, key, value) {
        const all = root._all();
        if (!all[screenName])
            all[screenName] = ({});
        all[screenName][key] = value;
        overridesAdapter.data = JSON.stringify(all);
    }

    function clear(screenName, key) {
        const all = root._all();
        if (all[screenName] && (key in all[screenName])) {
            delete all[screenName][key];
            if (Object.keys(all[screenName]).length === 0)
                delete all[screenName];
            overridesAdapter.data = JSON.stringify(all);
        }
    }

    function clearScreen(screenName) {
        const all = root._all();
        if (screenName in all) {
            delete all[screenName];
            overridesAdapter.data = JSON.stringify(all);
        }
    }

    FileView {
        id: overridesView
        path: Directories.screenOverridesPath(Config.options.panelFamily)
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: overridesAdapter
            property string data: "{}"
        }
    }

    Timer {
        id: writeTimer
        interval: 120
        onTriggered: overridesView.writeAdapter()
    }
}
