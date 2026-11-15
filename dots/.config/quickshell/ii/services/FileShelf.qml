pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "../modules/ii/dock/utilities/UtilityFiles.js" as UtilityFiles

/**
 * The drop shelf: files left halfway through a drag, to be picked up later.
 *
 * One store for every surface that shows it - the dock's Shelf tile, the
 * desktop Drop Shelf widgets, the island's shelf activity - so a file dropped
 * on one is waiting on all of them. Kept in Persistent (paths only, newest
 * last), so the shelf survives a restart.
 */
Singleton {
    id: root

    readonly property var items: Persistent.ready ? Array.from(Persistent.states.dockUtilities.shelf ?? []) : []
    readonly property int count: root.items.length
    readonly property string newest: root.count > 0 ? root.items[root.count - 1] : ""
    // Whether a file dragged off the shelf leaves it (Settings → Dock → Shelf).
    readonly property bool removeAfterDrag: Config.options?.dock?.utilities?.shelf?.removeAfterDrag ?? false

    // Urls or paths, as a drop hands them over; already-shelved ones move to the top.
    function add(urls) {
        if (!Persistent.ready)
            return;
        const incoming = UtilityFiles.dedupe(Array.from(urls ?? []).map(url => String(url)));
        if (incoming.length === 0)
            return;
        Persistent.states.dockUtilities.shelf = UtilityFiles.dedupe(root.items.filter(path => incoming.indexOf(path) < 0).concat(incoming));
    }

    // ── The phone's recents ──────────────────────────────────────────────
    // The newest things on the phone sit on the shelf as `phone:<id>` entries, ahead of the
    // files left here. Only their thumbnail is on this PC: the original is fetched when the
    // pointer lingers on it or it is dragged, a video is read through the phone's mounted
    // folder. Surfaces that show them call watchPhone(true) while they are on screen.
    readonly property bool phoneEnabled: Config.options?.dock?.utilities?.shelf?.phoneRecents ?? true
    readonly property int phoneLimit: 6
    property var _hiddenPhone: ({})
    property int _watching: 0
    property bool _watchApplied: false
    readonly property bool _wantPhone: root.phoneEnabled && root._watching > 0
    on_WantPhoneChanged: {
        if (root._wantPhone === root._watchApplied)
            return;
        root._watchApplied = root._wantPhone;
        PhoneGalleryService.watchRecents(root._wantPhone);
    }

    function watchPhone(on) {
        root._watching = Math.max(0, root._watching + (on ? 1 : -1));
    }

    readonly property var phoneEntries: !root._wantPhone ? [] : PhoneGalleryService.recents
        .filter(it => !root._hiddenPhone[String(it.id)])
        .slice(0, root.phoneLimit)
        .map(it => "phone:" + it.id)
    // What a per-file view lists: the phone's recents, then the shelf's files, newest first.
    readonly property var entries: root.phoneEntries.concat(root.items.slice().reverse())
    readonly property int entryCount: root.entries.length
    // Bumps when a thumbnail or an original lands, for bindings on thumbUrl() and ready().
    readonly property int phoneRevision: PhoneGalleryService.thumbRevision + Object.keys(PhoneGalleryService.fullPaths).length

    function isPhone(path) {
        return String(path).startsWith("phone:");
    }

    function phoneItem(path) {
        return root.isPhone(path) ? PhoneGalleryService.recentById(String(path).slice(6)) : null;
    }

    function name(path) {
        const item = root.phoneItem(path);
        return item ? String(item.name ?? "") : UtilityFiles.baseName(String(path));
    }

    function isImage(path) {
        return root.isPhone(path) ? root.phoneItem(path) !== null : UtilityFiles.isImage(String(path));
    }

    function thumbUrl(path) {
        void root.phoneRevision;
        const item = root.phoneItem(path);
        return item ? PhoneGalleryService.thumbPath(item.id) : "";
    }

    /** The paths as files on this PC, or null while a phone one is not here yet (and it is on its way). */
    function resolve(paths) {
        const out = [];
        let waiting = false;
        for (const path of Array.from(paths ?? [])) {
            if (!root.isPhone(path)) {
                out.push(String(path));
                continue;
            }
            const item = root.phoneItem(path);
            const local = item ? PhoneGalleryService.localPath(item) : "";
            if (local === "") {
                waiting = true;
                if (item)
                    PhoneGalleryService.prepare(item);
            } else {
                out.push(local);
            }
        }
        return waiting ? null : out;
    }

    function prepare(path) {
        const item = root.phoneItem(path);
        if (item)
            PhoneGalleryService.prepare(item);
    }

    /** 0..1 while a phone entry is being brought over, -1 otherwise. */
    function progress(path) {
        void root.phoneRevision;
        const item = root.phoneItem(path);
        return item ? PhoneGalleryService.prepareProgress(item) : -1;
    }

    // Opened as soon as it arrives, when the click came before the file did.
    property var _openWhenReady: ({})

    function open(path) {
        const local = root.resolve([path]);
        if (local && local.length > 0) {
            Quickshell.execDetached(["xdg-open", local[0]]);
            return;
        }
        const next = Object.assign({}, root._openWhenReady);
        next[path] = true;
        root._openWhenReady = next;
    }

    function _openArrived() {
        for (const path of Object.keys(root._openWhenReady)) {
            const local = root.resolve([path]);
            if (!local)
                continue;
            const next = Object.assign({}, root._openWhenReady);
            delete next[path];
            root._openWhenReady = next;
            Quickshell.execDetached(["xdg-open", local[0]]);
        }
    }

    Connections {
        target: IiLinkService
        function onFilesMountsChanged() {
            root._openArrived();
        }
    }

    Connections {
        target: PhoneGalleryService
        function onFullPathsChanged() {
            root._openArrived();
        }
    }

    function remove(path) {
        if (root.isPhone(path)) {
            const next = Object.assign({}, root._hiddenPhone);
            next[String(path).slice(6)] = true;
            root._hiddenPhone = next;
            return;
        }
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = root.items.filter(item => item !== path);
    }

    function clear() {
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = [];
    }

    // After a drag out: honours removeAfterDrag for the paths that left.
    function dragged(paths) {
        if (!root.removeAfterDrag)
            return;
        const gone = Array.from(paths ?? []);
        if (Persistent.ready)
            Persistent.states.dockUtilities.shelf = root.items.filter(item => gone.indexOf(item) < 0);
    }
}
