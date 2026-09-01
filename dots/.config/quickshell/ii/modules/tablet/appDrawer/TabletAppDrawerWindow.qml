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
 * The drawer uses a translucent colour wash rather than a snapshot. Unlike the shade, it
 * is not dragged frame by frame, so keeping the live application visible under a themed
 * scrim is both clearer and considerably cheaper than a continuous screencopy blur.
 */
PanelWindow {
    id: root

    required property Component contentComponent

    /// Forwarded from the drawer's content; see TabletAppDrawer.
    signal appHeld(string appId)

    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool wantOpen: GlobalStates.appDrawerOpen
        && (GlobalStates.activeAppDrawerMonitor === "" || GlobalStates.activeAppDrawerMonitor === root.screenName)

    /// This screen is the one the drawer belongs to. The controller tracks a single drag,
    /// so only the screen it started on may show progress.
    readonly property bool isTargetScreen: TabletAppDrawerGestureController.activeScreenName === ""
        || TabletAppDrawerGestureController.activeScreenName === root.screenName

    // 0 closed, 1 open. Everything visual reads this so the whole surface animates as one —
    // and the dock reads the same controller, so the two move as one sheet instead of each
    // animating its own copy of the same boolean and drifting apart. That drift is why the
    // dock used to be gone before the drawer was anywhere near the top.
    //
    // No Behavior here: while a finger is on the screen the value IS the finger's position,
    // and easing it would add lag to a direct manipulation. The controller runs its own
    // settle animation on release.
    readonly property real openProgress: root.isTargetScreen
        ? TabletAppDrawerGestureController.progress : 0

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
        // Follows the drag, not the settled flag: a sheet being pulled up has to accept the
        // finger that is pulling it.
        intersection: root.openProgress > 0.001 ? Intersection.Combine : Intersection.Subtract
    }

    // Keep the layer mapped while idle. A layer surface that is first mapped in the same
    // turn as its progress changes gives the compositor only the settled buffer, so the
    // sheet appears to pop in. Its closed mask is empty, therefore this transparent layer
    // never takes pointer input from the application below.
    visible: !GlobalStates.screenLocked

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
        // Never make this opaque: the current app remains part of the transition, just as it
        // does below Android's app drawer.
        opacity: root.openProgress * 0.72

        MouseArea {
            anchors.fill: parent
            // Tapping the backdrop closes, the way tapping outside any Android sheet does.
            enabled: root.wantOpen
            onClicked: root.dismiss()
        }
    }

    // A viewport makes the drawer a sheet that rises from the bottom. The progress is also
    // the clock for the wash above and the stagger inside the content, so the transition
    // cannot split into independent, visibly out-of-sync animations.
    Item {
        id: drawerViewport
        anchors.fill: parent
        clip: true

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.visible
            sourceComponent: root.contentComponent
            transform: Translate {
                y: (1 - root.openProgress) * root.height
            }

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
    }

    // The field is focused only once the drawer has settled, for the same reason the
    // surface takes keyboard focus only then.
    onOpenProgressChanged: {
        if (root.openProgress > 0.99)
            contentLoader.item?.focusSearch();
    }
}
