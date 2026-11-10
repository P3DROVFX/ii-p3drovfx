pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

/**
 * Graphics tablet buttons (OpenTabletDriver express keys and pen buttons) doing shell things.
 *
 * OTD has no "run a command" binding, so three pieces have to agree, and this service owns
 * all three so nobody has to keep them in step by hand:
 *
 *   1. OTD: a slot handed to the shell becomes a Multi-Key Binding pressing an unused
 *      combination (Ctrl+Alt+Shift+Q..I for express keys, +O/P for the pen). scripts/tablet/otd_buttons.py writes
 *      settings.json (the otd console never persists) and loads it into the daemon; the
 *      binding it replaced is backed up, so "keep" puts the user's own back.
 *   2. Hyprland: those keys are bound by *code* at runtime (`hyprctl eval`) to an
 *      `iitablet,<kind>,<slot>` custom event. Runtime binds die with a config reload, so
 *      they are re-registered on `configreloaded`. Nothing is written to the Lua config.
 *   3. Here: the event is mapped to the slot's action. No process per press.
 *
 * OTD's GTK window keeps its own copy of the settings; saving from it after the shell
 * changed them writes the old bindings back. Apply again from Settings if that happens.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.interactions?.tabletButtons ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? false)

    readonly property string scriptPath: Quickshell.shellPath("scripts/tablet/otd_buttons.py")

    /// The letter each slot presses with Ctrl+Alt+Shift. Keep in sync with KEYS in
    /// otd_buttons.py. It has to be a key OTD's virtual keyboard registered with uinput:
    /// that device declares only the basic keys, and the kernel drops every other code
    /// without a word — F13-F24 were accepted by OTD and never reached Hyprland.
    readonly property var keys: ({
        "aux": ["Q", "W", "E", "R", "T", "Y", "U", "I"],
        "pen": ["O", "P"]
    })
    /// XKB keycodes (evdev + 8) of those letters, bound by code so the layout cannot move them.
    readonly property var keycodes: ({
        "Q": 24, "W": 25, "E": 26, "R": 27, "T": 28, "Y": 29, "U": 30, "I": 31, "O": 32, "P": 33
    })

    function keycodeOf(key: string): int {
        return root.keycodes[key] ?? 0;
    }

    function actionsOf(kind: string): var {
        const configured = kind === "pen" ? (root.opts?.pen ?? []) : (root.opts?.aux ?? []);
        const list = [];
        for (const entry of configured)
            list.push(String(entry ?? "keep") || "keep");
        return list;
    }
    readonly property var auxActions: root.actionsOf("aux")
    readonly property var penActions: root.actionsOf("pen")

    function actionFor(kind: string, slot: int): string {
        return (kind === "pen" ? root.penActions : root.auxActions)[slot] ?? "keep";
    }

    function setAction(kind: string, slot: int, actionId: string): void {
        if (!Config.ready)
            return;
        const list = root.actionsOf(kind);
        while (list.length <= slot)
            list.push("keep");
        list[slot] = actionId;
        if (kind === "pen")
            Config.options.interactions.tabletButtons.pen = list;
        else
            Config.options.interactions.tabletButtons.aux = list;
    }

    function handedToShell(actionId: string): bool {
        return actionId !== "keep" && actionId !== "none" && actionId.length > 0;
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    /// Live draw's own tools. Not in the shared registry: a swipe that undoes a stroke
    /// makes no sense, a button next to the pen does.
    readonly property var liveDrawActions: [
        { id: "liveDraw", name: "Draw on Screen (open / close)", icon: "draw" },
        { id: "liveDrawPen", name: "Live Draw: Pen down / click through", icon: "stylus" },
        { id: "liveDrawUndo", name: "Live Draw: Undo", icon: "undo" },
        { id: "liveDrawRedo", name: "Live Draw: Redo", icon: "redo" },
        { id: "liveDrawEraser", name: "Live Draw: Eraser", icon: "ink_eraser" },
        { id: "liveDrawLaser", name: "Live Draw: Laser pointer", icon: "flare" },
        { id: "liveDrawHighlighter", name: "Live Draw: Highlighter", icon: "ink_highlighter" },
        { id: "liveDrawSpotlight", name: "Live Draw: Spotlight", icon: "highlight" },
        { id: "liveDrawZoom", name: "Live Draw: Zoom", icon: "zoom_in" },
        { id: "liveDrawBoard", name: "Live Draw: Board (light → dark → off)", icon: "developer_board" },
        { id: "liveDrawToolbar", name: "Live Draw: Hide / show toolbar", icon: "visibility_off" },
        { id: "liveDrawClear", name: "Live Draw: Clear sheet", icon: "delete_sweep" }
    ]

    /// Everything a slot can be set to, live draw first.
    readonly property var availableActions: {
        const keep = [{ id: "keep", name: "Driver default", icon: "settings_backup_restore" }];
        const shared = TouchGestureActionRegistry.availableActionsForFamily(PanelFamily.current, false)
            .filter(action => action.id !== "none" && action.id !== "liveDraw");
        return keep.concat(root.liveDrawActions, root.scrollActions, shared);
    }

    /// What a slot of this kind may be set to: dragging needs the pen's motion.
    function actionsForKind(kind: string): var {
        return kind === "pen" ? root.availableActions
            : root.availableActions.filter(action => action.penOnly !== true);
    }

    // ── Scrolling ───────────────────────────────────────────────────────────

    /// Done by scripts/tablet/tablet_scroll.py, which reads OTD's virtual keyboard and
    /// writes a wheel of its own, so these never pass through trigger(). The Hyprland
    /// bind still exists, only to keep the combination away from the focused app.
    /// `dir` is [dx, dy] in notches, dy > 0 scrolling up.
    readonly property var scrollActions: [
        { id: "scrollUp", name: "Scroll up", icon: "keyboard_arrow_up", dir: [0, 1] },
        { id: "scrollDown", name: "Scroll down", icon: "keyboard_arrow_down", dir: [0, -1] },
        { id: "scrollLeft", name: "Scroll left", icon: "keyboard_arrow_left", dir: [-1, 0] },
        { id: "scrollRight", name: "Scroll right", icon: "keyboard_arrow_right", dir: [1, 0] },
        { id: "dragScroll", name: "Scroll by dragging (hold)", icon: "pan_tool", penOnly: true }
    ]

    function isScroll(actionId: string): bool {
        return root.scrollActions.some(action => action.id === actionId);
    }

    /// The helper's configuration: evdev codes, as OTD's keyboard reports them.
    readonly property var scrollConfig: {
        const fixed = {};
        const drag = [];
        for (const kind of ["aux", "pen"]) {
            const actions = kind === "pen" ? root.penActions : root.auxActions;
            root.keys[kind].forEach((key, slot) => {
                const action = root.scrollActions.find(item => item.id === (actions[slot] ?? "keep"));
                if (!action)
                    return;
                const code = root.keycodeOf(key) - 8;
                if (action.id === "dragScroll")
                    drag.push(code);
                else
                    fixed[String(code)] = action.dir;
            });
        }
        return {
            "fixed": fixed,
            "drag": drag,
            "step": Math.max(1, root.opts?.scrollStep ?? 1),
            "speed": Math.max(0.1, root.opts?.dragSpeed ?? 1),
            "invert": root.opts?.invertDrag ?? false
        };
    }
    readonly property bool wantsScrollHelper: root.enabled
        && (Object.keys(root.scrollConfig.fixed).length > 0 || root.scrollConfig.drag.length > 0)

    onScrollConfigChanged: root.sendScrollConfig()

    function sendScrollConfig(): void {
        if (scrollProc.running)
            scrollProc.write(JSON.stringify(root.scrollConfig) + "\n");
    }

    property string scrollError: ""

    Process {
        id: scrollProc
        command: ["python3", "-I", Quickshell.shellPath("scripts/tablet/tablet_scroll.py")]
        stdinEnabled: true
        running: root.wantsScrollHelper
        onStarted: root.sendScrollConfig()
        stderr: StdioCollector { id: scrollErr }
        // `running` is a binding, and a binding is not re-evaluated because the process
        // behind it died. Restart after a pause, or a helper that cannot start would spin.
        onExited: code => {
            if (code !== 0 && code !== 15) {
                root.scrollError = scrollErr.text.trim() || `tablet_scroll.py exited with ${code}`;
                console.warn(`[TabletButtons] ${root.scrollError}`);
            }
            if (root.wantsScrollHelper)
                scrollRestart.restart();
        }
    }

    Timer {
        id: scrollRestart
        interval: 3000
        onTriggered: {
            if (root.wantsScrollHelper && !scrollProc.running)
                scrollProc.running = true;
        }
    }

    function actionInfo(actionId: string): var {
        return root.availableActions.find(action => action.id === actionId)
            ?? { id: actionId, name: actionId, icon: "help" };
    }

    function trigger(actionId: string): void {
        if (GlobalStates.screenLocked || !root.handedToShell(actionId) || root.isScroll(actionId))
            return;
        switch (actionId) {
        case "liveDrawPen":
            LiveDraw.toggleDrawing();
            return;
        case "liveDrawUndo":
            LiveDraw.command("undo", null);
            return;
        case "liveDrawRedo":
            LiveDraw.command("redo", null);
            return;
        case "liveDrawClear":
            LiveDraw.command("clear", null);
            return;
        case "liveDrawEraser":
            if (!LiveDraw.trayOpen)
                LiveDraw.open();
            LiveDraw.eraser = !LiveDraw.eraser;
            return;
        case "liveDrawLaser":
        case "liveDrawHighlighter": {
            const tool = actionId === "liveDrawLaser" ? "laser" : "highlighter";
            if (!LiveDraw.trayOpen)
                LiveDraw.open();
            LiveDraw.setTool(LiveDraw.tool === tool && !LiveDraw.eraser ? "pen" : tool);
            return;
        }
        case "liveDrawSpotlight":
            LiveDraw.setSpotlight(!LiveDraw.spotlight);
            return;
        case "liveDrawZoom":
            LiveDraw.setZoom(!LiveDraw.zoom);
            return;
        case "liveDrawBoard":
            LiveDraw.setBoard(LiveDraw.board === "" ? "light" : LiveDraw.board === "light" ? "dark" : "", true);
            return;
        case "liveDrawToolbar":
            if (LiveDraw.trayOpen)
                LiveDraw.trayHidden = !LiveDraw.trayHidden;
            return;
        default:
            ShellActionRegistry.trigger(actionId, Hyprland.focusedMonitor?.name ?? "");
        }
    }

    function press(kind: string, slot: int): void {
        root.lastPressKind = kind;
        root.lastPressSlot = slot;
        root.lastPressAtMs = Date.now();
        if (root.enabled)
            root.trigger(root.actionFor(kind, slot));
    }

    /// The last button that reached the shell, so Settings can show it is wired up.
    property string lastPressKind: ""
    property int lastPressSlot: -1
    property real lastPressAtMs: -1

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.bindKeys();
                return;
            }
            if (event.name !== "custom")
                return;
            const data = String(event.data);
            if (!data.startsWith("iitablet,"))
                return;
            const parts = data.split(",");
            root.press(parts[1] ?? "", parseInt(parts[2] ?? "-1"));
        }
    }

    // ── Hyprland binds ──────────────────────────────────────────────────────

    /// Only the keys of slots handed to the shell are bound, so the combination still
    /// reaches apps while nothing here wants it.
    readonly property string bindScript: {
        const lines = [];
        for (const kind of ["aux", "pen"]) {
            const actions = kind === "pen" ? root.penActions : root.auxActions;
            root.keys[kind].forEach((key, slot) => {
                const code = root.keycodeOf(key);
                const combo = `CTRL + ALT + SHIFT + code:${code}`;
                lines.push(`pcall(hl.unbind, "${combo}")`);
                if (root.enabled && root.handedToShell(actions[slot] ?? "keep"))
                    lines.push(`hl.bind("${combo}", hl.dsp.event("iitablet,${kind},${slot}"), `
                        + `{ description = "Tablet: ${kind} button ${slot + 1}" })`);
            });
        }
        return lines.join("\n");
    }

    function bindKeys(): void {
        Quickshell.execDetached(["hyprctl", "eval", root.bindScript]);
    }

    onBindScriptChanged: bindTimer.restart()

    // ── OpenTabletDriver ────────────────────────────────────────────────────

    /// Each slot as the driver should have it: "shell" or "keep".
    readonly property string applySignature: {
        if (!Config.ready)
            return "";
        const encode = (kind, actions) => root.keys[kind]
            .map((key, slot) => root.enabled && root.handedToShell(actions[slot] ?? "keep") ? "shell" : "keep")
            .join(",");
        return `${encode("aux", root.auxActions)}|${encode("pen", root.penActions)}`;
    }
    property string _appliedSignature: ""
    property bool _booted: false

    onApplySignatureChanged: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 400
        onTriggered: root.applyToDriver(false)
    }

    Timer {
        id: bindTimer
        interval: 100
        onTriggered: root.bindKeys()
    }

    Component.onCompleted: {
        applyTimer.restart();
        bindTimer.restart();
    }

    /// Writes the driver's bindings. At boot with the feature off nothing is touched, so a
    /// shell that never used it never runs the script.
    function applyToDriver(force: bool): void {
        if (root.applySignature.length === 0)
            return;
        if (!force && root.applySignature === root._appliedSignature)
            return;
        if (!force && !root._booted && !root.enabled) {
            root._booted = true;
            root._appliedSignature = root.applySignature;
            return;
        }
        root._booted = true;
        if (applyProc.running) {
            applyProc.again = true;
            return;
        }
        const parts = root.applySignature.split("|");
        applyProc.signature = root.applySignature;
        applyProc.command = ["python3", root.scriptPath, "apply", "--aux", parts[0], "--pen", parts[1]];
        applyProc.running = true;
    }

    property string applyError: ""
    property bool applying: applyProc.running

    Process {
        id: applyProc
        property bool again: false
        property string signature: ""
        stderr: StdioCollector { id: applyErr }
        onExited: code => {
            if (code === 0) {
                root._appliedSignature = applyProc.signature;
                root.applyError = "";
            } else {
                root.applyError = applyErr.text.trim() || `otd_buttons.py exited with ${code}`;
                console.warn(`[TabletButtons] ${root.applyError}`);
            }
            root.refresh();
            if (applyProc.again) {
                applyProc.again = false;
                applyTimer.restart();
            }
        }
    }

    // ── Status ──────────────────────────────────────────────────────────────

    /// From otd_buttons.py status: installed, daemon, hasSettings, tablets[{name, aux, pen}].
    property var status: null
    readonly property bool otdInstalled: root.status?.installed ?? false
    readonly property bool otdRunning: root.status?.daemon ?? false
    readonly property var tablet: (root.status?.tablets ?? [])[0] ?? null
    readonly property int auxCount: root.tablet?.aux?.length ?? 0
    readonly property int penCount: root.tablet?.pen?.length ?? 0

    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
    }

    Process {
        id: statusProc
        command: ["python3", root.scriptPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.status = JSON.parse(text);
                } catch (error) {
                    root.status = null;
                }
            }
        }
    }

    /// `qs -c ii ipc call tabletButtons press aux 0`
    IpcHandler {
        target: "tabletButtons"

        function press(kind: string, slot: int): string {
            root.press(kind, slot);
            return `${kind} ${slot} -> ${root.actionFor(kind, slot)}`;
        }

        /// `set aux 0 liveDraw`; "keep" hands the button back to the driver.
        function set(kind: string, slot: int, action: string): string {
            if (kind !== "aux" && kind !== "pen")
                return "kind must be aux or pen";
            if (slot < 0 || slot >= root.keys[kind].length)
                return `slot must be 0..${root.keys[kind].length - 1}`;
            if (!root.actionsForKind(kind).some(item => item.id === action))
                return `unknown action ${action}; see 'actions'`;
            root.setAction(kind, slot, action);
            return `${kind} ${slot} -> ${action}`;
        }

        function enable(on: bool): string {
            if (!Config.ready)
                return "Config is not loaded yet.";
            Config.options.interactions.tabletButtons.enable = on;
            return on ? "Tablet buttons on." : "Tablet buttons off; driver bindings restored.";
        }

        function actions(): string {
            return root.availableActions.map(item => item.id).join("\n");
        }

        function trigger(action: string): string {
            root.trigger(action);
            return `triggered ${action}`;
        }

        function apply(): string {
            root.applyToDriver(true);
            root.bindKeys();
            return "applying";
        }

        function status(): string {
            return `enabled=${root.enabled} aux=[${root.auxActions.join(", ")}] pen=[${root.penActions.join(", ")}]`
                + ` driver=${root._appliedSignature} otd=${root.otdRunning ? "running" : "stopped"}`
                + ` tablet=${root.tablet?.name ?? "none"} last=${root.lastPressKind}:${root.lastPressSlot}`
                + ` scrollHelper=${scrollProc.running ? "running" : "off"}`
                + (root.scrollError.length > 0 ? ` scrollError=${root.scrollError}` : "")
                + (root.applyError.length > 0 ? ` error=${root.applyError}` : "");
        }
    }
}
