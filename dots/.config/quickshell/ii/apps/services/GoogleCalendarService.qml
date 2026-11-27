pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim GoogleCalendarService stand-in for standalone apps: reads the cached
 * google_calendar_colors.json for event colors; refreshes or updates colors
 * lazily only when requested.
 */
Singleton {
    id: root

    readonly property bool colorsEnabled: Config.options?.calendar?.timetable?.googleColors?.enable ?? false
    property bool available: false
    property bool credentialsConfigured: false
    property bool authenticating: false
    property var palette: ({})
    property var eventColors: ({})
    property var colorOptions: []

    function startOAuth() {}
    function disconnect() {}

    function _applyCache(raw) {
        try {
            const parsed = JSON.parse(raw);
            root.palette = parsed?.palette ?? {};
            root.eventColors = parsed?.eventColors ?? {};
            const opts = [];
            for (const id of Object.keys(root.palette)) {
                const entry = root.palette[id];
                if (entry?.background)
                    opts.push({ id: String(id), background: String(entry.background), foreground: String(entry.foreground ?? "#ffffff") });
            }
            root.colorOptions = opts;
        } catch (e) {
            root.palette = {};
            root.eventColors = {};
            root.colorOptions = [];
        }
    }

    function knowsEvent(uid) {
        const key = String(uid ?? "").trim();
        return key.length > 0 && root.eventColors[key] !== undefined;
    }

    function colorIdForUid(uid) {
        const key = String(uid ?? "").trim();
        return key ? String(root.eventColors[key] ?? "") : "";
    }

    function colorForEvent(event) {
        if (!root.colorsEnabled || !event)
            return "";
        const uid = String(event.uid ?? "").trim();
        const cid = root.colorIdForUid(uid);
        return cid && root.palette[cid]?.background ? String(root.palette[cid].background) : "";
    }

    function refreshColors() {
        if (!root.colorsEnabled)
            return;
        colorsFile.reload();
    }

    function setEventColor(uid, colorId) {
        const key = String(uid ?? "").trim();
        if (!key)
            return;
        const next = Object.assign({}, root.eventColors);
        if (colorId)
            next[key] = String(colorId);
        else
            delete next[key];
        root.eventColors = next;
    }

    FileView {
        id: colorsFile
        path: root.colorsEnabled ? Directories.googleCalendarColorsPath : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyCache(colorsFile.text())
        onLoadFailed: {
            root.palette = {};
            root.eventColors = {};
            root.colorOptions = [];
        }
    }
}
