pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
            } else {
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

    DockMotion {
        id: groupMotion
        progress: 1
        duration: root.groupAnimationDuration
    }

    Component.onCompleted: {
        syncDisplayedApps();
        if (root.groupExitRequested) {
            groupMotion.animateTo(0);
        } else if (root.groupEntryRequested && root.dockContent?.groupTransitionKind === "create") {
            groupMotion.reset(0);
            groupMotion.animateTo(1);
        }
    }

    onAppsChanged: syncDisplayedApps()
    onGroupExitRequestedChanged: groupMotion.animateTo(root.groupExitRequested ? 0 : 1)

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
    scale: root.magScale * (0.72 + groupMotion.progress * 0.28)
    opacity: groupMotion.progress
    z: root.magScale > 1.01 ? Math.round(root.magScale * 100) : 1

    layer.enabled: groupMotion.progress > 0 && groupMotion.progress < 1
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 8
        blur: 1 - groupMotion.progress
    }

    Rectangle {
        id: groupSurface
        width: root.buttonSize * 0.92
        height: root.buttonSize * 0.92
        anchors.centerIn: parent
        radius: Appearance.rounding.small
        color: root.groupHovered
            ? Appearance.colors.colLayer0Hover
            : Appearance.colors.colLayer0

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StableDockModel {
            id: memberModel
            keyRole: "key"
            sourceValues: (root.displayedApps ?? []).slice(0, 4)
        }

        Item {
            anchors.centerIn: parent
            width: root.cellSize * 2 + root.gridGap
            height: width

            Repeater {
                model: memberModel
                delegate: Item {
                    id: member
                    required property string entryKey
                    required property int index
                    readonly property var entry: memberModel.itemsByKey[entryKey]
                    readonly property var appData: entry?.data ?? null
                    readonly property bool leaving: entry?.leaving ?? false
                    width: root.cellSize
                    height: root.cellSize
                    x: (index % 2) * (root.cellSize + root.gridGap)
                    y: Math.floor(index / 2) * (root.cellSize + root.gridGap)
                    opacity: memberMotion.progress
                    scale: 0.72 + memberMotion.progress * 0.28
                    transform: Translate { y: (1 - memberMotion.progress) * root.cellSize * 0.25 }

                    DockMotion {
                        id: memberMotion
                        duration: root.groupAnimationDuration
                    }
                    Component.onCompleted: {
                        memberMotion.reset(leaving ? 1 : 0);
                        memberMotion.animateTo(leaving ? 0 : 1);
                    }
                    onLeavingChanged: memberMotion.animateTo(leaving ? 0 : 1)
                    Behavior on x {
                        NumberAnimation {
                            duration: root.groupAnimationDuration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: root.groupAnimationDuration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    layer.enabled: memberMotion.progress > 0 && memberMotion.progress < 1
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 8
                        blur: 1 - memberMotion.progress
                    }
                    DockIcon {
                        anchors.fill: parent
                        appId: member.appData?.appId ?? ""
                        desktopEntry: TaskbarApps.getCachedDesktopEntry(member.appData?.appId ?? "")
                        isRunning: (member.appData?.toplevels?.length ?? 0) > 0
                        renderScale: root.dockContent?.magnificationRenderScale ?? 1
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
        property point pressPoint: Qt.point(0, 0)
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
            pressPoint = interactionArea.mapToItem(null, event.x, event.y)
        }
        onPositionChanged: event => {
            if (!pressed || pressButton !== Qt.LeftButton)
                return
            const point = interactionArea.mapToItem(null, event.x, event.y)
            const distance = Math.abs(root.dockContent?.isVertical ? point.y - pressPoint.y : point.x - pressPoint.x)
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
