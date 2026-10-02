pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Alt+Tab's peek: hold still on one window and the screen dims around a live picture of it,
 * drawn exactly where the window is - on its own monitor, at its own size, even when it
 * lives on another workspace. Nothing moves in the compositor while peeking, so Escape
 * leaves everything where it was; a release switches with animations off (WindowSwitcher)
 * underneath the peek, which holds until the window has focus and then fades away over the
 * real window in the same place.
 *
 * The picture is captured ahead: once the switcher is up and the selection holds still for a
 * moment, the (invisible) peek already streams it, so the peek opens on a picture instead of
 * an empty backdrop - a window on another workspace takes a good half second to send its first
 * frame. The backdrop waits for the picture either way.
 *
 * Every window gets a capture of its own. Pointing one capture at another window kept the old
 * window's frames in its buffers, and the screen flickered between the two every frame.
 *
 * The window is drawn the way Hyprland draws it: at its own opacity (rules, override and
 * decoration.active_opacity), over its workspace's background - the wallpaper as the shell
 * draws it behind windows, over the whole screen. A dim over the current screen let the
 * window you were leaving show through a translucent one, and around it.
 *
 * Its own click-through layer, ordered under the island and the panel (rules.lua), so the
 * switcher stays readable above it.
 */
Scope {
    id: root

    readonly property bool wanted: WindowSwitcher.peeking && WindowSwitcher.active && WindowSwitcher.peekEntry !== null
    /// The switcher is up and could peek: capture ahead.
    readonly property bool preparing: WindowSwitcher.active && WindowSwitcher.shown && WindowSwitcher.peekDelayMs > 0
    /// The selection once it has held still for a moment, so a burst of Tabs captures nothing.
    property var preparedEntry: null
    readonly property var entry: WindowSwitcher.peeking ? WindowSwitcher.peekEntry : root.preparedEntry
    /// Kept for the fade-out after the switcher itself has closed.
    property bool lingering: false
    /**
     * After a release, fully up until the window it shows has focus underneath: fading over the
     * screen being left showed that screen through the peek, and the switch landing mid-fade.
     */
    property bool holding: false
    readonly property bool showing: root.wanted || root.holding

    readonly property string wallpaperPath: Config.options?.background?.wallpaperPath ?? ""
    readonly property bool wallpaperIsVideo: /\.(mp4|webm|mkv|avi|mov)$/i.test(root.wallpaperPath)
    readonly property string wallpaperSource: root.wallpaperPath === "" ? ""
        : Qt.resolvedUrl(root.wallpaperIsVideo ? (Config.options?.background?.thumbnailPath ?? "") : root.wallpaperPath)
    /// The background blurs the wallpaper behind open windows, except for moving wallpapers.
    readonly property bool wallpaperMoving: root.wallpaperIsVideo || (Config.options?.background?.useWallpaperEngine ?? false)
    readonly property bool wallpaperBlurred: (Config.options?.background?.blurWhenWindowsOpen ?? false) && !root.wallpaperMoving
    /// The background's zoom (BackgroundRoot.recalcWallpaperScale): the workspace zoom, and 3 %
    /// more whenever a blur is on, which pushes the blur's dark edges off the screen.
    readonly property real wallpaperScale: (root.wallpaperMoving ? 1 : (Config.options?.background?.parallax?.workspaceZoom ?? 1))
        * ((Config.options?.background?.blurWhenWindowsOpen || Config.options?.lock?.blur?.enable) ? 1.03 : 1)

    onWantedChanged: {
        if (root.wanted) {
            root.holding = false;
        } else if (peekLoader.item?.open && WindowSwitcher.landingAddress !== ""
                && WindowSwitcher.currentAddress !== WindowSwitcher.landingAddress) {
            root.holding = true;
            holdTimeout.restart();
        }
    }
    onShowingChanged: {
        if (root.showing) {
            lingerTimer.stop();
            root.lingering = false;
        } else if (peekLoader.item) {
            root.lingering = true;
            lingerTimer.restart();
        }
    }

    Timer {
        id: lingerTimer
        interval: Appearance.animation.elementMoveFast.duration + 120
        onTriggered: root.lingering = false
    }

    // Hyprland names the new focus before it draws it: a couple of frames more, then let go.
    Timer {
        id: landedTimer
        interval: 50
        onTriggered: root.holding = false
    }
    // A switch that never reports back (refused, or the window went away) lets go anyway.
    Timer {
        id: holdTimeout
        interval: 400
        onTriggered: root.holding = false
    }

    function prepare(): void {
        if (root.preparing && !WindowSwitcher.peeking && WindowSwitcher.selectedEntry)
            prepareTimer.restart();
        else
            prepareTimer.stop();
    }

    Connections {
        target: WindowSwitcher
        function onSelectedAddressChanged() {
            root.prepare();
        }
        function onActiveChanged() {
            if (WindowSwitcher.active) {
                root.alphas = ({});
                root.holding = false;
            } else
                root.preparedEntry = null;
        }
        // From here on the peek shows what is peeked at. Kept, the window captured ahead came
        // back for an instant at the release (peeking ends a step before the switcher does),
        // and the peek faded out on it: the window you started on, not the one you chose.
        function onPeekingChanged() {
            if (WindowSwitcher.peeking)
                root.preparedEntry = null;
        }
        function onCurrentAddressChanged() {
            if (root.holding && WindowSwitcher.currentAddress === WindowSwitcher.landingAddress)
                landedTimer.restart();
        }
    }
    onPreparingChanged: root.prepare()

    Timer {
        id: prepareTimer
        interval: 100
        onTriggered: {
            if (root.preparing && !WindowSwitcher.peeking)
                root.preparedEntry = WindowSwitcher.selectedEntry;
        }
    }

    // ------------------------------------------------------------------ opacity

    /// Address -> { active, fullscreen, border, borderColor, rounding }: how Hyprland draws the
    /// window once focused - its alpha, and the border around it.
    property var alphas: ({})
    property var alphaQueue: []

    function alphaFor(entry: var): real {
        const known = entry ? root.alphas[entry.address] : undefined;
        if (!known)
            return 1;
        return entry.fullscreen ? known.fullscreen : known.active;
    }

    function requestAlpha(address: string): void {
        if (address === "" || root.alphas[address] !== undefined || root.alphaQueue.includes(address)
                || alphaProc.address === address)
            return;
        root.alphaQueue = root.alphaQueue.concat([address]);
        root.runAlpha();
    }

    function runAlpha(): void {
        if (alphaProc.running || root.alphaQueue.length === 0)
            return;
        alphaProc.address = root.alphaQueue[0];
        root.alphaQueue = root.alphaQueue.slice(1);
        alphaProc.running = true;
    }

    function storeAlpha(address: string, text: string): void {
        const lines = text.split("\n").map(line => line.trim());
        const option = line => Number((/"float":\s*([0-9.]+)/.exec(line) ?? [])[1] ?? 1);
        const rule = value => {
            const n = Number(value);
            return isFinite(n) && n > 0 ? n : 1;
        };
        const active = rule(lines[0]) * (lines[1] === "true" ? 1 : option(lines[4]));
        const fullscreen = rule(lines[2]) * (lines[3] === "true" ? 1 : option(lines[5]));
        // A gradient prints as AARRGGBB stops and an angle; the first stop stands for it.
        const stop = (/^([0-9a-fA-F]{8})\b/.exec(lines[7] ?? "") ?? [])[1];
        const next = Object.assign({}, root.alphas);
        next[address] = {
            active: Math.max(0, Math.min(1, active)),
            fullscreen: Math.max(0, Math.min(1, fullscreen)),
            border: Math.max(0, Number(lines[6]) || 0),
            borderColor: stop ? `#${stop}` : "transparent",
            rounding: Math.max(0, Number(lines[8]) || 0)
        };
        root.alphas = next;
        if (lines[9] === "false" && /"bool":\s*true/.test(lines[10] ?? ""))
            root.undim(address);
    }

    /**
     * decoration.dim_inactive lands in the capture: an unfocused window peeked a shade darker
     * than it shows once it has focus. The windows the peek captures go undimmed while it is
     * around (the ones off screen show no change), and get their own setting back after.
     */
    property var undimmed: []

    function undim(address: string): void {
        if (root.undimmed.includes(address))
            return;
        root.undimmed = root.undimmed.concat([address]);
        Quickshell.execDetached(["hyprctl", "eval", root.noDimChunk(address, "1")]);
    }

    function redim(): void {
        if (root.undimmed.length === 0)
            return;
        Quickshell.execDetached(["hyprctl", "eval", root.undimmed.map(address => root.noDimChunk(address, "unset")).join("\n")]);
        root.undimmed = [];
    }

    // A shell reload mid-peek must not leave windows undimmed for good.
    Component.onDestruction: root.redim()

    function noDimChunk(address: string, value: string): string {
        return `hl.dispatch(hl.dsp.window.set_prop({ window = "address:${address}", prop = "no_dim", value = "${value}" }))`;
    }

    /// The border Hyprland draws around the focused window, outside it: { width, color, rounding }.
    function borderFor(entry: var): var {
        const known = entry ? root.alphas[entry.address] : undefined;
        if (!known || entry.fullscreen)
            return { width: 0, color: "transparent", rounding: entry?.fullscreen ? 0 : Appearance.rounding.windowRounding };
        return { width: known.border, color: known.borderColor, rounding: known.rounding };
    }

    Process {
        id: alphaProc
        property string address: ""
        command: ["sh", "-c", 'w="address:$1"; hyprctl getprop "$w" opacity; hyprctl getprop "$w" opacity_override; '
            + 'hyprctl getprop "$w" opacity_fullscreen; hyprctl getprop "$w" opacity_fullscreen_override; '
            + 'hyprctl -j getoption decoration:active_opacity | tr -d "\\n"; echo; '
            + 'hyprctl -j getoption decoration:fullscreen_opacity | tr -d "\\n"; echo; '
            + 'hyprctl getprop "$w" border_size; hyprctl getprop "$w" active_border_color; '
            + 'hyprctl getprop "$w" rounding; hyprctl getprop "$w" no_dim; '
            + 'hyprctl -j getoption decoration:dim_inactive | tr -d "\\n"; echo', "sh", alphaProc.address]
        stdout: StdioCollector {
            onStreamFinished: root.storeAlpha(alphaProc.address, text)
        }
        onExited: {
            alphaProc.address = "";
            Qt.callLater(root.runAlpha);
        }
    }

    // ------------------------------------------------------------------ surface

    Loader {
        id: peekLoader
        active: WindowSwitcher.enabled && (root.preparing || root.showing || root.lingering)
        onActiveChanged: {
            if (!peekLoader.active)
                root.redim();
        }

        sourceComponent: PanelWindow {
            id: peekWindow

            /// The window's own monitor, so the picture lands where the window really is.
            readonly property var monitor: (HyprlandData.monitors ?? []).find(m => Number(m?.id) === Number(peekWindow.shownEntry?.monitor ?? -1))
                ?? (HyprlandData.monitors ?? []).find(m => String(m?.name ?? "") === WindowSwitcher.screenName) ?? null
            readonly property var targetScreen: Quickshell.screens.find(s => s.name === String(peekWindow.monitor?.name ?? ""))
                ?? Quickshell.screens.find(s => s.name === WindowSwitcher.screenName)
                ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            screen: peekWindow.targetScreen
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            // Not quickshell:*, which rules.lua blurs wholesale; see the peek's rules there.
            WlrLayershell.namespace: "ii-alt-tab-peek"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            // Seen, never touched: the switcher's own surfaces keep the pointer.
            mask: Region {}

            /// Set a turn after mapping, so the first frame is the closed state and the entry animates.
            property bool entered: false
            Component.onCompleted: {
                peekWindow.place(root.entry);
                Qt.callLater(() => peekWindow.entered = true);
            }

            readonly property var currentPicture: peekWindow.showA ? pictureA : pictureB
            readonly property var shownEntry: peekWindow.currentPicture.slotEntry
            /// Backdrop and picture arrive together: the peek waits for the picture's first frame
            /// and for the wallpaper (or its failing to load).
            readonly property bool open: peekWindow.entered && root.showing && peekWindow.currentPicture.ready
                && backdropImage.status !== Image.Loading
            property real reveal: peekWindow.open ? 1 : 0
            Behavior on reveal {
                NumberAnimation {
                    duration: peekWindow.open ? Appearance.animation.elementMove.duration
                        : Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: peekWindow.open ? Appearance.animationCurves.emphasizedDecel
                        : Appearance.animationCurves.standard
                }
            }

            // Two pictures trade places as the selection moves. The next one is captured in the
            // hidden slot and only fades in over the last once it has a frame.
            property var slotA: null
            property var slotB: null
            property bool showA: true
            property bool swapPending: false

            function place(entry: var): void {
                if (!entry)
                    return;
                root.requestAlpha(entry.address);
                const shown = peekWindow.showA ? peekWindow.slotA : peekWindow.slotB;
                if (!shown || shown.address === entry.address) {
                    // The first window, or the same one moved or retitled.
                    if (peekWindow.showA)
                        peekWindow.slotA = entry;
                    else
                        peekWindow.slotB = entry;
                    peekWindow.swapPending = false;
                    return;
                }
                if (peekWindow.showA)
                    peekWindow.slotB = entry;
                else
                    peekWindow.slotA = entry;
                peekWindow.swapPending = true;
                peekWindow.trySwap();
            }

            function trySwap(): void {
                if (!peekWindow.swapPending)
                    return;
                const incoming = peekWindow.showA ? pictureB : pictureA;
                // Nothing on screen yet: no need to wait for the frame to cross-fade.
                if (incoming.ready || !peekWindow.open) {
                    peekWindow.showA = !peekWindow.showA;
                    peekWindow.swapPending = false;
                }
            }

            Connections {
                target: root
                function onEntryChanged() {
                    // After the switcher closes the peek only fades out: keep what it shows.
                    if (WindowSwitcher.active)
                        peekWindow.place(root.entry);
                }
            }

            component PeekPicture: ClippingRectangle {
                id: picture
                required property var slotEntry
                required property bool current

                readonly property string slotAddress: picture.slotEntry?.address ?? ""
                /// The capture for this slot's window, recreated whenever the window changes.
                property var capture: null
                readonly property bool hasContent: picture.capture?.hasContent ?? false
                /// A window that cannot be captured still peeks, with its icon.
                property bool waited: false
                readonly property bool ready: picture.slotAddress !== "" && (picture.hasContent || picture.waited)
                readonly property real alpha: root.alphaFor(picture.slotEntry)

                onSlotAddressChanged: {
                    picture.waited = false;
                    waitTimer.restart();
                }
                onReadyChanged: peekWindow.trySwap()

                Timer {
                    id: waitTimer
                    interval: 700
                    onTriggered: picture.waited = true
                }

                readonly property real originX: Number(peekWindow.monitor?.x ?? 0)
                readonly property real originY: Number(peekWindow.monitor?.y ?? 0)
                // Kept visible at opacity 0: a live capture only advances while the item paints.
                visible: picture.slotEntry !== null
                x: (picture.slotEntry?.x ?? 0) - picture.originX
                y: (picture.slotEntry?.y ?? 0) - picture.originY
                width: picture.slotEntry?.width ?? 0
                height: picture.slotEntry?.height ?? 0
                radius: root.borderFor(picture.slotEntry).rounding
                color: picture.hasContent ? "transparent" : Appearance.colors.colLayer1
                // The incoming picture fades in on top; the outgoing one stays under it until
                // then, so the backdrop never shows through the cross-fade.
                z: picture.current ? 1 : 0
                property bool covering: false
                onCurrentChanged: {
                    if (picture.current) {
                        coverTimer.stop();
                        picture.covering = true;
                    } else {
                        coverTimer.restart();
                    }
                }
                Timer {
                    id: coverTimer
                    interval: Appearance.animation.elementMoveFast.duration
                    onTriggered: picture.covering = false
                }
                property real fade: picture.current ? 1 : 0
                Behavior on fade {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }
                opacity: picture.current ? picture.fade : (picture.covering ? 1 : 0)

                readonly property string iconPath: {
                    const _ = TaskbarApps.iconThemeRevision;
                    return Quickshell.iconPath(AppSearch.guessIcon(picture.slotEntry?.appClass ?? ""), "image-missing");
                }

                Repeater {
                    model: picture.slotAddress !== "" ? [picture.slotAddress] : []
                    delegate: ScreencopyView {
                        id: screencopy
                        anchors.fill: parent
                        captureSource: picture.slotEntry?.toplevel ?? null
                        // Until its first frame, so the hidden slot is ready when it is needed.
                        live: picture.current || !screencopy.hasContent
                        opacity: picture.alpha
                        Component.onCompleted: picture.capture = screencopy
                        Component.onDestruction: {
                            if (picture.capture === screencopy)
                                picture.capture = null;
                        }
                    }
                }

                // Until the first frame lands, and for windows that cannot be captured.
                Image {
                    anchors.centerIn: parent
                    visible: !picture.hasContent
                    source: picture.iconPath
                    width: Math.round(Math.min(128, parent.height * 0.3))
                    height: width
                    sourceSize: Qt.size(width, height)
                    asynchronous: true
                }
            }

            // The border Hyprland draws around the window, outside it and at the window's alpha.
            // A capture has none, and the real one appeared from nowhere as the peek let go.
            component PeekBorder: Rectangle {
                id: frame
                required property var picture
                readonly property var look: root.borderFor(frame.picture.slotEntry)
                visible: frame.picture.visible && frame.look.width > 0
                x: frame.picture.x - frame.look.width
                y: frame.picture.y - frame.look.width
                width: frame.picture.width + 2 * frame.look.width
                height: frame.picture.height + 2 * frame.look.width
                radius: frame.look.rounding + frame.look.width
                color: "transparent"
                border.width: frame.look.width
                border.color: frame.look.color
                opacity: frame.picture.opacity * frame.picture.alpha
                z: frame.picture.z
            }

            // Fades as one flat picture. Faded piece by piece, the dim over the wallpaper thinned
            // out mid-fade and the wallpaper flashed bright through a translucent window.
            Item {
                anchors.fill: parent
                opacity: peekWindow.reveal
                layer.enabled: peekWindow.reveal > 0 && peekWindow.reveal < 1

                // The window's workspace, as the background draws it with windows open
                // (WindowBlur): the wallpaper blurred, or plain, at the background's zoom. Opaque,
                // so nothing of the screen being left shows around the window or through it.
                // WindowBlur's dim never reaches the screen, so there is none here either:
                // with it, a translucent window read darker in the peek than on its workspace.
                Item {
                    id: backdrop
                    anchors.fill: parent
                    scale: root.wallpaperScale

                    Rectangle {
                        anchors.fill: parent
                        visible: backdropImage.status !== Image.Ready
                        color: Appearance.colors.colLayer0
                    }
                    Image {
                        id: backdropImage
                        anchors.fill: parent
                        visible: !root.wallpaperBlurred
                        source: root.wallpaperSource
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(peekWindow.width, peekWindow.height)
                        asynchronous: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: root.wallpaperBlurred
                        source: backdropImage
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 64
                        blur: (Config.options?.background?.blurWhenWindowsOpenRadius ?? 41) / 100
                    }
                }

                Item {
                    anchors.fill: parent
                    // Grows into place on the way in; on the way out it stays exactly over the
                    // real window, which it then fades into.
                    scale: peekWindow.open ? 0.97 + 0.03 * peekWindow.reveal : 1

                    PeekPicture {
                        id: pictureA
                        slotEntry: peekWindow.slotA
                        current: peekWindow.showA
                    }
                    PeekPicture {
                        id: pictureB
                        slotEntry: peekWindow.slotB
                        current: !peekWindow.showA
                    }
                    PeekBorder {
                        picture: pictureA
                    }
                    PeekBorder {
                        picture: pictureB
                    }
                }
            }
        }
    }
}
