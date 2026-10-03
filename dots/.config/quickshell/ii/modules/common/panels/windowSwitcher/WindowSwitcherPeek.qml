pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * Alt+Tab's peek: hold still on one window and the screen shows a live picture of it, drawn
 * exactly where the window is - on its own monitor, at its own size, even when it lives on
 * another workspace - over that workspace's wallpaper. Nothing moves in the compositor while
 * peeking, so Escape leaves everything where it was; a release switches with animations off
 * (WindowSwitcher) underneath the peek, which holds until the window has focus and then fades
 * away over the real window in the same place.
 *
 * With `peekWholeWorkspace` the rest of the workspace comes too: its other windows, stacked
 * as Hyprland stacks them (a special workspace over the dimmed workspace it covers), and the
 * bar left showing - the peek then covers only the part of the screen windows can use.
 *
 * The picture is captured ahead: once the switcher is up and the selection holds still for a
 * moment, the (invisible) peek already streams it, so the peek opens on a picture instead of
 * an empty backdrop - a window on another workspace takes a good half second to send its first
 * frame. The backdrop waits for the picture either way.
 *
 * Every window gets a capture of its own. Pointing one capture at another window kept the old
 * window's frames in its buffers, and the screen flickered between the two every frame.
 *
 * The window is drawn the way Hyprland draws it (`windowLooks`): at its own opacity (rules,
 * override and decoration.*_opacity), inside its border, with Hyprland's corners - a
 * superellipse when rounding_power is above 2 - over the wallpaper as the shell draws it
 * behind windows, across the whole screen. A dim over the current screen let the window you
 * were leaving show through a translucent one, and around it.
 *
 * Its own click-through layer, ordered under the island and the panel (rules.lua), so the
 * switcher stays readable above it. Loaded by every family next to the panel.
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
    /// Peek at the whole workspace, not the lone window.
    readonly property bool whole: WindowSwitcher.peekWholeWorkspace

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
                root.windowLooks = ({});
                root.mainAddresses = [];
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

    // ------------------------------------------------------------------ how Hyprland draws a window

    /// Address -> Logic.parseWindowLook: its opacities, border, corners and dim.
    property var windowLooks: ({})
    property var lookQueue: []
    /// The windows peeked at (not just drawn around one): the ones that get focus, and lose their dim.
    property var mainAddresses: []

    function lookFor(entry: var): var {
        return entry ? root.windowLooks[entry.address] : undefined;
    }

    /// How opaque Hyprland draws it: focused (or fullscreen), or as one of the others.
    function alphaFor(entry: var, focused: bool): real {
        const look = root.lookFor(entry);
        if (!look)
            return 1;
        if (!focused)
            return look.inactive;
        return entry.fullscreen ? look.fullscreen : look.active;
    }

    /// The border Hyprland draws around it, outside it: { width, color, rounding, power }.
    function borderFor(entry: var, focused: bool): var {
        const look = root.lookFor(entry);
        if (entry?.fullscreen)
            return { width: 0, color: "transparent", rounding: 0, power: 2 };
        if (!look)
            return { width: 0, color: "transparent", rounding: Appearance.rounding.windowRounding, power: 2 };
        return {
            width: look.border,
            color: focused ? look.borderColor : look.inactiveBorderColor,
            rounding: look.rounding,
            power: look.roundingPower
        };
    }

    function requestLook(address: string): void {
        if (address === "" || root.windowLooks[address] !== undefined || root.lookQueue.includes(address)
                || lookProc.address === address)
            return;
        root.lookQueue = root.lookQueue.concat([address]);
        root.runLook();
    }

    function runLook(): void {
        if (lookProc.running || root.lookQueue.length === 0)
            return;
        lookProc.address = root.lookQueue[0];
        root.lookQueue = root.lookQueue.slice(1);
        lookProc.running = true;
    }

    function storeLook(address: string, text: string): void {
        const look = Logic.parseWindowLook(text);
        const next = Object.assign({}, root.windowLooks);
        next[address] = look;
        root.windowLooks = next;
        if (look.dimmed && root.mainAddresses.includes(address))
            root.undim(address);
    }

    /// A window peeked at: it will have focus, so it is drawn - and captured - as focused.
    function noteMain(address: string): void {
        if (address === "" || root.mainAddresses.includes(address))
            return;
        root.mainAddresses = root.mainAddresses.concat([address]);
        if (root.windowLooks[address]?.dimmed)
            root.undim(address);
    }

    /**
     * decoration.dim_inactive lands in the capture: an unfocused window peeked a shade darker
     * than it shows once it has focus. The windows peeked at go undimmed while the peek is
     * around (the ones off screen show no change), and get their own setting back after. Each
     * one is written down (WindowSwitcher.undimRecordPath) before it is undimmed, so a shell
     * that dies mid-peek is cleaned up after by the next one.
     */
    property var undimmed: []

    function undim(address: string): void {
        if (root.undimmed.includes(address))
            return;
        root.undimmed = root.undimmed.concat([address]);
        // $0 the record, $1 the Lua, then every address undimmed so far.
        Quickshell.execDetached(["sh", "-c", 'c="$1"; shift; printf "%s\\n" "$@" > "$0" && hyprctl eval "$c"',
            WindowSwitcher.undimRecordPath, root.noDimChunk(address, true)].concat(root.undimmed));
    }

    function redim(): void {
        if (root.undimmed.length === 0)
            return;
        Quickshell.execDetached(["sh", "-c", 'hyprctl eval "$1"; rm -f "$0"', WindowSwitcher.undimRecordPath,
            root.undimmed.map(address => root.noDimChunk(address, false)).join("\n")]);
        root.undimmed = [];
    }

    // A shell reload mid-peek must not leave windows undimmed for good.
    Component.onDestruction: root.redim()

    function noDimChunk(address: string, on: bool): string {
        const value = on ? "1" : "unset";
        return `pcall(hl.dispatch, hl.dsp.window.set_prop({ window = "address:${address}", prop = "no_dim", value = "${value}" }))`;
    }

    // One round trip per window: every property in one `hyprctl --batch`.
    Process {
        id: lookProc
        property string address: ""
        command: ["hyprctl", "--batch", Logic.windowLookBatch(lookProc.address)]
        stdout: StdioCollector {
            onStreamFinished: root.storeLook(lookProc.address, text)
        }
        onExited: {
            lookProc.address = "";
            Qt.callLater(root.runLook);
        }
    }

    // ------------------------------------------------------------------ the windows around it

    /**
     * What a peek at `entry` draws besides it, bottom to top: `base` (the workspace a special
     * one covers, with `dim` over it), then `below` and `above` the window on its own workspace.
     */
    function sceneFor(entry: var): var {
        const empty = { base: [], dim: false, below: [], above: [] };
        if (!root.whole || !entry)
            return empty;
        const stack = Logic.stacking(WindowSwitcher.workspaceEntries(entry.workspaceId), entry.address);
        const at = stack.findIndex(e => e.address === entry.address);
        const scene = {
            base: [],
            dim: entry.special,
            below: at >= 0 ? stack.slice(0, at) : stack,
            above: at >= 0 ? stack.slice(at + 1) : []
        };
        if (entry.special)
            scene.base = Logic.stacking(WindowSwitcher.workspaceEntries(WindowSwitcher.monitorWorkspace(entry.monitor)), "");
        return scene;
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
            readonly property real originX: Number(peekWindow.monitor?.x ?? 0)
            readonly property real originY: Number(peekWindow.monitor?.y ?? 0)
            /// Left, top, right, bottom: what bars keep for themselves. The whole-workspace peek leaves it showing.
            readonly property var reserved: root.whole ? (peekWindow.monitor?.reserved ?? [0, 0, 0, 0]) : [0, 0, 0, 0]

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

            readonly property var currentSlot: peekWindow.showA ? slotViewA : slotViewB
            readonly property var shownEntry: peekWindow.currentSlot.slotEntry
            /// Backdrop and picture arrive together: the peek waits for the picture's first frame
            /// and for the wallpaper (or its failing to load).
            readonly property bool open: peekWindow.entered && root.showing && peekWindow.currentSlot.ready
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
                root.requestLook(entry.address);
                root.noteMain(entry.address);
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
                const incoming = peekWindow.showA ? slotViewB : slotViewA;
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
                    // A search matching nothing peeks at nothing: the last picture fades out.
                    if (WindowSwitcher.active)
                        peekWindow.place(root.entry);
                }
            }

            /**
             * One window as Hyprland draws it: its live capture inside Hyprland's corners, at its
             * opacity, in its border. `main` is the one peeked at, drawn focused, with its icon
             * until the first frame; the others around it stay empty until theirs.
             */
            component PeekWindow: Item {
                id: win
                required property var entry
                property bool main: false
                /// The slot is on screen: stream. Off it, only until a first frame is in hand.
                property bool streaming: true

                readonly property string address: win.entry?.address ?? ""
                readonly property var look: root.borderFor(win.entry, win.main)
                readonly property real alpha: root.alphaFor(win.entry, win.main)
                property var capture: null
                readonly property bool hasContent: win.capture?.hasContent ?? false

                Component.onCompleted: {
                    if (!win.main)
                        root.requestLook(win.address);
                }

                // Kept visible at opacity 0: a live capture only advances while the item paints.
                visible: win.entry !== null
                x: (win.entry?.x ?? 0) - peekWindow.originX
                y: (win.entry?.y ?? 0) - peekWindow.originY
                width: win.entry?.width ?? 0
                height: win.entry?.height ?? 0

                // Hyprland's border, outside the window and at its alpha. A capture has none,
                // and the real one appeared from nowhere as the peek let go.
                Shape {
                    visible: win.look.width > 0 && (win.main || win.hasContent)
                    x: -win.look.width / 2
                    y: -win.look.width / 2
                    width: win.width + win.look.width
                    height: win.height + win.look.width
                    opacity: win.alpha
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: win.look.color
                        strokeWidth: win.look.width
                        PathSvg {
                            path: Logic.roundedPath(win.width + win.look.width, win.height + win.look.width,
                                win.look.rounding + win.look.width / 2, win.look.power)
                        }
                    }
                }

                // The corners: a superellipse at rounding_power above 2, which a radius cannot draw.
                Shape {
                    id: cornerMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "white"
                        strokeColor: "transparent"
                        strokeWidth: -1
                        PathSvg {
                            path: Logic.roundedPath(win.width, win.height, win.look.rounding, win.look.power)
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: win.look.rounding > 0
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: cornerMask
                        // A soft threshold keeps the mask's antialiased edge.
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: win.main && !win.hasContent
                        color: Appearance.colors.colLayer1
                    }

                    Repeater {
                        model: win.address !== "" ? [win.address] : []
                        delegate: ScreencopyView {
                            id: screencopy
                            anchors.fill: parent
                            captureSource: win.entry?.toplevel ?? null
                            // Until its first frame, so the hidden slot is ready when it is needed.
                            live: win.streaming || !screencopy.hasContent
                            opacity: win.alpha
                            Component.onCompleted: win.capture = screencopy
                            Component.onDestruction: {
                                if (win.capture === screencopy)
                                    win.capture = null;
                            }
                        }
                    }

                    // Until the first frame lands, and for windows that cannot be captured.
                    Image {
                        anchors.centerIn: parent
                        visible: win.main && !win.hasContent
                        source: {
                            const _ = TaskbarApps.iconThemeRevision;
                            return Quickshell.iconPath(AppSearch.guessIcon(win.entry?.appClass ?? ""), "image-missing");
                        }
                        width: Math.round(Math.min(128, parent.height * 0.3))
                        height: width
                        sourceSize: Qt.size(width, height)
                        asynchronous: true
                    }
                }
            }

            /// One peek: the window, and with `whole` its workspace around it. The two slots cross-fade.
            component PeekSlot: Item {
                id: slot
                required property var slotEntry
                required property bool current

                readonly property var scene: root.sceneFor(slot.slotEntry)
                readonly property string slotAddress: slot.slotEntry?.address ?? ""
                /// A window that cannot be captured still peeks, with its icon.
                property bool waited: false
                readonly property bool ready: slot.slotAddress !== "" && (mainWindow.hasContent || slot.waited)

                onSlotAddressChanged: {
                    slot.waited = false;
                    waitTimer.restart();
                }
                onReadyChanged: peekWindow.trySwap()

                Timer {
                    id: waitTimer
                    interval: 700
                    onTriggered: slot.waited = true
                }

                anchors.fill: parent
                visible: slot.slotEntry !== null
                // The incoming slot fades in on top; the outgoing one stays under it until then,
                // so the backdrop never shows through the cross-fade.
                z: slot.current ? 1 : 0
                property bool covering: false
                onCurrentChanged: {
                    if (slot.current) {
                        coverTimer.stop();
                        slot.covering = true;
                    } else {
                        coverTimer.restart();
                    }
                }
                Timer {
                    id: coverTimer
                    interval: Appearance.animation.elementMoveFast.duration
                    onTriggered: slot.covering = false
                }
                property real fade: slot.current ? 1 : 0
                Behavior on fade {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standard
                    }
                }
                opacity: slot.current ? slot.fade : (slot.covering ? 1 : 0)
                // A whole workspace fades as one picture, or its overlapping windows would show
                // through each other mid-fade.
                layer.enabled: root.whole && slot.opacity > 0 && slot.opacity < 1

                // Keyed by address: the window list refreshing must not restart every capture.
                Repeater {
                    model: ScriptModel {
                        values: slot.scene.base
                        objectProp: "address"
                    }
                    delegate: PeekWindow {
                        required property var modelData
                        entry: modelData
                        streaming: slot.current
                    }
                }
                // Hyprland's dim behind a special workspace, over the windows it covers.
                Rectangle {
                    visible: slot.scene.dim
                    x: peekWindow.reserved[0]
                    y: peekWindow.reserved[1]
                    width: parent.width - peekWindow.reserved[0] - peekWindow.reserved[2]
                    height: parent.height - peekWindow.reserved[1] - peekWindow.reserved[3]
                    color: "black"
                    opacity: root.lookFor(slot.slotEntry)?.dimSpecial ?? 0.2
                }
                Repeater {
                    model: ScriptModel {
                        values: slot.scene.below
                        objectProp: "address"
                    }
                    delegate: PeekWindow {
                        required property var modelData
                        entry: modelData
                        streaming: slot.current
                    }
                }
                PeekWindow {
                    id: mainWindow
                    entry: slot.slotEntry
                    main: true
                    streaming: slot.current
                }
                Repeater {
                    model: ScriptModel {
                        values: slot.scene.above
                        objectProp: "address"
                    }
                    delegate: PeekWindow {
                        required property var modelData
                        entry: modelData
                        streaming: slot.current
                    }
                }
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
                // The whole-workspace peek leaves the bars' strips showing (`reserved`).
                Item {
                    id: workArea
                    x: peekWindow.reserved[0]
                    y: peekWindow.reserved[1]
                    width: parent.width - peekWindow.reserved[0] - peekWindow.reserved[2]
                    height: parent.height - peekWindow.reserved[1] - peekWindow.reserved[3]
                    clip: root.whole

                    Item {
                        id: backdrop
                        x: -workArea.x
                        y: -workArea.y
                        width: peekWindow.width
                        height: peekWindow.height
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
                }

                Item {
                    anchors.fill: parent
                    // Grows into place on the way in; on the way out it stays exactly over the
                    // real window, which it then fades into.
                    scale: peekWindow.open ? 0.97 + 0.03 * peekWindow.reveal : 1

                    PeekSlot {
                        id: slotViewA
                        slotEntry: peekWindow.slotA
                        current: peekWindow.showA
                    }
                    PeekSlot {
                        id: slotViewB
                        slotEntry: peekWindow.slotB
                        current: !peekWindow.showA
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ a click outside

    /**
     * With Alt up and a search waiting (WindowSwitcher.released), a click anywhere but the
     * switcher lets it go - it would otherwise sit there, holding every key, until Escape.
     * Under the island and the panel (rules.lua), so their own clicks reach them.
     */
    Loader {
        active: WindowSwitcher.enabled && WindowSwitcher.active && WindowSwitcher.released

        sourceComponent: PanelWindow {
            screen: Quickshell.screens.find(s => s.name === WindowSwitcher.screenName)
                ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "ii-alt-tab-catcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: WindowSwitcher.dismiss()
            }
        }
    }
}
