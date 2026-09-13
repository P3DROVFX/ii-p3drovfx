pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property string text: ""
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    property real horizontalMargin: horizontalPadding
    property real verticalMargin: verticalPadding
    
    function updateAnchor() {
        tooltipLoader.item?.anchor.updateAnchor();
    }

    readonly property bool parentHovered: {
        if (!parent)
            return false;
        if (parent.hovered !== undefined)
            return Boolean(parent.hovered);
        if (parent.containsMouse !== undefined)
            return Boolean(parent.containsMouse);
        return false;
    }

    readonly property bool internalVisibleCondition: Config.options.bar.tooltips.enableTooltips
        && ((extraVisibleCondition && root.parentHovered) || alternativeVisibleCondition)

    // PopupAnchor dereferences whatever it is handed without a null check, so the tooltip
    // window must not exist at all while we have nothing valid to anchor it to. That happens
    // when the host window is torn down under us — e.g. the tray overflow popup closing.
    readonly property var hostWindow: root.QsWindow?.window ?? null
    property var anchorEdges: Edges.Top
    property var anchorGravity: anchorEdges

    property Item contentItem: StyledToolTipContent {
        id: contentItem
        anchors.centerIn: parent
        text: root.text
        shown: false
        Component.onCompleted: shown = true
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }

    Loader {
        id: tooltipLoader
        anchors.fill: parent
        active: Config.options.bar.tooltips.enableTooltips && root.internalVisibleCondition && root.hostWindow !== null && root.parent !== null
        sourceComponent: PopupWindow {
            id: tooltipWindow
            visible: true

            // Assign the anchor item once. Prefer item-only: PopupAnchor::setWindow()
            // clears any prior item through a path that null-derefs when an item was
            // already set (quickshell bug in onItemWindowChanged). The item derives
            // its window on its own.
            Component.onCompleted: {
                tooltipWindow.anchor.item = root.parent;
            }

            // contentItem is owned by root and outlives this window, so detach it before the
            // window's item tree is torn down instead of leaving a dangling visual parent.
            Component.onDestruction: {
                if (root.contentItem)
                    root.contentItem.parent = null;
            }

            anchor {
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }
            mask: Region {
                item: null
            }

            color: "transparent"
            implicitWidth: root.contentItem.implicitWidth + root.horizontalMargin * 2
            implicitHeight: root.contentItem.implicitHeight + root.verticalMargin * 2

            data: [root.contentItem]
        }
    }
}
