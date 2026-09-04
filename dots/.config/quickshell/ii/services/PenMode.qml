pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.modules.common

/**
 * The shell behaving as though a pen, rather than a mouse, is the pointer.
 *
 * Two things change, and they are separable because people want them separately.
 *
 * **The pointer becomes a pen.** Not by shipping cursor artwork — that would clash with
 * whatever theme the user picked, and Hyprland's `setcursor` selects a theme rather than
 * a shape anyway — but by deriving a theme from theirs that inherits everything and
 * overrides only the arrow with that same theme's own `pencil`. The pen cursor is the
 * user's own cursor art. See scripts/tablet/pen-cursor.sh.
 *
 * **The barrel buttons do shell things.** This is the OpenTabletDriver question, and the
 * answer turned out to be that no OpenTabletDriver integration is needed: OTD passes the
 * barrel buttons through as ordinary `BTN_STYLUS` / `BTN_STYLUS2` on the tablet device,
 * so the daemon that already watches that device for the keyboard's sake can report them.
 * The alternative — writing key combinations into OTD's settings.json and binding those
 * combinations in Hyprland — would need the user to keep three files in agreement, and
 * would break the moment they opened OTD's own UI. This needs nothing configured
 * anywhere but here.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.tablet?.pen ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? false)

    /// The daemon is shared with the keyboard's auto-show, which may well be off. Asking
    /// for it here is what keeps it running for the buttons alone.
    readonly property bool wantsPenEvents: root.enabled && (root.anyButtonBound || false)

    readonly property var buttonActions: {
        const configured = root.opts?.buttons ?? [];
        const list = [];
        for (const entry of configured)
            list.push(String(entry ?? "none"));
        return list;
    }

    readonly property bool anyButtonBound: root.buttonActions.some(id => id !== "none")

    function actionFor(index) {
        return root.buttonActions[index] ?? "none";
    }

    // ── The cursor ──────────────────────────────────────────────────────────
    readonly property bool wantsPenCursor: root.enabled && (root.opts?.cursor ?? true)
    readonly property string parentTheme: {
        const configured = String(root.opts?.cursorTheme ?? "").trim();
        if (configured.length > 0)
            return configured;
        return String(Quickshell.env("XCURSOR_THEME") ?? "").trim();
    }
    readonly property int cursorSize: root.opts?.cursorSize ?? 20
    readonly property int restoreSize: {
        const inherited = parseInt(Quickshell.env("XCURSOR_SIZE") ?? "");
        return isFinite(inherited) && inherited > 0 ? inherited : 24;
    }

    /// The derived theme's name, once it has been generated. Empty until then.
    property string penThemeName: ""
    property string cursorError: ""

    Process {
        id: penThemeBuilder
        command: [`${Directories.scriptPath}/tablet/pen-cursor.sh`, root.parentTheme]
        stdout: StdioCollector { id: penThemeOut }
        stderr: StdioCollector { id: penThemeErr }
        onExited: code => {
            if (code === 0) {
                root.penThemeName = penThemeOut.text.trim();
                root.cursorError = "";
                root.applyCursor();
            } else {
                root.penThemeName = "";
                // A theme with no pencil is the ordinary failure, and it is the user's
                // theme choice rather than a fault: say so instead of retrying.
                root.cursorError = penThemeErr.text.trim()
                    || `no pencil cursor in "${root.parentTheme}"`;
                console.warn(`[PenMode] ${root.cursorError}`);
            }
        }
    }

    function ensurePenTheme() {
        if (root.parentTheme.length === 0 || penThemeBuilder.running)
            return;
        penThemeBuilder.running = true;
    }

    /**
     * Sets the compositor's cursor theme.
     *
     * Run through `hyprctl` rather than `Hyprland.dispatch`, and that is not a style
     * choice: `setcursor` is a top-level hyprctl *command*, not a dispatcher. Sending it
     * as one made Hyprland try to parse it as Lua and fail with `')' expected near
     * 'aosp'` — the pen cursor never applied, and the only sign was a line in the log.
     *
     * The theme is global and lasts for the session, so leaving pen mode has to put the
     * user's own theme back — including when the shell exits, which is what the
     * destruction handler is for. A shell that quit leaving a pen for a pointer would be
     * a shell that broke the desktop on its way out.
     */
    function setCursorTheme(theme, size) {
        if (String(theme ?? "").length === 0)
            return;
        Quickshell.execDetached(["hyprctl", "setcursor", String(theme), String(Math.round(size))]);
    }

    function applyCursor() {
        if (root.wantsPenCursor && root.penThemeName.length > 0)
            root.setCursorTheme(root.penThemeName, root.cursorSize);
        else
            root.setCursorTheme(root.parentTheme, root.restoreSize);
    }

    onWantsPenCursorChanged: {
        if (root.wantsPenCursor)
            root.ensurePenTheme();
        else
            root.applyCursor();
    }

    Component.onCompleted: if (root.wantsPenCursor) root.ensurePenTheme()
    Component.onDestruction: {
        if (root.wantsPenCursor)
            root.setCursorTheme(root.parentTheme, root.restoreSize);
    }

    // ── The buttons ─────────────────────────────────────────────────────────
    /**
     * Which button is being held for a drag, or -1.
     *
     * Dragging is the one binding that cannot be a plain action: it means something for
     * as long as the button is down, and the pen's motion in between is the argument. So
     * it is handled here rather than dispatched to the shared registry.
     */
    property int draggingButton: -1
    property real dragLastX: 0
    property real dragLastY: 0
    /// The window's own position, accumulated across the drag. See continueDrag.
    property real dragX: 0
    property real dragY: 0
    property string dragAddress: ""

    readonly property var focusedMonitor: {
        for (const monitor of (HyprlandData.monitors ?? [])) {
            if (String(monitor?.name ?? "") === String(Hyprland.focusedMonitor?.name ?? ""))
                return monitor;
        }
        return null;
    }

    /**
     * The window a drag would move: the focused one, if it is floating.
     *
     * Looked up here rather than borrowed from TabletWindowActions, which knows this
     * already — a service may not import a panel family's module, and this is four lines
     * against a layering violation.
     *
     * Floating only, because moving a tiled window by pixels does nothing: the layout
     * puts it straight back.
     */
    function focusedFloatingClient() {
        for (const client of (HyprlandData.windowList ?? [])) {
            if (Number(client?.focusHistoryID ?? -1) !== 0)
                continue;
            return client?.floating ? client : null;
        }
        return null;
    }

    function beginDrag(x, y) {
        const client = root.focusedFloatingClient();
        if (!client) {
            root.draggingButton = -1;
            return false;
        }
        root.dragAddress = String(client.address ?? "");
        root.dragLastX = x;
        root.dragLastY = y;
        // Where the window is now, in layout coordinates. Every step adds the pen's
        // travel to this rather than re-reading the client list, which is only refreshed
        // on an event and would lag a drag badly.
        root.dragX = Number(client?.at?.[0] ?? 0);
        root.dragY = Number(client?.at?.[1] ?? 0);
        return true;
    }

    /**
     * Moves the held window by however far the pen travelled.
     *
     * The pen reports 0..1 across its own surface, which in absolute mode is the screen,
     * so a delta scales by the monitor's size. The window should follow the hand rather
     * than jump so its corner lands under the nib, which is why this accumulates a
     * position of its own instead of placing the window at the pen.
     *
     * Dispatched as an absolute move — the same call the touch handles use — because
     * that one is known to work. A `relative = true` argument was a guess about the Lua
     * dispatcher's shape, and a guess that fails does so silently in a log line.
     */
    function continueDrag(x, y) {
        if (root.dragAddress.length === 0)
            return;
        const monitor = root.focusedMonitor;
        const width = Number(monitor?.width ?? 1920);
        const height = Number(monitor?.height ?? 1080);
        const scale = Number(monitor?.scale ?? 1) || 1;
        const dx = (x - root.dragLastX) * width / scale;
        const dy = (y - root.dragLastY) * height / scale;
        root.dragLastX = x;
        root.dragLastY = y;
        if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5)
            return;
        root.dragX += dx;
        root.dragY += dy;
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${Math.round(root.dragX)}, y = ${Math.round(root.dragY)}, window = "address:${root.dragAddress}" })`);
    }

    function endDrag() {
        root.draggingButton = -1;
        root.dragAddress = "";
    }

    function handleButton(index, pressed, x, y) {
        root.lastButtonSeen = index;
        root.lastButtonAtMs = Date.now();
        if (!root.enabled)
            return;
        const action = root.actionFor(index);
        if (action === "none")
            return;

        if (action === "dragWindow") {
            if (pressed) {
                root.draggingButton = index;
                root.beginDrag(x, y);
            } else if (root.draggingButton === index) {
                root.endDrag();
            }
            return;
        }

        // Everything else fires on press, the way a button does everywhere else in this
        // shell. Releasing a button that opened a panel must not close it again.
        if (pressed)
            ShellActionRegistry.trigger(action, Hyprland.focusedMonitor?.name ?? "");
    }

    function handleMove(x, y) {
        if (root.draggingButton >= 0)
            root.continueDrag(x, y);
    }

    /// The last barrel button seen, so Settings can say whether the pen is talking to us
    /// at all. A binding nobody can confirm is a binding nobody trusts.
    property int lastButtonSeen: -1
    property real lastButtonAtMs: -1
    readonly property bool penButtonsSeen: root.lastButtonSeen >= 0

    /// `qs -c ii ipc call penMode toggle`
    IpcHandler {
        target: "penMode"

        function on(): string {
            if (!Config.ready)
                return "Config is not loaded yet.";
            Config.options.tablet.pen.enable = true;
            return "Pen mode on.";
        }

        function off(): string {
            if (!Config.ready)
                return "Config is not loaded yet.";
            Config.options.tablet.pen.enable = false;
            return "Pen mode off.";
        }

        function toggle(): string {
            return Config.options?.tablet?.pen?.enable ? off() : on();
        }

        function status(): string {
            return `enabled=${root.enabled}`
                + ` cursor=${root.wantsPenCursor ? (root.penThemeName || "pending") : "off"}`
                + ` parentTheme=${root.parentTheme}`
                + ` buttons=[${root.buttonActions.join(", ")}]`
                + ` lastButton=${root.lastButtonSeen}`
                + (root.cursorError.length > 0 ? ` error=${root.cursorError}` : "");
        }
    }
}
