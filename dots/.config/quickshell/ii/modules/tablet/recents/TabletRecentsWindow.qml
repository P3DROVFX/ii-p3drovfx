import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common

/**
 * The full-screen surface Recents is drawn on, one per monitor.
 *
 * Behind the cards is the wallpaper, blurred — not a photograph of the screen. A blurred
 * screencopy put the app you were in behind its own card, so Recents opened onto two of
 * the same window, and closing faded that photograph out on top of the live app, which
 * read as a second surface closing underneath. Android shows the home wallpaper here, and
 * so does this.
 *
 * The app you were in does not fade out either: it shrinks into its card (the "hero"), and
 * grows back out of a card into its window when one is opened or Recents is dismissed.
 *
 * With `appearance.transparency` off the backdrop is the solid surface colour, which is
 * what that setting means everywhere else.
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
        // Back to the app you came from: it grows out of its card again.
        root.armCloseHero(root.currentToplevel());
        GlobalStates.recentsOpen = false;
    }

    function dismissThen(action) {
        root.pendingAction = action;
        GlobalStates.recentsOpen = false;
    }

    onVisibleChanged: {
        // Registered while this surface is on screen, not while it is "open": it keeps
        // painting for the length of its close, and that is exactly the window in which
        // another surface must not photograph it.
        GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.visible);
        if (!root.visible)
            root.heroToplevel = null;
        if (root.visible || !root.pendingAction)
            return;
        const action = root.pendingAction;
        root.pendingAction = null;
        action();
    }

    readonly property string overlayName: "recents"

    Component.onCompleted: GlobalStates.setTabletOverlayOnScreen(root.overlayName, root.visible)

    onOpenProgressChanged: {
        if (root.openProgress > 0.99)
            contentLoader.item?.forceActiveFocus();
    }

    // ── Hero ────────────────────────────────────────────────────────────────
    /**
     * The window that is turning into a card, or a card turning back into its window.
     *
     * One picture travels between the window's real rectangle (openProgress 0) and its card
     * (openProgress 1), on the same progress as everything else, so opening and closing are
     * one motion played in either direction. Its card stays hidden meanwhile. Armed on open
     * with the window on screen, on dismiss with that same window, and on a card tap with
     * that card; a close from anywhere else (Home, another surface) just fades.
     */
    property var heroToplevel: null
    property rect heroWindowRect: Qt.rect(0, 0, 0, 0)
    property rect heroCardRect: Qt.rect(0, 0, 0, 0)
    readonly property bool heroInFlight: root.heroToplevel !== null
        && root.visible && root.openProgress < 0.999
    /// The hero has a picture and is covering the window it came from.
    readonly property bool heroCovering: root.heroInFlight && heroCapture.hasContent

    function addressOf(toplevel) {
        const raw = String(toplevel?.HyprlandToplevel?.address ?? "").trim();
        if (raw.length === 0)
            return "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    function monitorData() {
        return (HyprlandData.monitors ?? []).find(m => m?.name === root.screenName) ?? null;
    }

    /// The window on screen right now: the most recently focused one on this monitor's
    /// active workspace, or null on an empty (home) workspace.
    function currentToplevel() {
        const monitor = root.monitorData();
        const workspaceId = monitor?.activeWorkspace?.id ?? -1;
        let best = null;
        for (const client of (HyprlandData.windowList ?? [])) {
            if ((client?.workspace?.id ?? -2) !== workspaceId || client.hidden === true)
                continue;
            if (!best || Number(client.focusHistoryID ?? 9999) < Number(best.focusHistoryID ?? 9999))
                best = client;
        }
        if (!best)
            return null;
        const address = String(best.address ?? "");
        return (ToplevelManager.toplevels?.values ?? []).find(t => root.addressOf(t) === address) ?? null;
    }

    /// Where `toplevel` sits on this screen, in surface coordinates.
    function windowRectOf(toplevel) {
        const address = root.addressOf(toplevel);
        const client = (HyprlandData.windowList ?? []).find(c => String(c?.address ?? "") === address);
        const monitor = root.monitorData();
        if (!client || !monitor)
            return null;
        const at = client.at ?? [0, 0];
        const size = client.size ?? [0, 0];
        if (size[0] <= 0 || size[1] <= 0)
            return null;
        return Qt.rect(at[0] - monitor.x, at[1] - monitor.y, size[0], size[1]);
    }

    function armHero(toplevel) {
        const rect = toplevel ? root.windowRectOf(toplevel) : null;
        if (!rect || (Config.options?.tablet?.recents?.layout ?? "list") === "grid") {
            root.heroToplevel = null;
            return;
        }
        // Same window as the open: keep the picture it already has. A new view would leave
        // the card hidden with nothing in its place until the capture arrives.
        if (toplevel !== root.heroToplevel)
            root.heroToplevel = null;
        root.heroWindowRect = rect;
        // Until its card is laid out the hero stays where the window is.
        root.heroCardRect = rect;
        root.heroToplevel = toplevel;
        root.refreshHeroCard();
    }

    /// A close that should play the hero, set just before the close itself.
    property bool closeHeroArmed: false

    function armCloseHero(toplevel) {
        root.armHero(toplevel);
        root.closeHeroArmed = root.heroToplevel !== null;
    }

    function refreshHeroCard() {
        const card = contentLoader.item?.cardFor(root.heroToplevel) ?? null;
        const snapshot = card?.snapshotItem ?? null;
        if (!snapshot || snapshot.width <= 0)
            return;
        const p = snapshot.mapToItem(recentsViewport, 0, 0);
        root.heroCardRect = Qt.rect(p.x, p.y, snapshot.width, snapshot.height);
    }

    onWantOpenChanged: {
        if (root.wantOpen) {
            GlobalFocusGrab.addDismissable(root);
            root.armHero(root.currentToplevel());
        } else {
            GlobalFocusGrab.removeDismissable(root);
            // Closed from somewhere else — Home, another surface: there is no card being
            // opened, so the window from the open must not fly back.
            if (!root.closeHeroArmed)
                root.heroToplevel = null;
            root.closeHeroArmed = false;
        }
    }

    // The card moves while it arrives (the row slides in, the list settles), so the target
    // is re-read every frame of the flight rather than once.
    FrameAnimation {
        running: root.heroInFlight
        onTriggered: root.refreshHeroCard()
    }

    // ── Backdrop ────────────────────────────────────────────────────────────
    readonly property string wallpaperPath: Config.options?.background?.wallpaperPath ?? ""

    component BackdropPicture: Item {
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0Base
        }

        // Quarter resolution: it is about to be blurred, and a full-size decode of the
        // wallpaper costs memory for detail nobody can see.
        Image {
            anchors.fill: parent
            visible: root.useBlur && status === Image.Ready
            source: root.useBlur ? root.wallpaperPath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(Math.max(1, Math.round(root.width / 4)), Math.max(1, Math.round(root.height / 4)))
            layer.enabled: visible
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 32
                blur: 1
            }
        }

        // The wash. The opaque base, not colLayer0: colLayer0 already carries the user's
        // background transparency, so an "88% wash" made of it landed nearer 55%.
        Rectangle {
            anchors.fill: parent
            visible: root.useBlur
            color: Appearance.colors.colLayer0Base
            opacity: root.backdropOpacity
        }
    }

    BackdropPicture {
        anchors.fill: parent
        opacity: root.openProgress

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }
    }

    // While the hero stands where the window is, the window's own rectangle is backdrop
    // already, at full strength. Otherwise the live app shows through the half-faded
    // backdrop around a hero that is smaller than it — the duplicate this replaced.
    Item {
        x: root.heroWindowRect.x
        y: root.heroWindowRect.y
        width: root.heroWindowRect.width
        height: root.heroWindowRect.height
        clip: true
        visible: root.heroCovering

        BackdropPicture {
            x: -parent.x
            y: -parent.y
            width: root.width
            height: root.height
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
                contentLoader.item.heroRequested.connect(root.armCloseHero);
                contentLoader.item.heroToplevel = Qt.binding(() => root.heroInFlight ? root.heroToplevel : null);
            }
        }
    }

    Item {
        id: hero
        z: 2
        visible: root.heroInFlight
        readonly property real t: root.openProgress
        x: root.heroWindowRect.x + (root.heroCardRect.x - root.heroWindowRect.x) * hero.t
        y: root.heroWindowRect.y + (root.heroCardRect.y - root.heroWindowRect.y) * hero.t
        width: root.heroWindowRect.width + (root.heroCardRect.width - root.heroWindowRect.width) * hero.t
        height: root.heroWindowRect.height + (root.heroCardRect.height - root.heroWindowRect.height) * hero.t

        ClippingRectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large * hero.t
            color: "transparent"

            // A fresh view per flight: an existing ScreencopyView keeps its last frame and
            // does not reliably replace it, so a reused one would fly an old picture.
            Loader {
                id: heroCapture
                anchors.fill: parent
                active: root.heroToplevel !== null
                readonly property bool hasContent: heroCapture.item?.hasContent ?? false

                sourceComponent: ScreencopyView {
                    captureSource: root.heroToplevel
                    live: false
                }
            }
        }
    }

}
