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
 * The backdrop blurs a frozen screencopy rather than letting Hyprland blur the layer. A
 * layer rule can only switch blur on or off; its strength is the surface's own alpha, and
 * the shell's `ignore_alpha` rule turns even that into a threshold. So compositor blur
 * arrived as a step part-way through the animation instead of ramping with it. Blurring a
 * snapshot here is the only way the strength can follow the finger, and it is the same
 * thing TabletShadeWindow does for the same reason.
 *
 * With `appearance.transparency` off there is no capture and no blur at all: the drawer
 * sits on a solid surface colour, which is what that setting means everywhere else.
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

    readonly property bool useBlur: Config.options?.appearance?.transparency?.enable ?? false

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
        // Open, or being dragged open — but deliberately NOT while closing. A sheet being
        // pulled up must accept the finger pulling it; a sheet on its way out must hand
        // input straight back, or it stays the topmost target after the dock button has
        // reappeared and swallows the next tap on Apps.
        intersection: (root.wantOpen || TabletAppDrawerGestureController.tracking)
            ? Intersection.Combine : Intersection.Subtract
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

    // The snapshot has to be taken while this surface is still painting nothing, or the
    // capture contains the drawer's own backdrop and the blur compounds every frame.
    property bool _backdropArmed: false

    onOpenProgressChanged: {
        if (root.openProgress > 0.001 && !root._backdropArmed) {
            root._backdropArmed = true;
            if (root.useBlur)
                backdropCapture.captureFrame();
        } else if (root.openProgress <= 0.001) {
            root._backdropArmed = false;
        }
        // The field is focused only once the drawer has settled, for the same reason the
        // surface takes keyboard focus only then.
        if (root.openProgress > 0.99)
            contentLoader.item?.focusSearch();
    }

    Item {
        id: backdrop
        anchors.fill: parent
        visible: root.useBlur && root.openProgress > 0.001 && backdropCapture.hasContent
        layer.enabled: backdrop.visible
        layer.effect: MultiEffect {
            // Auto padding grows the effect item past its source and shifts the whole
            // capture, which shows up as a sharp band along one edge.
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blurMultiplier: 1.2
            // Reaches full strength slightly before the sheet lands, so the last few
            // frames are the drawer settling rather than the background still resolving.
            blur: Math.min(1.0, root.openProgress * 1.15)
        }

        ScreencopyView {
            id: backdropCapture
            anchors.fill: parent
            captureSource: root.useBlur ? root.screen : null
            // A live capture would see this surface's own blurred output and smear.
            live: false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        // Blurred: a wash over the snapshot, never opaque — the current app stays part of
        // the transition, just as it does below Android's app drawer. Unblurred: the same
        // colour, but solid by the time the sheet lands, because that is what turning
        // transparency off asks for.
        opacity: root.useBlur ? root.openProgress * 0.72 : root.openProgress

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
}
