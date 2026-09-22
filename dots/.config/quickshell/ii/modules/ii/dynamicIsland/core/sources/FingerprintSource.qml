pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core

/**
 * Something is waiting for a finger on the reader.
 *
 * `sudo` in a terminal behind other windows and a polkit prompt both block on the sensor
 * with nothing on screen saying so; with a 30 s timeout, the request is often gone before
 * anyone notices. fprintd broadcasts every request on the system bus whoever made it, so
 * one passive listener (dbus-monitor - it never claims the reader) is
 * enough to ask for a touch here, and to say how it went.
 *
 * Phases: "waiting" (touch the sensor), "retry" (a scan that did not count, or a wrong
 * finger with tries left), "match" (a moment of confirmation) - then gone. The lock
 * screen draws its own prompt, so the island stays out of it while locked, and so it
 * does for Settings' enrolment and test scans.
 *
 * Nothing here depends on how the request was made: plain pam_fprintd in a terminal,
 * an askpass helper, polkit. A helper that draws its own fingerprint prompt can read
 * `bar.floatingNotch.disableFingerprint` to stand aside for the island.
 */
ContinuousSource {
    id: source

    activityId: "fingerprint"

    /** "idle", "waiting", "retry" or "match". */
    property string phase: "idle"
    /** A scan-quality hint for "retry", or "" after a wrong finger. */
    property string hint: ""
    /** Who asked: a polkit message, the sudo command line, or "". */
    property string requester: ""

    condition: source.phase !== "idle" && !GlobalStates.screenLocked
        && !GlobalStates.fingerprintClaimedByShell
        // A password prompt on the island draws its own fingerprint row.
        && AskpassService.current === null
        && (!source._heldByPrompt || source.phase === "match")

    /**
     * The scan belongs to a password prompt the island showed (pam_fprintd_grosshack
     * races the finger against it), until the reader goes quiet again. A password typed
     * there stops the scan, and fprintd reports that as a no-match: without this the
     * fingerprint face flashed up after every password as if it had asked for a finger.
     * Only a real match still shows, as the confirmation.
     */
    property bool _heldByPrompt: false
    readonly property bool _promptRaces: AskpassService.current !== null
        && AskpassService.current.racesFinger === true
    on_PromptRacesChanged: {
        if (source._promptRaces)
            source._heldByPrompt = true;
        else if (source.phase === "idle")
            source._heldByPrompt = false;
    }
    payload: source.phase
    onPhaseChanged: if (source.active) source.revision += 1

    // Settings taking the reader ends whatever request was showing; otherwise that
    // prompt would come back, stale, the moment Settings let go.
    readonly property bool _claimedByShell: GlobalStates.fingerprintClaimedByShell
    on_ClaimedByShellChanged: {
        if (!source._claimedByShell)
            return;
        source._endTimer.stop();
        source._setPhase("idle");
    }

    // ── The listener, only while the activity is switched on ────────────────
    // Started and stopped by hand rather than bound: the restart below assigns
    // `running`, and an assignment would silently end a binding for good.
    onAllowedChanged: source._syncWatch()
    Component.onCompleted: source._syncWatch()

    function _syncWatch() {
        source._restartTimer.stop();
        source._watch.running = source.allowed && source._readerStack;
        if (!source.allowed)
            source._setPhase("idle");
    }

    /**
     * Whether fprintd is installed at all. Without it nothing can ever ask for a finger,
     * and a listener would sit in memory for the whole session waiting for a daemon that
     * does not exist. Read once: installing fprintd means setting up PAM too, which
     * nobody expects the running shell to notice.
     */
    property bool _readerStack: false
    property Process _stackCheck: Process {
        running: true
        command: ["sh", "-c", "for d in /usr/share /usr/local/share /etc; do "
            + "[ -e \"$d/dbus-1/system-services/net.reactivated.Fprint.service\" ] && exit 0; done; exit 1"]
        onExited: (code, status) => {
            source._readerStack = code === 0;
            source._syncWatch();
        }
    }

    // `dbus-monitor` rather than a script: it is a 3 MB C process where a Python/GObject
    // listener held 34 MB for the whole session. It cannot become a bus monitor as a
    // user and falls back to plain match rules, which is all this needs: fprintd's
    // signals are broadcast. `sender` is the well-known name, which the bus resolves
    // at delivery - so fprintd being activated later is fine, and nothing but fprintd
    // (root-owned by policy) can fake a prompt.
    property Process _watch: Process {
        command: ProcUtils.pdeath(["dbus-monitor", "--system",
            "type='signal',sender='net.reactivated.Fprint',interface='net.reactivated.Fprint.Device',member='VerifyStatus'",
            "type='signal',sender='net.reactivated.Fprint',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='net.reactivated.Fprint.Device'"])
        stdout: SplitParser {
            onRead: data => {
                // A chunk can carry more than one line.
                for (const line of String(data).split("\n"))
                    source._parseLine(line);
            }
        }
        onExited: (code, status) => {
            source._setPhase("idle");
            if (source.allowed)
                source._restartTimer.restart();
        }
    }

    /**
     * dbus-monitor prints a header line per signal and one line per argument:
     *
     *   signal ... interface=net.reactivated.Fprint.Device; member=VerifyStatus
     *      string "verify-match"
     *      boolean true
     *   signal ... interface=org.freedesktop.DBus.Properties; member=PropertiesChanged
     *      string "net.reactivated.Fprint.Device"
     *      ...  string "finger-needed"
     *           variant             boolean true
     */
    property string _member: ""
    property string _statusResult: ""
    property bool _nextIsNeeded: false

    function _parseLine(raw) {
        const line = String(raw).trim();
        if (line === "")
            return;
        if (line.startsWith("signal ")) {
            const member = /member=(\w+)/.exec(line);
            source._member = member ? member[1] : "";
            source._statusResult = "";
            source._nextIsNeeded = false;
            return;
        }
        if (source._member === "VerifyStatus") {
            const text = /^string "(.*)"$/.exec(line);
            if (text) {
                source._statusResult = text[1];
                return;
            }
            const flag = /^boolean (true|false)$/.exec(line);
            if (flag && source._statusResult !== "")
                source._handle({ event: "status", result: source._statusResult, done: flag[1] === "true" });
            return;
        }
        if (source._member === "PropertiesChanged") {
            if (line === 'string "finger-needed"') {
                source._nextIsNeeded = true;
                return;
            }
            const flag = /boolean (true|false)$/.exec(line);
            if (flag && source._nextIsNeeded) {
                source._nextIsNeeded = false;
                source._handle({ event: "needed", value: flag[1] === "true" });
            }
        }
    }

    property Timer _restartTimer: Timer {
        interval: 5000
        onTriggered: {
            if (source.allowed)
                source._watch.running = true;
        }
    }

    function _handle(event) {
        // Settings is enrolling or testing a finger and shows its own prompt.
        if (GlobalStates.fingerprintClaimedByShell) {
            source._endTimer.stop();
            source._setPhase("idle");
            return;
        }
        switch (event.event) {
        case "needed":
            if (event.value) {
                source._endTimer.stop();
                // A wrong finger with tries left comes back as a fresh request.
                source._setPhase(source.phase === "failed" ? "retry" : "waiting");
            } else if (source.phase === "waiting" || source.phase === "retry") {
                // The status that explains why usually follows at once; if none does,
                // the request was cancelled (Ctrl-C, a password typed instead).
                source._endTimer.interval = 600;
                source._endTimer.restart();
            }
            break;
        case "status":
            source._onStatus(String(event.result ?? ""), event.done === true);
            break;
        }
    }

    function _onStatus(result, done) {
        if (source.phase === "idle")
            return;
        if (result === "verify-match") {
            source.hint = "";
            source._setPhase("match");
            source._endTimer.interval = 900;
            source._endTimer.restart();
            return;
        }
        if (!done) {
            // A scan that did not read; the reader is still listening.
            source.hint = source._hintFor(result);
            source._setPhase("retry");
            return;
        }
        // No match. fprintd reports a cancel the same way, so only a new request
        // arriving shortly after says it was a real wrong finger with tries left.
        source.hint = "";
        source.phase = "failed";
        source._endTimer.interval = 1200;
        source._endTimer.restart();
    }

    function _hintFor(result) {
        switch (result) {
        case "verify-swipe-too-short":
            return Translation.tr("Too short");
        case "verify-finger-not-centered":
            return Translation.tr("Centre your finger");
        case "verify-remove-and-retry":
            return Translation.tr("Lift and try again");
        default:
            return Translation.tr("Try again");
        }
    }

    function _setPhase(next) {
        if (next === source.phase)
            return;
        const starting = source.phase === "idle" || source.phase === "failed";
        source.phase = next;
        if (next === "idle") {
            source.hint = "";
            source.requester = "";
            source._heldByPrompt = source._promptRaces;
        } else if (starting && next === "waiting") {
            source._findRequester();
        }
    }

    property Timer _endTimer: Timer {
        interval: 600
        onTriggered: source._setPhase("idle")
    }

    // ── Who asked ───────────────────────────────────────────────────────────
    function _findRequester() {
        if (PolkitService.active && PolkitService.cleanMessage !== "") {
            source.requester = PolkitService.cleanMessage;
            return;
        }
        source.requester = "";
        if (!source._requesterProc.running)
            source._requesterProc.running = true;
    }

    // One read per request, never polled: the newest sudo (or doas) on the system, if any.
    property Process _requesterProc: Process {
        command: ["pgrep", "-n", "-a", "-x", "sudo|doas"]
        stdout: StdioCollector {
            id: requesterOut
            onStreamFinished: {
                const line = String(requesterOut.text ?? "").trim();
                if (line === "" || source.requester !== "")
                    return;
                // "1234 /usr/bin/sudo -A pacman -Syu" -> "sudo pacman -Syu"
                const parts = line.split(/\s+/);
                const tool = String(parts[1] ?? "sudo").split("/").pop();
                const args = parts.slice(2).filter(arg => !arg.startsWith("-"));
                source.requester = [tool].concat(args).join(" ");
            }
        }
    }
}
