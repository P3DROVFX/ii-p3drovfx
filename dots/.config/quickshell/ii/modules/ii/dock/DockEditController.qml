import QtQuick
import qs
import qs.services
import qs.modules.common
import "utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * Everything Edit Mode can do to what the dock carries besides apps, from the
 * dock itself: what each item is called, whether it can be resized, stacked or
 * set up, and the writes that add, remove, resize and stack it.
 *
 * Settings and the Edit Mode panel toggle the same keys as switches, which are
 * preferences. Here they are arranged ON the dock - a widget taken off with its
 * badge, put back from the (+) tile - so every write is a layout edit with ONE
 * history entry over all the keys it touched: Ctrl+Z puts a removed utility
 * back with its size and its place, not just its place.
 */
QtObject {
    id: root

    property Item dockContent: null

    readonly property bool vertical: root.dockContent?.isVertical ?? false

    // The dock's own widgets, in the order the (+) sheet offers them.
    // `options` is a Settings page drawn in the item's options card.
    readonly property var nativeWidgets: [
        { "id": "media", "key": "enableMediaWidget", "symbol": "play_circle", "title": Translation.tr("Media"), "stackable": true },
        { "id": "weather", "key": "enableWeatherWidget", "symbol": "cloud", "title": Translation.tr("Weather"), "stackable": true },
        { "id": "tasks", "key": "enableTasksWidget", "symbol": "checklist", "title": Translation.tr("Tasks"), "stackable": true },
        { "id": "sports", "key": "enableSportsWidget", "symbol": "sports_soccer", "title": Translation.tr("Sports"), "stackable": true },
        { "id": "livePreview", "key": "enableLivePreviewWidget", "symbol": "live_tv", "title": Translation.tr("Live preview"), "stackable": true,
            "options": "widgets/DockLivePreviewConfig.qml" },
        { "id": "phone", "key": "showPhoneButton", "symbol": "smartphone", "title": Translation.tr("Phone mirror"), "stackable": false }
    ]
    readonly property var buttons: [
        { "id": "overview", "key": "showOverviewButton", "symbol": "apps", "title": Translation.tr("Overview"),
            "options": "widgets/DockOverviewButtonConfig.qml" },
        { "id": "pin", "key": "showPinButton", "symbol": "keep", "title": Translation.tr("Pin") },
        { "id": "trash", "key": "showTrashButton", "symbol": "delete", "title": Translation.tr("Trash") }
    ]

    // Every key an edit from the dock may write. Snapshotted whole: a handful
    // of values, and an undo that restores exactly what was there.
    readonly property var _keys: ["order", "manualOrder", "utilityWidgets", "pinnedFiles",
        "enableMediaWidget", "enableWeatherWidget", "enableTasksWidget", "enableSportsWidget",
        "enableLivePreviewWidget", "showPhoneButton", "showOverviewButton", "showPinButton",
        "showTrashButton", "enableWidgetStack", "widgetStackItems", "livePreviewSlots"]

    function _snapshot() {
        const dock = Config.options.dock;
        const out = {};
        for (const key of root._keys) {
            const value = dock[key];
            out[key] = (value !== null && typeof value === "object") ? JSON.parse(JSON.stringify(value)) : value;
        }
        return out;
    }

    function _restore(snapshot) {
        const dock = Config.options.dock;
        for (const key of root._keys) {
            const value = snapshot[key];
            const current = (dock[key] !== null && typeof dock[key] === "object") ? JSON.stringify(dock[key]) : dock[key];
            const next = (value !== null && typeof value === "object") ? JSON.stringify(value) : value;
            if (current !== next)
                dock[key] = (value !== null && typeof value === "object") ? JSON.parse(next) : value;
        }
        TaskbarApps.syncPinnedFileOrder();
    }

    // One edit, one history entry, whatever it wrote.
    function commit(mutate) {
        const before = root._snapshot();
        mutate(Config.options.dock);
        const after = root._snapshot();
        if (JSON.stringify(before) === JSON.stringify(after))
            return;
        GlobalStates.editHistoryPush({
            "undo": () => root._restore(before),
            "redo": () => root._restore(after)
        });
    }

    // ── What an item is ─────────────────────────────────────────────────────
    function nativeInfo(id) {
        return root.nativeWidgets.find(entry => entry.id === id) ?? null;
    }
    function buttonInfo(id) {
        return root.buttons.find(entry => entry.id === id) ?? null;
    }

    // The catalogue id of a dock item: "media", "overview", "util:timer"…
    function idFor(item) {
        if (!item)
            return "";
        switch (item.type) {
        case "action":
            return String(item.actionId ?? "");
        case "utility":
            return DockUtilityCatalog.orderKey(item.kind);
        default:
            return String(item.type ?? "");
        }
    }

    // Items the dock's edit layer dresses. Apps carry their own badges, and a
    // group opens its own popup.
    function editable(item) {
        const type = item?.type ?? "";
        return type === "action" || type === "media" || type === "weather" || type === "sports"
            || type === "livePreview" || type === "tasks" || type === "phone" || type === "utility"
            || type === "widgetStack" || type === "file";
    }

    function describe(item) {
        const type = item?.type ?? "";
        if (type === "utility") {
            const info = DockUtilityCatalog.find(item.kind);
            const wideAllowed = !root.vertical;
            return {
                "title": Translation.tr(info?.title ?? item.kind),
                "symbol": info?.symbol ?? "widgets",
                "subtitle": item.wide && wideAllowed ? Translation.tr("Wide widget") : Translation.tr("Square widget"),
                "sizes": wideAllowed,
                "wide": !!item.wide,
                "options": info?.settings ? "dockUtilities/" + info.file + "Config.qml" : ""
            };
        }
        if (type === "action") {
            const info = root.buttonInfo(item.actionId);
            return {
                "title": info?.title ?? "",
                "symbol": info?.symbol ?? "radio_button_unchecked",
                "subtitle": Translation.tr("Button"),
                "options": info?.options ?? ""
            };
        }
        if (type === "widgetStack") {
            return {
                "title": Translation.tr("Widget stack"),
                "symbol": "stacks",
                "subtitle": Translation.tr("%1 widgets, turned with the wheel").arg(root.dockContent?.widgetStackMembers?.length ?? 0)
            };
        }
        if (type === "file") {
            const path = String(item.path ?? "");
            return {
                "title": path.split("/").filter(part => part.length > 0).pop() ?? path,
                "symbol": "folder",
                "subtitle": path
            };
        }
        const info = root.nativeInfo(type);
        const slots = Math.max(2, Math.min(6, Config.options.dock.livePreviewSlots ?? 2));
        return {
            "title": info?.title ?? type,
            "symbol": info?.symbol ?? "widgets",
            "subtitle": type === "livePreview" ? Translation.tr("%1 slots wide").arg(slots) : Translation.tr("Widget"),
            "stackable": info?.stackable === true,
            "slots": type === "livePreview" && !root.vertical ? slots : 0,
            "options": info?.options ?? ""
        };
    }

    // ── Writes ──────────────────────────────────────────────────────────────
    function _dropOrderKey(dock, key) {
        const order = Array.from(dock.order ?? []);
        if (order.indexOf(key) >= 0)
            dock.order = order.filter(entry => entry !== key);
    }

    function remove(item) {
        const type = item?.type ?? "";
        root.commit(dock => {
            if (type === "utility") {
                dock.utilityWidgets = DockUtilityCatalog.withoutKind(dock.utilityWidgets ?? [], item.kind);
                root._dropOrderKey(dock, DockUtilityCatalog.orderKey(item.kind));
            } else if (type === "action") {
                const info = root.buttonInfo(item.actionId);
                if (info)
                    dock[info.key] = false;
            } else if (type === "widgetStack") {
                // The stack goes; its members go back to their own places
                // (the ones that are on).
                dock.enableWidgetStack = false;
            } else if (type === "file") {
                TaskbarApps.removePinnedFile(item.path);
            } else {
                const info = root.nativeInfo(type);
                if (info)
                    dock[info.key] = false;
            }
        });
    }

    function setWide(item, wide) {
        if (item?.type !== "utility" || !!item.wide === !!wide)
            return;
        root.commit(dock => dock.utilityWidgets = DockUtilityCatalog.withKind(dock.utilityWidgets ?? [], item.kind, wide));
    }

    function stepLivePreviewSlots(delta) {
        const current = Math.max(2, Math.min(6, Config.options.dock.livePreviewSlots ?? 2));
        const next = Math.max(2, Math.min(6, current + delta));
        if (next !== current)
            root.commit(dock => dock.livePreviewSlots = next);
    }

    function inStack(member) {
        return (Config.options.dock.enableWidgetStack ?? false)
            && (Config.options.dock.widgetStackItems ?? []).indexOf(member) >= 0;
    }

    // Into the stack (turning the stack on) or back out to the dock. A widget
    // taken out of the stack keeps showing on its own.
    function setStacked(member, stacked) {
        root.commit(dock => {
            const items = Array.from(dock.widgetStackItems ?? []).filter(entry => entry !== member);
            if (stacked) {
                items.push(member);
                dock.enableWidgetStack = true;
            } else {
                const info = root.nativeInfo(member);
                if (info)
                    dock[info.key] = true;
            }
            dock.widgetStackItems = items;
        });
    }

    // ── The (+) sheet ───────────────────────────────────────────────────────
    // Whether the catalogue entry `id` is on the dock (or in its stack).
    function isAdded(id) {
        const dock = Config.options.dock;
        if (DockUtilityCatalog.isOrderKey(id))
            return DockUtilityCatalog.entryFor(dock.utilityWidgets ?? [], DockUtilityCatalog.kindFromOrderKey(id)) !== null;
        if (id === "widgetStack")
            return dock.enableWidgetStack ?? false;
        const info = root.nativeInfo(id) ?? root.buttonInfo(id);
        return info ? (dock[info.key] ?? false) || (root.nativeInfo(id) !== null && root.inStack(id)) : false;
    }

    // Why an added entry is not drawn right now, or "".
    function waitingReason(id) {
        const content = root.dockContent;
        if (!content || !root.isAdded(id))
            return "";
        switch (id) {
        case "media":
            return content.showMusicPlayer ? "" : Translation.tr("Shows while something plays");
        case "sports":
            if (root.vertical)
                return Translation.tr("Horizontal docks only");
            return SportsService.allGames.length > 0 ? "" : Translation.tr("Shows while there are games");
        case "phone":
            return content.showPhone ? "" : Translation.tr("Shows while your phone is reachable");
        case "widgetStack":
            return (content.widgetStackMembers?.length ?? 0) > 0 ? "" : Translation.tr("Add widgets to it");
        default:
            return "";
        }
    }

    function toggle(id) {
        const added = root.isAdded(id);
        root.commit(dock => {
            if (DockUtilityCatalog.isOrderKey(id)) {
                const kind = DockUtilityCatalog.kindFromOrderKey(id);
                if (added) {
                    dock.utilityWidgets = DockUtilityCatalog.withoutKind(dock.utilityWidgets ?? [], kind);
                    root._dropOrderKey(dock, id);
                } else {
                    dock.utilityWidgets = DockUtilityCatalog.withKind(dock.utilityWidgets ?? [], kind, false);
                }
                return;
            }
            if (id === "widgetStack") {
                dock.enableWidgetStack = !added;
                return;
            }
            const info = root.nativeInfo(id) ?? root.buttonInfo(id);
            if (!info)
                return;
            dock[info.key] = !added;
            // Taking a stacked widget off takes it out of the stack too, or
            // the stack would keep drawing what was just removed.
            if (added && root.nativeInfo(id) !== null)
                dock.widgetStackItems = Array.from(dock.widgetStackItems ?? []).filter(entry => entry !== id);
        });
    }
}
