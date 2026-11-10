import QtQuick
import Quickshell
import qs.modules.common

/**
 * Slide-in sub-page overlay shared by settings pages that host widget config
 * sub-pages. Fill the page root with it (z above the main content) and bind
 * the main content's opacity to `slideProgress` for the cross-fade.
 * Sub-pages are expected to expose `showBackButton` and a `goBack` signal
 * (ContentPage does).
 */
Item {
    id: host

    // URL of the open sub-page; empty = closed. Resolve relative paths at the
    // call site (Qt.resolvedUrl) so they stay relative to the caller's file.
    property url activeSubPage: ""
    readonly property bool isOpen: activeSubPage.toString() !== ""
    readonly property alias subPageItem: subPageLoader.item
    signal subPageLoaded(var item)
    signal navigationChanged()
    // The Settings window uses this path to keep nested configuration pages
    // in the local mouse-back history (for example Drive -> Advanced Drive).
    readonly property var navigationPath: {
        const first = activeSubPage.toString();
        if (first === "")
            return [];

        const path = [first];
        const nested = host.nestedHost;
        if (nested && nested.navigationPath.length > 0)
            return path.concat(nested.navigationPath);
        return path;
    }

    // Hosts announce themselves to the nearest host above them, or to the
    // Settings window when there is none. Finding them used to be a binding
    // that walked the whole sub-page tree, and re-ran for every item added
    // to it while the page was being built.
    property var nestedHosts: []
    property var registeredWith: null

    readonly property Item nestedHost: {
        const page = subPageLoader.item;
        if (!page)
            return null;
        if (page.navigationPath !== undefined && page !== host)
            return page;
        for (const nested of host.nestedHosts) {
            if (nested && host.isWithin(nested, page))
                return nested;
        }
        return null;
    }

    function isWithin(node, ancestor) {
        for (let p = node; p; p = p.parent) {
            if (p === ancestor)
                return true;
        }
        return false;
    }

    function registerNestedHost(nested) {
        if (host.nestedHosts.indexOf(nested) === -1)
            host.nestedHosts = host.nestedHosts.concat([nested]);
    }

    function unregisterNestedHost(nested) {
        if (host.nestedHosts.indexOf(nested) !== -1)
            host.nestedHosts = host.nestedHosts.filter(entry => entry !== nested);
    }

    Component.onCompleted: {
        for (let p = host.parent; p; p = p.parent) {
            if (typeof p.registerNestedHost === "function") {
                p.registerNestedHost(host);
                host.registeredWith = p;
                return;
            }
        }
        const win = host.QsWindow.window;
        if (win && typeof win.registerSubPageHost === "function") {
            win.registerSubPageHost(host);
            host.registeredWith = win;
        }
    }

    Component.onDestruction: {
        const owner = host.registeredWith;
        if (!owner)
            return;
        if (typeof owner.unregisterNestedHost === "function")
            owner.unregisterNestedHost(host);
        else if (typeof owner.unregisterSubPageHost === "function")
            owner.unregisterSubPageHost(host);
    }
    // 1 when closed, 0 when fully open — bind the main page's opacity to this
    readonly property real slideProgress: width > 0 ? slider.x / width : 1

    function open(url) {
        activeSubPage = url;
    }

    function close() {
        activeSubPage = "";
    }

    function requestBack() {
        const win = host.QsWindow.window;
        if (win && win.navigateBack !== undefined && win.navigateBack())
            return;
        host.close();
    }

    function restoreNavigationPath(path) {
        const normalizedPath = Array.isArray(path) ? path : [];
        activeSubPage = normalizedPath.length > 0 ? normalizedPath[0] : "";

        // The Loader may need one event-loop turn to create the page before
        // its own ConfigSubPageHost can receive the remaining path.
        Qt.callLater(function() {
            const nested = host.nestedHost;
            if (nested && nested.restoreNavigationPath)
                nested.restoreNavigationPath(normalizedPath.slice(1));
        });
    }

    // Keep the host interactive while the close animation is leaving the
    // screen. Without this, the page underneath becomes hover/clickable for
    // the last frames of every sub-page transition.
    enabled: isOpen || slider.overlayActive
    onIsOpenChanged: {
        if (isOpen)
            slider.overlayActive = true;

    }
    onActiveSubPageChanged: host.navigationChanged()

    // Cover the entire host, including the area left behind while the page
    // slides closed. The loaded page is declared after this shield and stays
    // above it, so its controls remain usable while the parent page cannot
    // receive hover/click events.
    MouseArea {
        anchors.fill: parent
        enabled: host.enabled
        visible: host.enabled
        hoverEnabled: true
        // Leave the mouse side button for SettingsWindow's local history
        // handler. Normal buttons are still blocked from reaching the page
        // underneath while the sub-page is open or closing.
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: event => event.accepted = true
    }

    Item {
        id: slider
        z: 1

        // overlayActive stays true during the close animation (until x reaches width)
        property bool overlayActive: host.isOpen

        width: parent.width
        height: parent.height
        y: 0
        onXChanged: {
            if (!host.isOpen && x >= slider.width - 1)
                overlayActive = false;

        }
        // Open: x=0. Closed: x=width (off-screen right).
        x: host.isOpen ? 0 : slider.width

        Loader {
            id: subPageLoader

            anchors.fill: parent
            source: host.activeSubPage
            active: slider.overlayActive
            asynchronous: true
            onLoaded: {
                if (item.hasOwnProperty("showBackButton"))
                    item.showBackButton = true;

                if (item.goBack !== undefined)
                    item.goBack.connect(host.requestBack);

                host.subPageLoaded(item);
            }
        }

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }

        }

    }

}
