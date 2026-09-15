import QtQuick
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
    property Item hoveredAppButton: null
    property Item lastHoveredButton: null
    readonly property bool isVertical: dockContent?.isVertical ?? false
    readonly property string dockPos: dockContent?.dockPos ?? dock.dockEffectivePosition
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
        root.dockContent.removeAppFromGroup(root.groupId, appData.appId ?? "")
    }

    function _getSlotMagScale() {
        return 1.0
    }

    contentComponent: GridLayout {
        columns: 3
        columnSpacing: Appearance.sizes.elevationMargin * 0.5
        rowSpacing: Appearance.sizes.elevationMargin * 0.5
        implicitWidth: root.appButtonSize * 3 + columnSpacing * 2

        Repeater {
            model: root.apps
            delegate: RippleButton {
                id: appButton
                required property var modelData
                readonly property var appData: modelData
                property real dragStartX: 0
                property real dragStartY: 0
                property bool dragActive: false
                property bool suppressClick: false
                readonly property bool appHovered: root.hoveredAppButton === appButton

                Layout.preferredWidth: root.appButtonSize
                Layout.preferredHeight: root.appButtonSize
                padding: 0
                buttonRadius: Appearance.rounding.normal
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                scale: appButton.appHovered ? 1.08 : 1.0

                Behavior on scale {
                    animation: Appearance.animation.dockMagnification.numberAnimation.createObject(appButton)
                }

                contentItem: DockIcon {
                    anchors.fill: parent
                    appId: modelData?.appId ?? ""
                    desktopEntry: TaskbarApps.getCachedDesktopEntry(modelData?.appId ?? "")
                    isRunning: (modelData?.toplevels?.length ?? 0) > 0
                }

                pressedAction: event => {
                    dragStartX = event.x
                    dragStartY = event.y
                    dragActive = false
                    root.draggingAppId = ""
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
                    // Keep the right-click inside the popup. Closing the
                    // popup synchronously can otherwise let the release be
                    // delivered to the group tile underneath it.
                    if (event)
                        event.accepted = true
                    root.removeDraggedApp(modelData)
                    root.hoveredAppButton = null
                    root.lastHoveredButton = null
                    root.draggingAppId = ""
                    Qt.callLater(() => root.close())
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
                        root.draggingAppId = modelData?.appId ?? ""
                        root.hoveredAppButton = null
                    }
                }

                releaseAction: () => {
                    if (!appButton.dragActive)
                        return

                    const shouldRemove = !root.pointerInsidePopup
                    appButton.dragActive = false
                    appButton.suppressClick = true
                    root.draggingAppId = ""
                    if (shouldRemove) {
                        root.removeDraggedApp(modelData)
                        root.lastHoveredButton = null
                        root.close()
                    }
                }

                canceledAction: () => {
                    appButton.dragActive = false
                    appButton.suppressClick = true
                    if (root.draggingAppId === (modelData?.appId ?? ""))
                        root.draggingAppId = ""
                    if (root.hoveredAppButton === appButton)
                        root.hoveredAppButton = null
                }

                onClicked: {
                    if (appButton.suppressClick) {
                        appButton.suppressClick = false
                        return
                    }
                    root.launchApp(modelData)
                    root.close()
                }

                Rectangle {
                    visible: appButton.dragActive
                    anchors.fill: parent
                    z: 2
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colErrorContainer
                    opacity: 0.72

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "remove_circle"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

            }
        }

        Item {
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0

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
