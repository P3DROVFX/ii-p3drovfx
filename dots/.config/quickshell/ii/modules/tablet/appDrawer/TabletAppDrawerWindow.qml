import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common

/**
 * The full-screen surface the app drawer is drawn on, one per monitor.
 *
 * It scrims rather than snapshots. The shade freezes and blurs a screencopy because its
 * blur has to ramp with the finger, frame by frame, while it is dragged; the drawer either
 * is open or is not, so a plain animated scrim gets the same read for none of the cost of a
 * continuous capture.
 */
PanelWindow {
    id: root

    required property Component contentComponent

    /// Forwarded from the drawer's content; see TabletAppDrawer.
    signal appHeld(string appId)

    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool wantOpen: GlobalStates.appDrawerOpen
        && (GlobalStates.activeAppDrawerMonitor === "" || GlobalStates.activeAppDrawerMonitor === root.screenName)

    // 0 closed, 1 open. Everything visual reads this so the whole surface animates as one.
    //
    // A binding, not an assignment from onWantOpenChanged: a window constructed while the
    // drawer is already open — which is what a hot reload does — gets no change signal, so
    // the imperative version left the surface mapped and drawing nothing.
    property real openProgress: root.wantOpen ? 1 : 0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell:tabletAppDrawer"
    WlrLayershell.layer: WlrLayer.Overlay
    // Typing has to reach the search field the moment the drawer is up, but taking focus
    // while it is still animating steals keys from whatever the user was doing.
    WlrLayershell.keyboardFocus: root.openProgress > 0.99 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Keep the close animation mapped, but give input back to the dock immediately. Without
    // this, the transparent, closing overlay was still the topmost touch target while the
    // dock button had already reappeared, so a second tap on Apps was swallowed.
    Item {
        id: inputRegion
        anchors.fill: parent
    }
    mask: Region {
        item: inputRegion
        intersection: root.wantOpen ? Intersection.Combine : Intersection.Subtract
    }

    // Unmapped when fully closed: an always-mapped full-screen Overlay surface would sit
    // over every window for nothing. The shade stays mapped only because its top edge must
    // remain grabbable at all times; the drawer has no such strip.
    visible: (root.wantOpen || root.openProgress > 0.001) && !GlobalStates.screenLocked

    Behavior on openProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    onWantOpenChanged: {
        if (root.wantOpen) {
            contentLoader.item?.reset();
            GlobalFocusGrab.addDismissable(root);
        } else {
            GlobalFocusGrab.removeDismissable(root);
        }
    }

    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    /// GlobalFocusGrab dismisses by calling this on the registered window.
    function dismiss() {
        GlobalStates.appDrawerOpen = false;
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: root.openProgress * (Config.options?.appearance?.transparency?.enable ? 0.86 : 1.0)

        MouseArea {
            anchors.fill: parent
            // Tapping the backdrop closes, the way tapping outside any Android sheet does.
            enabled: root.wantOpen
            onClicked: root.dismiss()
        }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.visible
        sourceComponent: root.contentComponent

        onLoaded: {
            if (!contentLoader.item)
                return;
            contentLoader.item.revealProgress = Qt.binding(() => root.openProgress);
            contentLoader.item.dismissRequested.connect(root.dismiss);
            contentLoader.item.appHeld.connect(root.appHeld);
            if (root.wantOpen)
                contentLoader.item.reset();
        }
    }

    // The field is focused only once the drawer has settled, for the same reason the
    // surface takes keyboard focus only then.
    onOpenProgressChanged: {
        if (root.openProgress > 0.99)
            contentLoader.item?.focusSearch();
    }
}
