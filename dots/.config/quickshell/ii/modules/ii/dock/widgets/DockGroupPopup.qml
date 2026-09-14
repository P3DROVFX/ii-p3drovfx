import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock

import ".."

DockContextMenuBase {
    id: root

    property var apps: []
    property var dockContent: null
    property string groupId: ""
    property string draggingAppId: ""
    property var pendingRemovals: []
    property Item hoveredAppButton: null
    property Item lastHoveredButton: null
    readonly property bool isVertical: dockContent?.isVertical ?? false
    dockPos: dockContent?.dockPos ?? "bottom"
    readonly property bool dragging: draggingAppId !== ""
    readonly property bool buttonHovered: hoveredAppButton !== null
    readonly property bool anyContextMenuOpen: false
    // DockPreviewPopup updates this while its compact window is resizing.
    property bool popupIsResizing: false
    readonly property real maxWindowPreviewHeight: dockContent?.maxWindowPreviewHeight ?? 200
    readonly property real maxWindowPreviewWidth: dockContent?.maxWindowPreviewWidth ?? 300
    readonly property real windowControlsHeight: dockContent?.windowControlsHeight ?? 30
    readonly property point hoveredButtonCenter: {
        const item = root.lastHoveredButton
        if (!item)
            return Qt.point(0, 0)
        return item.mapToItem(null, item.width / 2, item.height / 2)
    }
    readonly property real appButtonSize: Appearance.sizes.dockButtonSize

    motionMargin: root.appButtonSize
    useDockSlideAnimation: true
    showHeader: false
    symmetricContentMargins: true

    function launchApp(appData) {
        if (!appData)
            return

        const toplevels = appData.toplevels ?? []
        const fallbackToplevel = toplevels.length > 0 ? toplevels[toplevels.length - 1] : null
        for (const toplevel of toplevels) {
            if (toplevel?.activated) {
                toplevel.activate()
                return
            }
        }

        // A window on another workspace is not `activated`, but it is still
        // the same application instance. Prefer focusing that toplevel over
        // executing the desktop entry and spawning a second instance.
        if (fallbackToplevel) {
            fallbackToplevel.activate()
            return
        }

        const desktopEntry = TaskbarApps.getCachedDesktopEntry(appData.appId ?? "")
        desktopEntry?.execute()
    }

    function removeDraggedApp(appData) {
        if (!appData || !root.dockContent)
            return
        return root.dockContent.removeAppFromGroup(root.groupId, appData.appId ?? "")
    }

    function commitRemoval(appData) {
        root.pendingRemovals = root.pendingRemovals.filter(app => app.appId !== appData?.appId);
        const lastMember = root.apps.length === 1;
        const removed = root.removeDraggedApp(appData);
        if (removed && lastMember)
            root.close();
        return removed;
    }

    function _getSlotMagScale() {
        return 1.0
    }

    StableDockModel {
        id: appModel
        sourceValues: root.apps
        keyRole: "appId"
    }

    onClosed: {
        const pending = root.pendingRemovals.slice();
        root.pendingRemovals = [];
        for (const appData of pending)
            root.removeDraggedApp(appData);
        root.draggingAppId = "";
        root.hoveredAppButton = null;
        root.lastHoveredButton = null;
    }

    contentComponent: Item {
        id: appGrid
        readonly property real gap: Appearance.sizes.elevationMargin * 0.5
        implicitWidth: root.appButtonSize * 3 + gap * 2
        implicitHeight: Math.max(0, Math.ceil(appModel.count / 3) * (root.appButtonSize + gap) - gap)

        Repeater {
            model: appModel
            delegate: RippleButton {
                id: appButton
                required property string entryKey
                required property int index
                readonly property var appData: appModel.itemsByKey[entryKey] ?? null
                readonly property real popupReveal: root.contentProgress(index)
                readonly property real reveal: popupReveal * memberMotion.progress
                property real removalX: 0
                property real removalY: 0
                property real dragX: 0
                property real dragY: 0
                property bool removing: false
                property real dragStartX: 0
                property real dragStartY: 0
                property bool dragActive: false
                property bool suppressClick: false
                readonly property bool appHovered: root.hoveredAppButton === appButton

                x: (index % 3) * (root.appButtonSize + appGrid.gap)
                y: Math.floor(index / 3) * (root.appButtonSize + appGrid.gap)
                width: root.appButtonSize
                height: root.appButtonSize
                z: dragActive || removing ? 2 : 0
                enabled: !removing && !root.isClosing
                opacity: reveal
                Behavior on x {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                padding: 0
                buttonRadius: Appearance.rounding.normal
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                DockMotion {
                    id: memberMotion
                    progress: 1
                    onSettled: value => {
                        if (value === 0 && appButton.removing) {
                            if (!root.commitRemoval(appButton.appData)) {
                                appButton.removing = false;
                                appButton.resetDrag();
                                memberMotion.animateTo(1);
                            }
                        }
                    }
                }

                function removeMember() {
                    if (appButton.removing)
                        return;
                    const length = Math.hypot(appButton.dragX, appButton.dragY);
                    appButton.removalX = length > 0 ? appButton.dragX / length : root.motionX;
                    appButton.removalY = length > 0 ? appButton.dragY / length : root.motionY;
                    root.pendingRemovals = root.pendingRemovals.concat([appButton.appData]);
                    appButton.removing = true;
                    root.hoveredAppButton = null;
                    root.lastHoveredButton = null;
                    root.draggingAppId = "";
                    memberMotion.animateTo(0);
                }

                function resetDrag() {
                    appButton.dragActive = false;
                    appButton.dragX = 0;
                    appButton.dragY = 0;
                    root.draggingAppId = "";
                }

                contentItem: DockIcon {
                    anchors.fill: parent
                    appId: appButton.appData?.appId ?? ""
                    desktopEntry: TaskbarApps.getCachedDesktopEntry(appButton.appData?.appId ?? "")
                    isRunning: (appButton.appData?.toplevels?.length ?? 0) > 0
                    // Unfold from the compact grid. Shared icons retain identity
                    // while spreading into their individual popup slots.
                    scale: 0.36 + 0.64 * appButton.reveal
                    transform: Translate {
                        x: appButton.dragX + (1 - appButton.popupReveal) * (appGrid.width / 2 - appButton.x - appButton.width / 2) + (1 - memberMotion.progress) * appButton.removalX * root.appButtonSize * 0.35
                        y: appButton.dragY + (1 - appButton.popupReveal) * (root.motionY * root.appButtonSize + appGrid.height / 2 - appButton.y - appButton.height / 2) + (1 - memberMotion.progress) * appButton.removalY * root.appButtonSize * 0.35
                    }
                    layer.enabled: appButton.reveal > 0 && appButton.reveal < 1
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 8
                        blur: 1 - appButton.reveal
                    }
                }

                Behavior on dragX {
                    enabled: !appButton.dragActive && !appButton.removing
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on dragY {
                    enabled: !appButton.dragActive && !appButton.removing
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                pressedAction: event => {
                    dragStartX = event.x
                    dragStartY = event.y
                    suppressClick = false
                    resetDrag()
                }

                enteredAction: () => {
                    if (root.dragging)
                        return
                    root.hoveredAppButton = appButton
                    root.lastHoveredButton = appButton
                }

                exitedAction: () => {
                    if (root.hoveredAppButton === appButton)
                        root.hoveredAppButton = null
                }

                altAction: event => {
                    if (event)
                        event.accepted = true;
                    appButton.removeMember();
                }

                positionChangedAction: event => {
                    if (!appButton.down)
                        return

                    const dx = event.x - appButton.dragStartX
                    const dy = event.y - appButton.dragStartY
                    const distance = Math.sqrt(dx * dx + dy * dy)
                    const dragThreshold = Math.max(5, root.appButtonSize * 0.12)
                    if (!appButton.dragActive && distance > dragThreshold) {
                        appButton.dragActive = true
                        root.draggingAppId = appButton.appData?.appId ?? ""
                        root.hoveredAppButton = null
                    }
                    if (appButton.dragActive) {
                        appButton.dragX = dx;
                        appButton.dragY = dy;
                    }
                }

                releaseAction: () => {
                    if (!appButton.dragActive)
                        return

                    const shouldRemove = !root.pointerInsidePopup;
                    appButton.suppressClick = true;
                    if (shouldRemove)
                        appButton.removeMember();
                    else
                        appButton.resetDrag();
                }

                canceledAction: () => {
                    if (appButton.removing)
                        return;
                    appButton.suppressClick = true;
                    appButton.resetDrag();
                    if (root.hoveredAppButton === appButton)
                        root.hoveredAppButton = null;
                }

                onClicked: {
                    if (appButton.suppressClick) {
                        appButton.suppressClick = false
                        return
                    }
                    root.launchApp(appButton.appData)
                    root.close()
                }


            }
        }

        Item {
            width: 0
            height: 0

            Loader {
                active: Config.options?.dock?.enablePreview ?? true
                sourceComponent: DockPreviewPopup {
                    dockRoot: root
                    // This Loader owns the actual PopupWindow created by
                    // DockContextMenuBase. Use it as the preview host so the
                    // child preview coordinates stay in the popup's scene.
                    dockWindow: root.item ?? root.QsWindow?.window ?? null
                    anchorItem: root.lastHoveredButton
                    compactMode: true
                    appTopLevel: root.lastHoveredButton?.appData ?? null
                }
            }
        }
    }
}
