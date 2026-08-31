pragma ComponentBehavior: Bound

import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

import "./widgets"

Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property bool dockRevealed: false
    property bool dockWindowVisible: true
    property int delegateIndex: -1
    property bool pickerOpen: false
    signal pickerRequested()

    readonly property var screen: root.dockContent?.currentScreen ?? null
    readonly property string screenName: root.screen?.name ?? ""
    readonly property string appId: String(Config.options?.dock?.livePreviewAppId ?? "").trim()
    readonly property var desktopEntry: root.appId
        ? TaskbarApps.getCachedDesktopEntry(root.appId)
        : null
    readonly property var selectedToplevel: {
        // Explicit reads keep the per-monitor selection reactive when the
        // picker changes app/window policy without creating a second model.
        const preferred = DockLivePreviewService.preferredAppId;
        const follows = DockLivePreviewService.followActiveWindow;
        const locked = DockLivePreviewService.lockedToplevel;
        const revision = DockLivePreviewService.resolutionRevision;
        return DockLivePreviewService.selectedToplevelFor(root.screen);
    }
    readonly property bool hasSelectedApp: root.appId !== ""
    readonly property bool captureModeAllows: (Config.options?.dock?.livePreviewCaptureMode ?? "visible") !== "hover"
        || root.hovered
    readonly property bool dockPrivacyAllowsCapture: !GlobalStates.screenLocked
        && !(GlobalStates.oledSaverMonitors ?? []).includes(root.screenName)
        && !(root.screenName && GlobalStates.isMediaModeActiveForScreen(root.screenName))
    readonly property bool widgetActuallyVisible: root.visible && root.width > 1 && root.height > 1
    readonly property bool captureRequested: (Config.options?.dock?.enableLivePreviewWidget ?? false)
        && root.dockRevealed
        && root.dockWindowVisible
        && root.widgetActuallyVisible
        && !root.isVertical
        && !(root.dockContent?.dragging ?? false)
        && root.selectedToplevel !== null
        && root.captureModeAllows
        && root.dockPrivacyAllowsCapture

    property bool captureLease: false
    readonly property bool captureActive: root.captureLease
        && DockLivePreviewService.activeCaptureScreenName === root.screenName
        && (root.captureRequested || captureTeardownTimer.running)

    property var displayedToplevel: null
    property var pendingToplevel: null
    property string transitionPhase: "stable"
    property real previewOpacity: 0.0
    readonly property bool captureReady: root.captureActive
        && root.displayedToplevel !== null
        && screencopyView.hasContent
        && (root.transitionPhase === "stable" || root.transitionPhase === "enteringNew")
    property bool captureUnavailable: false

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin
        ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotWidth: root.dockContent?.buttonSlotSize
        ?? (root.buttonSize + root.dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (root.buttonSize + root.dotMarginV * 2)
    readonly property real previewSlots: Math.max(2, Math.min(6, Config.options?.dock?.livePreviewSlots ?? 2))
    readonly property real iconSize: Math.min(root.buttonSize * 0.72, root.slotHeight - root.dotMarginV * 2)
    // The compositor frame is intentionally captured above display size so
    // the small dock surface stays readable after the requested crop/zoom.
    readonly property real previewZoom: 1.55
    // A 5x target made every live frame much larger than the dock surface.
    // Keep one device-pixel minimum while capping the compositor workload.
    readonly property real captureResolutionScale: Math.min(2.0, Math.max(1.0, root.screen?.devicePixelRatio ?? 1.0))
    readonly property real overlayInset: Math.max(3, Math.round(root.dotMarginV * 0.45))
    readonly property real widgetRadius: (Config.options?.dock?.widgetRadius ?? -1) >= 0
        ? Config.options.dock.widgetRadius
        : Appearance.rounding.normal

    width: root.isVertical ? root.slotWidth : root.slotWidth * root.previewSlots
    height: root.slotHeight
    implicitWidth: width
    implicitHeight: height
    clip: true

    function releaseCaptureNow() {
        captureTeardownTimer.stop();
        root.captureLease = false;
        DockLivePreviewService.releaseCapture(root.screenName);
    }

    Component.onDestruction: {
        // The outer DockContent loader can destroy this item while the
        // teardown timer is pending; do not leave the singleton's arbitration
        // lease owned by a component that no longer exists.
        if (root.captureLease)
            DockLivePreviewService.releaseCapture(root.screenName);
    }

    function updateCaptureLease() {
        if (root.captureRequested) {
            captureTeardownTimer.stop();
            if (DockLivePreviewService.activeCaptureScreenName !== root.screenName)
                root.captureLease = false;
            if (!root.captureLease)
                root.captureLease = DockLivePreviewService.requestCapture(root.screenName);
            return;
        }

        if (!root.captureLease)
            return;

        if (root.shouldReleaseImmediately)
            root.releaseCaptureNow();
        else
            captureTeardownTimer.restart();
    }

    readonly property bool shouldReleaseImmediately: GlobalStates.screenLocked
        || !(Config.options?.dock?.enableLivePreviewWidget ?? false)
        || root.selectedToplevel === null
        || !(root.screenName && !((GlobalStates.oledSaverMonitors ?? []).includes(root.screenName)))
        || (root.screenName && GlobalStates.isMediaModeActiveForScreen(root.screenName))
        || (root.dockContent?.dragging ?? false)
        || root.isVertical

    function beginSelectionTransition(nextToplevel) {
        root.pendingToplevel = nextToplevel;

        if (root.transitionPhase === "exitingOld")
            return;

        if (root.displayedToplevel === null) {
            root.switchToPendingToplevel();
            return;
        }

        if (root.displayedToplevel === root.pendingToplevel)
            return;

        root.transitionPhase = "exitingOld";
        root.previewOpacity = 0.0;
        sourceTransitionTimer.restart();
    }

    function switchToPendingToplevel() {
        sourceTransitionTimer.stop();
        root.displayedToplevel = root.pendingToplevel;
        root.captureUnavailable = false;
        root.previewOpacity = 0.0;
        root.transitionPhase = root.displayedToplevel ? "waitingForFrame" : "stable";
        if (!root.displayedToplevel)
            root.pendingToplevel = null;
    }

    function activateSelection() {
        if (root.selectedToplevel) {
            DockLivePreviewService.activate(root.selectedToplevel);
            return;
        }
        root.openPicker();
    }

    function openPicker() {
        root.pickerOpen = true;
        root.pickerRequested();
    }

    onCaptureRequestedChanged: root.updateCaptureLease()
    onDockRevealedChanged: root.updateCaptureLease()
    onDockWindowVisibleChanged: root.updateCaptureLease()
    onSelectedToplevelChanged: root.beginSelectionTransition(root.selectedToplevel)
    onCaptureActiveChanged: {
        if (root.captureActive)
            root.captureUnavailable = false;
    }
    onIsVerticalChanged: root.updateCaptureLease()

    HoverHandler {
        id: hoverHandler
    }

    readonly property bool hovered: hoverHandler.hovered

    Timer {
        id: captureTeardownTimer
        interval: 220
        repeat: false
        onTriggered: root.releaseCaptureNow()
    }

    Timer {
        id: sourceTransitionTimer
        interval: 180
        repeat: false
        onTriggered: root.switchToPendingToplevel()
    }

    Connections {
        target: DockLivePreviewService

        function onCaptureArbitrationChanged() {
            root.updateCaptureLease();
        }
    }

    Connections {
        target: GlobalStates

        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.releaseCaptureNow();
            else
                root.updateCaptureLease();
        }
    }

    Connections {
        target: root.dockContent

        function onDraggingChanged() {
            if (root.dockContent?.dragging)
                root.releaseCaptureNow();
            else
                root.updateCaptureLease();
        }
    }

    Connections {
        target: root.displayedToplevel

        function onClosed() {
            if (root.displayedToplevel === root.pendingToplevel)
                root.pendingToplevel = null;
            root.beginSelectionTransition(root.selectedToplevel);
        }
    }

    Loader {
        id: pickerLoader
        active: root.pickerOpen
        sourceComponent: Component {
            DockLivePreviewPicker {
                anchorItem: root
                onDismissed: root.pickerOpen = false
            }
        }
    }

    // The preview is the entire widget surface. There is no card background
    // or metadata column: only the rounded screencopy and a small app mark.
    ClippingRectangle {
        id: horizontalSurface
        visible: !root.isVertical
        anchors.fill: parent
        anchors.leftMargin: root.dotMargin
        anchors.rightMargin: root.dotMargin
        anchors.topMargin: root.dotMarginV
        anchors.bottomMargin: root.dotMarginV
        radius: root.widgetRadius
        antialiasing: true
        color: "transparent"

        Item {
            id: captureContent
            anchors.fill: parent
            visible: root.captureActive
            opacity: root.captureReady ? root.previewOpacity : 0.0

            ScreencopyView {
                id: screencopyView
                anchors.fill: parent
                scale: root.previewZoom
                transformOrigin: Item.Center
                captureSource: root.captureActive ? root.displayedToplevel : null
                live: true
                paintCursor: Config.options?.dock?.livePreviewPaintCursor ?? false
                constraintSize: Qt.size(
                    Math.max(1, Math.round(horizontalSurface.width * root.captureResolutionScale)),
                    Math.max(1, Math.round(horizontalSurface.height * root.captureResolutionScale))
                )

                onHasContentChanged: {
                    if (!hasContent || root.transitionPhase !== "waitingForFrame")
                        return;
                    root.transitionPhase = "enteringNew";
                    previewEnterAnimation.restart();
                }

                onStopped: {
                    root.captureUnavailable = true;
                    root.previewOpacity = 0.0;
                }
            }
        }

        NumberAnimation {
            id: previewEnterAnimation
            target: root
            property: "previewOpacity"
            from: 0.0
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            onFinished: {
                if (root.transitionPhase === "enteringNew")
                    root.transitionPhase = "stable";
            }
        }

        RippleButton {
            id: collapseButton
            visible: root.hovered
            enabled: visible
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: root.overlayInset
            anchors.rightMargin: root.overlayInset
            width: Math.min(root.buttonSize * 0.34, parent.height * 0.72)
            height: width
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "keyboard_arrow_down"
                iconSize: Math.max(Appearance.font.pixelSize.smallest, parent.height * 0.68)
                color: Appearance.colors.colOnLayer1
            }
            opacity: root.hovered ? 1.0 : 0.0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            onClicked: root.openPicker()
            z: 3
        }

        DockIcon {
            visible: root.hasSelectedApp
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.overlayInset
            anchors.bottomMargin: root.overlayInset
            width: Math.min(root.iconSize * 0.58, root.height * 0.46)
            height: width
            appId: root.appId
            desktopEntry: root.desktopEntry
            isRunning: root.selectedToplevel !== null
            z: 2
        }

        MaterialSymbol {
            visible: !root.hasSelectedApp
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: root.overlayInset
            anchors.bottomMargin: root.overlayInset
            text: "live_tv"
            iconSize: Math.min(root.iconSize * 0.58, root.height * 0.46)
            color: Appearance.colors.colOnLayer1
            z: 2
        }

        MouseArea {
            anchors.fill: parent
            z: 1
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton)
                    root.openPicker();
                else
                    root.activateSelection();
            }
        }
    }

    // Vertical Dock keeps one compact app mark; capture is intentionally
    // disabled there because the horizontal preview has no readable width.
    Item {
        visible: root.isVertical
        anchors.fill: parent

        DockIcon {
            visible: root.hasSelectedApp
            anchors.centerIn: parent
            width: root.iconSize
            height: width
            appId: root.appId
            desktopEntry: root.desktopEntry
            isRunning: root.selectedToplevel !== null
        }

        MaterialSymbol {
            visible: !root.hasSelectedApp
            anchors.centerIn: parent
            text: "live_tv"
            iconSize: root.iconSize
            color: Appearance.colors.colOnLayer1
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                if (event.button === Qt.RightButton || !root.selectedToplevel)
                    root.openPicker();
                else
                    root.activateSelection();
            }
        }
    }
}
