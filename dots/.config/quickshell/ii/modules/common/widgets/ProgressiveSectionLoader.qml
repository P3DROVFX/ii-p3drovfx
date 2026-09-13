pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

Item {
    id: root

    property url source
    property bool active: false
    property bool showSkeleton: true
    property real estimatedHeight: 200
    property bool asynchronous: true
    property bool prioritizeOnViewport: false
    property bool prioritizeOnSearch: false
    property string sectionTitle: ""
    property real viewportLookahead: 0.75
    // Keeps a lazy section inside a parent-provided viewport. This is useful
    // for scrollable previews that historically filled the remaining layout
    // space instead of contributing their full content height.
    property bool fillAvailableHeight: false

    property bool priorityRequested: false

    readonly property bool loading: sectionLoader.status === Loader.Loading
    readonly property bool ready: sectionLoader.status === Loader.Ready && sectionLoader.item !== null
    readonly property real loadedHeight: sectionLoader.item ? sectionLoader.item.implicitHeight : 0
    readonly property bool searchRequested: root.prioritizeOnSearch
        && root.sectionTitle !== ""
        && SearchRegistry.currentSearch.toLowerCase() === root.sectionTitle.toLowerCase()
    readonly property Item viewport: root.findViewport(root.parent)

    // Quantised scroll position. Re-running mapToItem() for every scrolled
    // pixel, in every lazy section on the page, is a per-frame cost the
    // lookahead below makes unnecessary.
    readonly property int scrollStep: {
        const vp = root.viewport;
        return vp ? Math.floor(vp.contentY / 120) : 0;
    }

    readonly property bool nearViewport: {
        if (root.ready || root.priorityRequested)
            return true;

        const vp = root.viewport;
        if (!vp || vp.height <= 0)
            return false;

        // These reads make the binding react to scrolling and layout changes.
        // `root.height` is deliberately not among them: it is driven by
        // implicitHeight, which depends on `ready`, which this binding can
        // trigger - that cycle is what QML reported as a binding loop.
        root.scrollStep;
        vp.height;
        root.y;

        // The normal stage queue owns the initial viewport. Viewport priority
        // only takes over after the user has started scrolling.
        if (root.scrollStep <= 0)
            return false;

        const point = root.mapToItem(vp, 0, 0);
        const lookahead = Math.max(root.estimatedHeight, vp.height * root.viewportLookahead);
        return point.y < vp.height + lookahead
            && point.y + root.estimatedHeight > -lookahead;
    }

    signal loaded()

    function findViewport(node) {
        let current = node;
        while (current) {
            if (current.flickableDirection !== undefined && current.contentY !== undefined)
                return current;
            current = current.parent;
        }
        return null;
    }

    function requestPriorityLoad() {
        if (!root.priorityRequested)
            root.priorityRequested = true;
    }

    onNearViewportChanged: {
        if (root.prioritizeOnViewport && root.nearViewport)
            root.requestPriorityLoad();
    }

    onSearchRequestedChanged: {
        if (root.searchRequested)
            root.requestPriorityLoad();
    }

    Layout.fillWidth: true
    implicitHeight: root.ready ? root.loadedHeight : Math.max(0, root.estimatedHeight)
    clip: root.fillAvailableHeight

    Loader {
        id: sectionLoader
        anchors.left: parent.left
        anchors.right: parent.right
        active: root.active
            || root.priorityRequested
        asynchronous: root.asynchronous
        source: root.source
        height: root.fillAvailableHeight
            ? root.height
            : (root.ready ? root.loadedHeight : 0)

        onLoaded: root.loaded()
    }

    Rectangle {
        anchors.fill: parent
        visible: (root.active || root.priorityRequested) && !root.ready && root.showSkeleton
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.large

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.rounding.large
            spacing: Appearance.rounding.small

            Rectangle {
                Layout.preferredWidth: parent.width * 0.42
                Layout.preferredHeight: Appearance.font.pixelSize.normal
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.small
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                opacity: 0.72
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.small
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                opacity: 0.72
            }
        }
    }
}
