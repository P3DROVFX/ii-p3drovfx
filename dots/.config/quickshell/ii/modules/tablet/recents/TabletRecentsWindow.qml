import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * The full-screen surface Recents is drawn on, one per monitor.
 *
 * The backdrop blurs a frozen screencopy rather than letting Hyprland blur the layer, for
 * the same reason the app drawer does: a layer rule can only switch blur on or off, its
 * strength is the surface's own alpha, and the shell's `ignore_alpha` rule turns even that
 * into a threshold — so compositor blur arrives as a step part-way through the animation
 * instead of ramping with it. Blurring a snapshot here is the only way the strength can
 * follow the transition.
 *
 * With `appearance.transparency` off there is no capture and no blur: Recents sits on a
 * solid surface colour, which is what that setting means everywhere else.
 */
PanelWindow {
    id: root

    required property Component contentComponent

    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool wantOpen: GlobalStates.recentsOpen
        && (GlobalStates.activeRecentsMonitor === "" || GlobalStates.activeRecentsMonitor === root.screenName)

    property real openProgress: root.wantOpen ? 1 : 0

    readonly property bool useBlur: Config.options?.appearance?.transparency?.enable ?? false
    /// How far the wash goes. Recents is a place you are *in*, not a sheet over the app you
    /// were using, so it sits further towards opaque than the drawer's 0.72 — but not at 1,
    /// or the windows you are choosing between stop being part of the transition.
    readonly property real backdropOpacity: Math.max(0.4, Math.min(1,
        (Config.options?.tablet?.recents?.backdropOpacity ?? 88) / 100))

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
        if (root.wantOpen) {
            GlobalFocusGrab.addDismissable(root);
        } else {
            GlobalFocusGrab.removeDismissable(root);
        }
    }

    Component.onDestruction: {
        GlobalFocusGrab.removeDismissable(root);
        GlobalStates.setTabletOverlayOnScreen(root.overlayName, false);
    }

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
        // Registered while this surface is on screen, not while it is "open": it keeps
        // painting for the length of its close, and that is exactly the window in which
        // another surface must not photograph it.
        GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.visible);
        if (root.visible || !root.pendingAction)
            return;
        const action = root.pendingAction;
        root.pendingAction = null;
        action();
    }

    // ── Backdrop capture ────────────────────────────────────────────────────
    /**
     * The backdrop is rebuilt for every open, not refreshed.
     *
     * A ScreencopyView keeps the last frame it captured, and asking an existing one for
     * another frame does not reliably replace it — measured: with one view kept around, the
     * drawer opened onto the same picture whichever workspace it was opened from. A view
     * created when the surface starts opening has nothing to keep, so `hasContent` means
     * what it says: a picture of *this* open has arrived.
     *
     * The Loader also waits for any other full-screen tablet overlay to leave the screen —
     * a plain binding, so it activates the moment the other one unmaps. Closing is a
     * transition, so "the other one is closed" and "the other one is gone" are not the same
     * instant, and capturing between them is what froze one surface into the other.
     */
    readonly property string overlayName: "recents"

    readonly property bool wantsBackdrop: root.useBlur
        && (root.wantOpen || root.openProgress > 0.001)

    Component.onCompleted: GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.visible)

    onOpenProgressChanged: {
        if (root.openProgress > 0.99)
            contentLoader.item?.forceActiveFocus();
    }

    Item {
        id: backdrop
        anchors.fill: parent
        visible: root.useBlur && root.openProgress > 0.001 && (backdropLoader.item?.hasContent ?? false)
        layer.enabled: backdrop.visible
        layer.effect: MultiEffect {
            // Auto padding grows the effect item past its source and shifts the whole
            // capture, which shows up as a sharp band along one edge.
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blurMultiplier: 1.2
            // Reaches full strength slightly before the cards land, so the last few frames
            // are Recents settling rather than the background still resolving.
            blur: Math.min(1.0, root.openProgress * 1.15)
        }

        Loader {
            id: backdropLoader
            anchors.fill: parent
            active: root.wantsBackdrop && !GlobalStates.otherTabletOverlayOnScreen(root.overlayName)

            sourceComponent: ScreencopyView {
                anchors.fill: parent
                captureSource: root.screen
                // A live capture would see this surface's own blurred output and smear.
                live: false
                // Taken the moment the view exists, which is the moment Recents starts
                // opening — before it has painted anything of its own.
                Component.onCompleted: captureFrame()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        // The opaque base, not colLayer0. colLayer0 already carries the user's background
        // transparency, so a "88% wash" made of it was landing nearer 55% and the desktop
        // read straight through the surface. Strength belongs to one number, and that number
        // is the preference.
        color: Appearance.colors.colLayer0Base
        opacity: root.openProgress * (root.useBlur ? root.backdropOpacity : 1.0)

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }
    }

    /**
     * A viewport, so the cards arrive by sliding rather than by appearing.
     *
     * The travel is a fraction of the height, not all of it: Recents is not a bottom sheet
     * being pulled up, it is the app you were in stepping back into a row. A full-height
     * slide reads as the wrong surface. The same progress drives the blur and the wash
     * above, so the three cannot split into independent, visibly out-of-sync animations.
     */
    Item {
        id: recentsViewport
        anchors.fill: parent
        z: 1
        clip: true

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.visible
            sourceComponent: root.contentComponent
            transform: Translate {
                y: (1 - root.openProgress) * root.height * 0.18
            }

            onLoaded: {
                if (!contentLoader.item)
                    return;
                contentLoader.item.revealProgress = Qt.binding(() => root.openProgress);
                contentLoader.item.dismissRequested.connect(root.dismiss);
                contentLoader.item.deferredRequested.connect(root.dismissThen);
            }
        }
    }

}
