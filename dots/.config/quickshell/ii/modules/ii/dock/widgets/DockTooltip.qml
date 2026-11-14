import QtQuick

/**
 * A request for the dock's tooltip (DockTooltipHost). Items declare one with
 * the label and when to show it; the host — one per dock — draws the bubble,
 * slides it between items and swaps the label. Nothing here is a window: an
 * item asking for a tooltip costs a property, not a native popup.
 */
Item {
    id: root

    property Item parentItem: parent
    property string text: ""
    property bool showTooltip: false
    // Kept for callers written against the per-item popup.
    property int tooltipOffset: 0

    visible: false
    width: 0
    height: 0

    // The host lives on DockContent (`dockTooltipHost`); found by walking up
    // from the item the tooltip points at.
    property var host: null
    function _findHost() {
        for (let p = root.parentItem; p; p = p.parent) {
            if (p.dockTooltipHost !== undefined && p.dockTooltipHost !== null)
                return p.dockTooltipHost;
        }
        return null;
    }

    function _sync() {
        const host = root._findHost();
        root.host = host;
        if (!host)
            return;
        if (root.showTooltip && root.text.length > 0)
            host.requestShow(root);
        else
            host.release(root);
    }

    onShowTooltipChanged: root._sync()
    onTextChanged: {
        const host = root._findHost();
        root.host = host;
        if (root.showTooltip && host)
            host.updateText(root);
        else
            root._sync();
    }
    Component.onDestruction: {
        const host = root._findHost();
        if (host)
            host.release(root);
        else if (root.host && typeof root.host.release === "function")
            root.host.release(root);
        root.host = null;
    }
}
