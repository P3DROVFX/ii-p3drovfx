pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The XDG default application associations owned by the desktop session.
 *
 * Hyprland's own shortcut variables are deliberately not stored here: they are commands with
 * fallbacks and belong to HyprlandBinds. These are desktop-file associations, so changing one
 * updates the application used by xdg-open, portals and other XDG-aware programs immediately.
 */
Singleton {
    id: root

    readonly property var categories: [
        {
            "id": "browser", "icon": "language", "label": Translation.tr("Web browser"),
            "description": Translation.tr("Links and web pages"),
            "mimes": ["x-scheme-handler/http", "x-scheme-handler/https"]
        },
        {
            "id": "files", "icon": "folder", "label": Translation.tr("File manager"),
            "description": Translation.tr("Folders opened by the desktop"),
            "mimes": ["inode/directory"]
        },
        {
            "id": "text", "icon": "edit_note", "label": Translation.tr("Text editor"),
            "description": Translation.tr("Plain text documents"),
            "mimes": ["text/plain"]
        },
        {
            "id": "pdf", "icon": "picture_as_pdf", "label": Translation.tr("PDF viewer"),
            "description": Translation.tr("PDF documents"),
            "mimes": ["application/pdf"]
        },
        {
            "id": "images", "icon": "image", "label": Translation.tr("Image viewer"),
            "description": Translation.tr("Photos and images"),
            "mimes": ["image/jpeg", "image/png", "image/webp"]
        },
        {
            "id": "music", "icon": "music_note", "label": Translation.tr("Music player"),
            "description": Translation.tr("Audio files"),
            "mimes": ["audio/mpeg", "audio/ogg", "audio/flac"]
        },
        {
            "id": "video", "icon": "movie", "label": Translation.tr("Video player"),
            "description": Translation.tr("Video files"),
            "mimes": ["video/mp4", "video/webm", "video/x-matroska"]
        },
        {
            "id": "mail", "icon": "mail", "label": Translation.tr("Mail client"),
            "description": Translation.tr("Email links"),
            "mimes": ["x-scheme-handler/mailto"]
        },
        {
            "id": "calendar", "icon": "calendar_month", "label": Translation.tr("Calendar"),
            "description": Translation.tr("Calendar files"),
            "mimes": ["text/calendar"]
        },
        {
            "id": "office", "icon": "description", "label": Translation.tr("Office documents"),
            "description": Translation.tr("Documents, spreadsheets and presentations"),
            "mimes": ["application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.spreadsheet", "application/vnd.oasis.opendocument.presentation"]
        }
    ]

    /// category id -> desktop file id. This is runtime state: xdg-mime, not config.json, owns it.
    property var defaults: ({})
    property bool ready: false
    property bool refreshing: false
    property bool updating: false
    property string errorMessage: ""
    property string statusMessage: ""
    /// The picker target, shared by the tab and its sub-page just like HyprlandBinds.editApp.
    property string editCategory: ""

    property string _pendingCategory: ""
    property string _pendingDesktopId: ""
    /// A read begun before a successful write must not put its stale answer back into `defaults`.
    property int _associationRevision: 0
    property bool _refreshQueued: false

    function category(id: string): var {
        return root.categories.find(entry => entry.id === id) ?? null;
    }

    function defaultId(id: string): string {
        return String(root.defaults[id] ?? "");
    }

    function desktopEntry(id: string): var {
        const desktopId = String(id ?? "");
        if (desktopId === "")
            return null;
        return DesktopEntries.byId(desktopId)
            ?? DesktopEntries.byId(desktopId.replace(/\.desktop$/, ""))
            ?? Array.from(DesktopEntries.applications.values)
                .find(entry => String(entry.id ?? "") === desktopId)
            ?? null;
    }

    function appName(id: string): string {
        const desktopId = root.defaultId(id);
        if (desktopId === "")
            return root.ready ? Translation.tr("Not set") : Translation.tr("Looking up…");
        return String(root.desktopEntry(desktopId)?.name ?? desktopId);
    }

    function appIcon(id: string): string {
        const desktopId = root.defaultId(id);
        if (desktopId === "")
            return "";
        return String(root.desktopEntry(desktopId)?.icon ?? AppSearch.guessIcon(desktopId));
    }

    function beginEdit(id: string) {
        if (root.category(id) !== null)
            root.editCategory = id;
    }

    function runQueuedRefresh() {
        if (!root._refreshQueued)
            return;
        root._refreshQueued = false;
        Qt.callLater(root.refresh);
    }

    function refresh() {
        if (refreshProc.running) {
            root._refreshQueued = true;
            return;
        }
        root._refreshQueued = false;
        root.refreshing = true;
        root.errorMessage = "";
        const command = ["bash", "-c",
            "command -v xdg-mime >/dev/null 2>&1 || exit 127; "
            + "while [ \"$#\" -ge 2 ]; do id=$1; mime=$2; shift 2; "
            + "printf '%s\\t%s\\n' \"$id\" \"$(xdg-mime query default \"$mime\" 2>/dev/null)\"; done",
            "ii-default-apps"];
        for (const entry of root.categories) {
            command.push(entry.id);
            command.push(entry.mimes[0]);
        }
        refreshProc.associationRevision = root._associationRevision;
        refreshProc.command = command;
        refreshProc.running = true;
    }

    function setDefault(categoryId: string, desktopId: string): bool {
        const entry = root.category(categoryId);
        const cleanedId = String(desktopId ?? "").trim();
        if (!entry || cleanedId === "" || root.updating)
            return false;

        root.errorMessage = "";
        root.statusMessage = "";
        root.updating = true;
        root._pendingCategory = entry.id;
        root._pendingDesktopId = cleanedId;
        setProc.command = ["bash", "-c",
            "command -v xdg-mime >/dev/null 2>&1 || exit 127; "
            + "desktop=$1; shift; for mime do xdg-mime default \"$desktop\" \"$mime\" || exit $?; done",
            "ii-set-default-app", cleanedId].concat(entry.mimes);
        setProc.running = true;
        return true;
    }

    Process {
        id: refreshProc

        property int associationRevision: 0

        stdout: StdioCollector {
            id: refreshOutput
        }

        onExited: exitCode => {
            root.refreshing = false;
            root.ready = true;
            if (exitCode !== 0) {
                root.errorMessage = exitCode === 127
                    ? Translation.tr("xdg-mime is not installed, so system defaults cannot be read.")
                    : Translation.tr("Could not read the system default applications.");
                root.runQueuedRefresh();
                return;
            }

            const next = {};
            for (const line of String(refreshOutput.text ?? "").split("\n")) {
                const divider = line.indexOf("\t");
                if (divider < 0)
                    continue;
                next[line.slice(0, divider)] = line.slice(divider + 1).trim();
            }
            // The command may have queried the old associations before a picker write completed.
            // Keep the optimistic/new value and let the queued read below confirm it instead.
            if (refreshProc.associationRevision === root._associationRevision
                    && JSON.stringify(next) !== JSON.stringify(root.defaults))
                root.defaults = next;
            root.runQueuedRefresh();
        }
    }

    Process {
        id: setProc

        onExited: exitCode => {
            const categoryId = root._pendingCategory;
            const desktopId = root._pendingDesktopId;
            root._pendingCategory = "";
            root._pendingDesktopId = "";
            root.updating = false;
            if (exitCode !== 0) {
                root.errorMessage = exitCode === 127
                    ? Translation.tr("xdg-mime is not installed, so the default could not be changed.")
                    : Translation.tr("Could not change the system default application.");
                return;
            }

            const next = Object.assign({}, root.defaults);
            next[categoryId] = desktopId;
            root.defaults = next;
            root._associationRevision += 1;
            root.statusMessage = Translation.tr("Default application updated.");
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: root.refresh()
    }
}
