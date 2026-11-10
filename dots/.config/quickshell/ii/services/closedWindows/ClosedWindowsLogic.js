.pragma library

/*
 * Reopen a closed window: the pure logic. What a window's record keeps, which closes are
 * worth remembering, how the app is started again and where Hyprland is told to put it.
 * No QML, no compositor - ClosedWindows.qml calls these, and
 * scripts/tests/test_closed_windows_logic.cjs checks them directly.
 */

/// Lock.qml parks every monitor on a temporary workspace with an id at or above this while
/// the screen is locked. A window closed from there belongs where it was before the lock.
var LOCK_WORKSPACE_MIN = 10000;

// The probe's separators: ASCII record/group/unit separators never appear in a command line
// anyone types, and a newline can.
var RECORD_SEP = "\x1e";
var FIELD_SEP = "\x1d";
var ARG_SEP = "\x1f";

function normalisedAddress(raw) {
    const text = String(raw ?? "").trim();
    if (text.length === 0)
        return "";
    return text.startsWith("0x") ? text : `0x${text}`;
}

/// One `hyprctl clients` object as the service keeps it, carrying over what the previous
/// record knew: when the window was first seen, and its workspace from before a lock.
function recordFor(client, previous, monitors, now) {
    const workspace = client.workspace ?? {};
    let workspaceId = Number(workspace.id ?? 0);
    let workspaceName = String(workspace.name ?? "");
    if (workspaceId >= LOCK_WORKSPACE_MIN && previous) {
        workspaceId = previous.workspaceId;
        workspaceName = previous.workspaceName;
    }
    const at = Array.isArray(client.at) ? [Number(client.at[0]), Number(client.at[1])] : [0, 0];
    const size = Array.isArray(client.size) ? [Number(client.size[0]), Number(client.size[1])] : [0, 0];
    const monitor = (monitors ?? []).find(m => Number(m?.id) === Number(client.monitor)) ?? null;
    // Window rules place a window relative to its monitor; `at` is in layout coordinates.
    const localAt = monitor ? [at[0] - Number(monitor.x ?? 0), at[1] - Number(monitor.y ?? 0)] : at;
    return {
        "address": normalisedAddress(client.address),
        "pid": Number(client.pid ?? 0),
        "appClass": String(client.class || client.initialClass || ""),
        "title": String(client.title || client.initialTitle || ""),
        "workspaceId": workspaceId,
        "workspaceName": workspaceName,
        "floating": client.floating === true,
        "fullscreen": Number(client.fullscreen ?? 0),
        "at": at,
        "localAt": localAt,
        "size": size,
        "firstSeen": previous?.firstSeen ?? now,
        // Dialogs map floating; a window floated by hand later is a window like any other.
        "floatedAtOpen": previous ? previous.floatedAtOpen === true : client.floating === true,
        // Brought back by a reopen: the user asked for this window, so it is never a splash screen.
        "reopened": previous?.reopened === true
    };
}

/// The probe's output: the shell's own pid and, per window pid, what it takes to start the
/// process again.
function parseProbe(text) {
    const out = { "selfPid": 0, "procs": {} };
    for (const record of String(text ?? "").split(RECORD_SEP)) {
        if (record.length === 0)
            continue;
        const fields = record.split(FIELD_SEP);
        if (fields[0] === "self") {
            out.selfPid = Number(fields[1] ?? 0);
            continue;
        }
        const pid = Number(fields[0]);
        if (!(pid > 0) || fields.length < 7)
            continue;
        out.procs[pid] = {
            "argv": fields[1].length > 0 ? fields[1].split(ARG_SEP) : [],
            "cwd": fields[2],
            "flatpakId": fields[3],
            "appImage": fields[4],
            "cgroup": fields[5],
            "exeOk": fields[6] === "1"
        };
    }
    return out;
}

function basename(path) {
    const text = String(path ?? "");
    return text.slice(text.lastIndexOf("/") + 1);
}

/// A dialog (an in-process file chooser, a preferences box) is not worth relaunching the app
/// for. Neither Hyprland nor the toplevel protocol reports a dialog's parent here, so it is
/// told apart by where it lives: floating since it opened, over a bigger window of the same
/// process on the same workspace. A process that runs several real windows (kitty -1, a
/// browser - `multiWindowPids`) is left out: its small floating windows are windows too.
function isDialog(record, others, multiWindowPids) {
    if (!record.floating || !record.floatedAtOpen || !(record.pid > 0))
        return false;
    if (multiWindowPids?.[record.pid])
        return false;
    const area = record.size[0] * record.size[1];
    return (others ?? []).some(other => other.address !== record.address
        && other.pid === record.pid
        && other.workspaceId === record.workspaceId
        && other.size[0] * other.size[1] > area);
}

/// Pids with two or more tiled windows in one window list.
function tiledPids(records) {
    const counts = {};
    for (const record of records) {
        if (record.pid > 0 && !record.floating)
            counts[record.pid] = (counts[record.pid] ?? 0) + 1;
    }
    return Object.keys(counts).filter(pid => counts[pid] >= 2).map(Number);
}

/// Why a close is not remembered, or "" when it is.
function skipReason(record, proc, others, opts, now, selfPid, multiWindowPids) {
    if (!record || record.appClass.length === 0)
        return "no class";
    const ignored = (opts?.ignoredClasses ?? []).map(name => String(name).toLowerCase());
    if (ignored.indexOf(record.appClass.toLowerCase()) !== -1)
        return "ignored class";
    if (selfPid > 0 && record.pid === selfPid)
        return "the shell's own window";
    const program = basename(proc?.argv?.[0]);
    if (program === "qs" || program === "quickshell")
        return "the shell's own window";
    if (!record.reopened && now - record.firstSeen < Number(opts?.minLifetimeMs ?? 0))
        return "too short-lived";
    if (isDialog(record, others, multiWindowPids))
        return "dialog";
    return "";
}

function shellQuote(word) {
    const text = String(word);
    if (/^[A-Za-z0-9_@%+=:,./-]+$/.test(text))
        return text;
    return `'${text.replace(/'/g, `'\\''`)}'`;
}

function shellCommand(argv, cwd) {
    const command = argv.map(shellQuote).join(" ");
    return cwd ? `cd ${shellQuote(cwd)} 2>/dev/null; exec ${command}` : `exec ${command}`;
}

/// A process started by D-Bus activation only serves the bus: running its command line
/// again starts nothing anyone sees, so the app's desktop entry starts it instead.
function dbusActivated(proc) {
    return String(proc?.cgroup ?? "").startsWith("dbus-")
        || (proc?.argv ?? []).indexOf("--gapplication-service") !== -1;
}

/// How to start the app again, best first: the Flatpak, the AppImage file (its mount point
/// dies with it), the very command line (arguments and working directory too, so a viewer
/// reopens its file), then the app's desktop entry. null when there is no way.
/// `entry` is { command: [...], workingDirectory } or null.
function launchFor(proc, entry) {
    if (proc?.flatpakId)
        return { "source": "flatpak", "command": shellCommand(["flatpak", "run", proc.flatpakId], "") };
    if (proc?.appImage)
        return { "source": "appimage", "command": shellCommand([proc.appImage].concat(proc.argv.slice(1)), proc.cwd) };
    if (proc && proc.argv.length > 0 && proc.exeOk && !dbusActivated(proc))
        return { "source": "cmdline", "command": shellCommand(proc.argv, proc.cwd) };
    const command = (entry?.command ?? []).filter(word => String(word).length > 0);
    if (command.length > 0)
        return { "source": "desktop", "command": shellCommand(command, entry.workingDirectory ?? "") };
    return null;
}

/// The workspace as a dispatcher names it.
function workspaceSelector(record) {
    if (record.workspaceId < 0 || record.workspaceName.startsWith("special:"))
        return record.workspaceName;
    if (record.workspaceName.length > 0 && record.workspaceName !== String(record.workspaceId))
        return `name:${record.workspaceName}`;
    return String(record.workspaceId);
}

/// Window rules for `hl.dsp.exec_cmd`: Hyprland applies them to the window of the process it
/// starts, so the window maps in place without a frame anywhere else.
function placementRules(record) {
    const rules = { "workspace": `${workspaceSelector(record)} silent` };
    // Apps that remember their own state (kitty's remember_window_size, browsers) ask to be
    // maximized on start, which would override the size rule and tile-fill the window.
    if (record.fullscreen !== 1)
        rules.suppress_event = "maximize";
    if (record.fullscreen === 2)
        rules.fullscreen = true;
    else if (record.fullscreen === 1)
        rules.maximize = true;
    else if (record.floating) {
        rules.float = true;
        rules.size = `${Math.max(1, Math.round(record.size[0]))} ${Math.max(1, Math.round(record.size[1]))}`;
        rules.move = `${Math.round(record.localAt[0])} ${Math.round(record.localAt[1])}`;
    }
    return rules;
}

function luaString(text) {
    let out = "\"";
    for (const ch of String(text)) {
        const code = ch.codePointAt(0);
        if (ch === "\\" || ch === "\"")
            out += `\\${ch}`;
        else if (ch === "\n")
            out += "\\n";
        else if (code < 0x20 || code === 0x7f)
            out += `\\${String(code).padStart(3, "0")}`;
        else
            out += ch;
    }
    return out + "\"";
}

function luaValue(value) {
    if (typeof value === "boolean")
        return value ? "true" : "false";
    if (typeof value === "number")
        return String(value);
    return luaString(value);
}

function luaTable(object) {
    const keys = Object.keys(object);
    if (keys.length === 0)
        return "{}";
    return `{ ${keys.map(key => `${key} = ${luaValue(object[key])}`).join(", ")} }`;
}

function execDispatch(command, rules) {
    return `hl.dsp.exec_cmd(${luaString(command)}, ${luaTable(rules)})`;
}

/// A single-instance app (kitty -1, a browser already running, Nautilus) opens its window
/// from the process that was already there, which the exec rules never match. The window is
/// moved into place once it shows up instead.
function fallbackDispatches(address, record) {
    const target = luaString(`address:${address}`);
    const out = [`hl.dsp.window.move({ workspace = ${luaString(workspaceSelector(record))}, follow = false, window = ${target} })`];
    if (record.floating && record.fullscreen === 0) {
        out.push(`hl.dsp.window.float({ action = "set", window = ${target} })`);
        // Resizing keeps the centre, so the position goes last.
        out.push(`hl.dsp.window.resize({ x = ${Math.max(1, Math.round(record.size[0]))}, y = ${Math.max(1, Math.round(record.size[1]))}, window = ${target} })`);
        out.push(`hl.dsp.window.move({ x = ${Math.round(record.at[0])}, y = ${Math.round(record.at[1])}, window = ${target} })`);
    }
    return out;
}

/// The `openwindow` event's payload: ADDRESS,WORKSPACENAME,CLASS,TITLE (the title may hold commas).
function parseOpenWindow(data) {
    const parts = String(data ?? "").split(",");
    return {
        "address": normalisedAddress(parts[0]),
        "workspaceName": parts[1] ?? "",
        "appClass": parts[2] ?? "",
        "title": parts.slice(3).join(",")
    };
}

/// What to do with a window that opened while a reopen waits for its app: "" (not ours),
/// "placed" (the exec rules put it there) or "move" (it needs the fallback).
function pendingVerdict(pending, opened, now) {
    if (!pending || now > pending.deadline)
        return "";
    if (opened.appClass.toLowerCase() !== pending.record.appClass.toLowerCase())
        return "";
    const target = workspaceSelector(pending.record).replace(/^name:/, "");
    return opened.workspaceName === target ? "placed" : "move";
}

/// The stack with `entry` on top (last), never deeper than `depth`.
function pushed(stack, entry, depth) {
    const next = (stack ?? []).concat([entry]);
    const keep = Math.max(1, Number(depth) || 1);
    return next.length > keep ? next.slice(next.length - keep) : next;
}
