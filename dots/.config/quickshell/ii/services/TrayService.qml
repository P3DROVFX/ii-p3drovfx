pragma Singleton

import qs.modules.common
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive

    // SystemTray.items is populated asynchronously. Copy its values whenever the
    // ObjectModel changes, so the filtered properties receive a new JS array and
    // cannot remain bound to a stale in-place list.
    property var allItems: []

    function refreshItems() {
        const values = SystemTray.items.values;
        root.allItems = values ? values.slice() : [];
    }

    Connections {
        target: SystemTray.items
        function onValuesChanged() {
            root.refreshItems();
        }
    }

    Component.onCompleted: root.refreshItems()

    // Quickshell unloads a dbusmenu once no QsMenuOpener references it, so a menu
    // window opened fresh on every right-click had to refetch the layout over DBus
    // each time. Hold one opener per item for its lifetime: the layout stays loaded
    // (and follows LayoutUpdated), and SysTrayMenu opens with its entries in place.
    Instantiator {
        model: SystemTray.items
        delegate: QsMenuOpener {
            required property SystemTrayItem modelData
            menu: modelData.hasMenu ? modelData.menu : null
        }
    }

    function getItemKey(item) {
        if (!item) return "";
        var baseId = item.id || "";
        if (baseId.indexOf("chrome_status_icon") !== -1 || baseId === "electron" || baseId === "") {
            var extra = (item.tooltipTitle || item.title || item.icon || "").toLowerCase();
            if (extra.length > 0) return baseId + "_" + extra;
        }
        return baseId;
    }

    property var itemsInUserList: root.allItems.filter(i => {
        if (!i) return false;
        var key = root.getItemKey(i);
        var pins = Config.options.tray.pinnedItems || [];
        var isPinned = pins.includes(key) || pins.includes(i.id);
        return isPinned && (!smartTray || i.status !== Status.Passive);
    })

    property var itemsNotInUserList: root.allItems.filter(i => {
        if (!i) return false;
        var key = root.getItemKey(i);
        var pins = Config.options.tray.pinnedItems || [];
        var isPinned = pins.includes(key) || pins.includes(i.id);
        return !isPinned && (!smartTray || i.status !== Status.Passive);
    })

    property bool invertPins: Config.options.tray.invertPinnedItems
    property var pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property var unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        if (!item) return "";
        var result = item.tooltipTitle && item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title && item.title.length > 0 ? item.title : (item.id || ""));
        if (item.tooltipDescription && item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId && item.id) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    // Callers may pass either a live item or a bare id. A bare id is ambiguous for
    // Electron/Chrome items, whose stored key is "<id>_<title>", so look the live item
    // up and derive the real key from it instead of trusting the id.
    function resolveKey(itemOrId) {
        if (!itemOrId) return "";
        if (typeof itemOrId === "object") return getItemKey(itemOrId);
        var match = SystemTray.items.values.find(i => i && i.id === itemOrId);
        return match ? getItemKey(match) : itemOrId;
    }

    function isListed(itemOrId) {
        var key = root.resolveKey(itemOrId);
        if (!key) return false;
        var rawId = typeof itemOrId === "object" ? (itemOrId.id || "") : itemOrId;
        var pins = Config.options.tray.pinnedItems || [];
        return pins.includes(key) || (rawId.length > 0 && pins.includes(rawId));
    }

    function addToList(itemOrId) {
        var key = root.resolveKey(itemOrId);
        if (!key) return;
        var pins = (Config.options.tray.pinnedItems || []).slice();
        if (pins.includes(key)) return;
        pins.push(key);
        Config.options.tray.pinnedItems = pins;
    }

    function removeFromList(itemOrId) {
        var key = root.resolveKey(itemOrId);
        if (!key) return;
        var rawId = typeof itemOrId === "object" ? (itemOrId.id || "") : itemOrId;
        Config.options.tray.pinnedItems = (Config.options.tray.pinnedItems || []).filter(id => id !== key && id !== rawId);
    }

    // With invertPins the config list is a blacklist for the pinned area, so being listed
    // and being pinned are opposites. Everything below goes through here to keep the two
    // modes from cancelling each other out.
    function setPinned(itemOrId, pinned) {
        if (invertPins ? !pinned : pinned)
            root.addToList(itemOrId);
        else
            root.removeFromList(itemOrId);
    }

    function pin(itemOrId) {
        root.setPinned(itemOrId, true);
    }

    function unpin(itemOrId) {
        root.setPinned(itemOrId, false);
    }

    function isPinned(itemOrId) {
        if (!itemOrId) return false;
        return invertPins ? !root.isListed(itemOrId) : root.isListed(itemOrId);
    }

    function togglePin(itemOrId) {
        root.setPinned(itemOrId, !root.isPinned(itemOrId));
    }

}
