pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim Holidays stand-in for standalone apps: reads the shell's cached
 * holidays.json (zero background timers).
 */
Singleton {
    id: root

    property var byDayKey: ({})
    property var _yearsLoaded: ({})

    function _rebuild(data) {
        const map = {};
        const years = {};
        if (data && typeof data === "object") {
            const entries = Array.isArray(data) ? data : Object.values(data).flat();
            for (const item of entries) {
                const key = String(item?.date ?? "").slice(0, 10);
                if (!/^\d{4}-\d{2}-\d{2}$/.test(key))
                    continue;
                years[key.slice(0, 4)] = true;
                if (!map[key])
                    map[key] = [];
                map[key].push(item);
            }
        }
        root._yearsLoaded = years;
        root.byDayKey = map;
    }

    function ensureYear(year) {
        // Cache is populated and maintained by the shell's Holidays service.
        if (!root._yearsLoaded[String(year)])
            holidaysFile.reload();
    }

    FileView {
        id: holidaysFile
        path: Directories.holidaysCachePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root._rebuild(JSON.parse(holidaysFile.text()));
            } catch (e) {
                root.byDayKey = {};
            }
        }
        onLoadFailed: root.byDayKey = {}
    }
}
