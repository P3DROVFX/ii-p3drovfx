pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock

import "./widgets"

DockButton {
    id: root

    property var apps: []
    property var dockContent: null
    property int delegateIndex: -1
    property string groupId: ""
    property bool groupHovered: false
    property var displayedApps: []
    property real groupTransitionOpacity: 1.0
    property real groupTransitionScale: 1.0

    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotWidth: root.dockContent?.buttonSlotSize ?? (root.buttonSize + root.dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.dockContent.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (root.buttonSize + root.dotMarginV * 2)
    readonly property real magScale: root.dockMagnificationScale
    readonly property string dockPos: root.dockContent?.dockPos ?? "bottom"
    readonly property real cellSize: root.buttonSize * 0.36
    readonly property real gridGap: Math.max(2, Math.round(root.buttonSize * 0.04))
    readonly property bool groupExitRequested: root.dockContent?.isGroupExiting(root.groupId) ?? false
    readonly property bool groupEntryRequested: root.dockContent?.isGroupEntryTransition(root.groupId) ?? false
    readonly property int groupAnimationDuration: root.dockContent?.groupAnimationDuration ?? Appearance.animation.elementMoveFast.duration

    function _appId(appData) {
        return String(appData?.appId ?? "");
    }

    function syncDisplayedApps() {
        const currentApps = Array.from(root.apps ?? []).filter(appData => _appId(appData) !== "");
        const currentById = {};
        for (const appData of currentApps)
            currentById[_appId(appData)] = appData;

        const nextDisplayed = [];
        const retained = {};
        for (const entry of root.displayedApps ?? []) {
            const appId = _appId(entry?.data);
            if (!appId)
                continue;
            if (currentById[appId]) {
                nextDisplayed.push({ key: appId, data: currentById[appId], leaving: false });
                retained[appId] = true;
            } else if (!entry.leaving) {
                // Keep the old icon in the grid until its exit animation ends.
                nextDisplayed.push({ key: appId, data: entry.data, leaving: true });
            }
        }

        // A delegate can be recreated when the containing dock model changes.
        // Rehydrate a member removed from an existing group so the exit is not
        // lost just because the Repeater chose to replace the tile.
        const dockContent = root.dockContent;
        if (dockContent?.groupTransitionKind === "remove"
                && dockContent.groupTransitionGroupId === root.groupId) {
            for (const appId of dockContent.groupTransitionAppIds ?? []) {
                if (currentById[appId] || nextDisplayed.some(entry => entry.key === appId))
                    continue;
                nextDisplayed.unshift({
                    key: appId,
                    data: dockContent._appDataForId(appId),
                    leaving: true
                });
            }
        }

        for (const appData of currentApps) {
            const appId = _appId(appData);
            if (!retained[appId])
                nextDisplayed.push({ key: appId, data: appData, leaving: false });
        }

        root.displayedApps = nextDisplayed;
        if (nextDisplayed.some(entry => entry.leaving))
            memberExitTimer.restart();
    }

    function purgeLeavingApps() {
        root.displayedApps = (root.displayedApps ?? []).filter(entry => !entry.leaving);
    }

    function playGroupEntryAnimation() {
        root.groupTransitionOpacity = 0.0;
        root.groupTransitionScale = 0.72;
        Qt.callLater(function () {
            if (!root)
                return;
            root.groupTransitionOpacity = 1.0;
            root.groupTransitionScale = 1.0;
        });
    }

    function playGroupExitAnimation() {
        root.groupTransitionOpacity = 0.0;
        root.groupTransitionScale = 0.72;
    }

    Component.onCompleted: {
        syncDisplayedApps();
        if (root.groupExitRequested)
            playGroupExitAnimation();
        else if (root.groupEntryRequested)
            playGroupEntryAnimation();
    }

    onAppsChanged: syncDisplayedApps()

    Connections {
        target: root.dockContent
        function onGroupMutationRevisionChanged() {
            if (root.groupExitRequested)
                root.playGroupExitAnimation();
        }
        function onGroupTransitionRevisionChanged() {
            if (root.groupEntryRequested)
                root.playGroupEntryAnimation();
        }
    }

    Timer {
        id: memberExitTimer
        interval: root.groupAnimationDuration
        repeat: false
        onTriggered: root.purgeLeavingApps()
    }

    width: root.slotWidth
    height: root.slotHeight
    transformOrigin: {
        if (root.dockPos === "top")
            return Item.Top
        if (root.dockPos === "left")
            return Item.Left
        if (root.dockPos === "right")
            return Item.Right
        return Item.Bottom
    }
    scale: root.magScale * root.groupTransitionScale
    opacity: root.groupTransitionOpacity
    z: root.magScale > 1.01 ? Math.round(root.magScale * 100) : 1

    Behavior on groupTransitionOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Behavior on groupTransitionScale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Rectangle {
        id: groupSurface
        width: root.buttonSize * 0.92
        height: root.buttonSize * 0.92
        anchors.centerIn: parent
        radius: Appearance.rounding.small
        color: root.groupHovered
            ? Appearance.colors.colLayer2Base
            : Appearance.colors.colLayer1Base

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Grid {
            anchors.centerIn: parent
            columns: 2
            rows: 2
            spacing: root.gridGap

            Repeater {
                model: (root.displayedApps ?? []).slice(0, 4)
                delegate: Item {
                    required property var modelData
                    readonly property var appData: modelData?.data ?? null
                    readonly property bool leaving: modelData?.leaving ?? false
                    property real transitionOpacity: 1.0
                    property real transitionScale: 1.0
                    width: root.cellSize
                    height: root.cellSize

                    Component.onCompleted: {
                        transitionOpacity = leaving ? 1.0 : 0.0;
                        transitionScale = leaving ? 1.0 : 0.72;
                        Qt.callLater(function () {
                            if (!parent)
                                return;
                            transitionOpacity = leaving ? 0.0 : 1.0;
                            transitionScale = leaving ? 0.72 : 1.0;
                        });
                    }

                    Behavior on transitionOpacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Behavior on transitionScale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    opacity: transitionOpacity
                    scale: transitionScale

                    DockIcon {
                        anchors.fill: parent
                        appId: appData?.appId ?? ""
                        desktopEntry: TaskbarApps.getCachedDesktopEntry(appData?.appId ?? "")
                        isRunning: (appData?.toplevels?.length ?? 0) > 0
                    }
                }
            }
        }

        Rectangle {
            visible: root.apps.length > 4
            width: Math.max(root.buttonSize * 0.25, Appearance.font.pixelSize.small)
            height: width
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -width * 0.18
            anchors.bottomMargin: -height * 0.18
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            StyledText {
                anchors.centerIn: parent
                text: "+" + String(root.apps.length - 4)
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
        }
    }

    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property int pressButton: Qt.NoButton
        property bool dragActive: false

        onEntered: {
            root.groupHovered = true
            if (root.dockContent?.suppressHover)
                return
            root.dockContent?.onButtonEntered(root)
        }
        onExited: {
            root.groupHovered = false
            root.dockContent?.onButtonExited(root)
        }
        onPressed: event => {
            pressButton = event.button
            pressCoord = root.dockContent?.isVertical ? event.y : event.x
        }
        onPositionChanged: event => {
            if (!pressed || pressButton !== Qt.LeftButton)
                return
            const currentCoord = root.dockContent?.isVertical ? event.y : event.x
            const distance = Math.abs(currentCoord - pressCoord)
            if (!dragActive && distance > 5 && root.delegateIndex >= 0) {
                dragActive = true
                root.groupHovered = false
                root.dockContent?.startItemDrag(root.delegateIndex, interactionArea, event.x, event.y)
            }
            if (dragActive)
                root.dockContent?.moveItemDrag(interactionArea, event.x, event.y)
        }
        onReleased: event => {
            if (event.button === Qt.RightButton) {
                dragActive = false
                pressButton = Qt.NoButton
                // A right-click inside the separate group popup can finish
                // after that popup starts closing. Do not let that release
                // fall through and remove the whole group underneath it.
                if (groupPopup.active)
                    return
                groupPopup.close()
                root.dockContent?.removeAppGroup(root.groupId)
                return
            }
            if (dragActive) {
                dragActive = false
                pressButton = Qt.NoButton
                root.dockContent?.endItemDrag()
                return
            }
            pressButton = Qt.NoButton
            root.openGroup()
        }
        onCanceled: {
            pressButton = Qt.NoButton
            if (dragActive) {
                dragActive = false
                root.dockContent?.cancelDrag()
            }
        }
    }

    function openGroup() {
        groupPopup.open()
    }

    DockGroupPopup {
        id: groupPopup
        anchorItem: root
        apps: root.apps
        groupId: root.groupId
        dockContent: root.dockContent
    }

    DockTooltip {
        parentItem: root
        text: Translation.tr("Right click to dissolve group\nRight click an app to remove it from the group")
        showTooltip: root.groupHovered
        tooltipOffset: -root.dotMargin
    }

    Connections {
        target: groupPopup
        function onActiveChanged() {
            if (!root.dockContent)
                return
            if (groupPopup.active)
                root.dockContent.registerContextMenuOpen()
            else
                root.dockContent.registerContextMenuClose()
        }
    }

    Component.onDestruction: {
        if (root.dockContent && groupPopup.active)
            root.dockContent.registerContextMenuClose()
    }
}
