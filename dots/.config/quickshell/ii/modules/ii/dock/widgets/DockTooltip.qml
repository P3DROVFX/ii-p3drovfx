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
    // from the item the tooltip points at. The nearest dock also takes the
    // request for a host that is not up yet.
    property var host: null
    property bool _hostRetryPending: false
    property int _hostRetries: 0
    function _dock() {
        for (let p = root.parentItem; p; p = p.parent) {
            if (p.dockTooltipHost !== undefined)
                return p;
        }
        return null;
    }
    function _findHost() {
        const dock = root._dock();
        return dock?.dockTooltipHost ?? null;
    }

    // No host yet: ask the dock for one, then show once it exists. Bounded, so
    // a dock that never brings it up does not keep a callback alive per frame.
    function _requestHost() {
        const dock = root._dock();
        if (!dock || typeof dock.requestTooltipHost !== "function")
            return;
        dock.requestTooltipHost();
        if (root._hostRetryPending)
            return;
        root._hostRetryPending = true;
        root._hostRetries = 0;
        Qt.callLater(root._retryForHost);
    }
    function _retryForHost() {
        if (!root.showTooltip || root.text.length === 0) {
            root._hostRetryPending = false;
            return;
        }
        if (root._findHost()) {
            root._hostRetryPending = false;
            root._sync();
            return;
        }
        root._hostRetries += 1;
        if (root._hostRetries >= 20) {
            root._hostRetryPending = false;
            return;
        }
        Qt.callLater(root._retryForHost);
    }

    function _sync() {
        const host = root._findHost();
        root.host = host;
        if (!host) {
            if (root.showTooltip && root.text.length > 0)
                root._requestHost();
            return;
        }
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
