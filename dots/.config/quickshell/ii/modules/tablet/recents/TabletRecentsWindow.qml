import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/// Full-screen surface the recents carousel is drawn on, one per monitor.
/// Same shape as the app drawer's window; see TabletAppDrawerWindow for the reasoning
/// behind the scrim, the binding-not-assignment on openProgress and the focus timing.
PanelWindow {
    id: root

    required property Component contentComponent

    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool wantOpen: GlobalStates.recentsOpen
        && (GlobalStates.activeRecentsMonitor === "" || GlobalStates.activeRecentsMonitor === root.screenName)

    property real openProgress: root.wantOpen ? 1 : 0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:tabletRecents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.openProgress > 0.99 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: (root.wantOpen || root.openProgress > 0.001) && !GlobalStates.screenLocked

    Behavior on openProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    onWantOpenChanged: {
        if (root.wantOpen)
            GlobalFocusGrab.addDismissable(root);
        else
            GlobalFocusGrab.removeDismissable(root);
    }

    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    /// Something to do once this surface is completely gone.
    ///
    /// Closing an overlay that held keyboard focus makes Hyprland refocus whatever had it
    /// before. That undoes anything recents just did about focus — a workspace switch is
    /// pulled straight back, an activated window loses focus again — and it does so
    /// silently, with nothing in the log to say so. Anything that changes what is focused
    /// therefore has to wait for the unmap. Running it before the close, or on the next
    /// tick after it, is not late enough; both were tried.
    property var pendingAction: null

    function dismiss() {
        GlobalStates.recentsOpen = false;
    }

    function dismissThen(action) {
        root.pendingAction = action;
        root.dismiss();
    }

    onVisibleChanged: {
        if (root.visible || !root.pendingAction)
            return;
        const action = root.pendingAction;
        root.pendingAction = null;
        action();
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: root.openProgress * (Config.options?.appearance?.transparency?.enable ? 0.9 : 1.0)

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        z: 1
        active: root.visible
        sourceComponent: root.contentComponent

        onLoaded: {
            if (!contentLoader.item)
                return;
            contentLoader.item.revealProgress = Qt.binding(() => root.openProgress);
            contentLoader.item.dismissRequested.connect(root.dismiss);
            contentLoader.item.deferredRequested.connect(root.dismissThen);
        }
    }

    onOpenProgressChanged: {
        if (root.openProgress > 0.99)
            contentLoader.item?.forceActiveFocus();
    }
}
