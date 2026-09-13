pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Compiling one of the shell's Rust helpers from inside the shell.
 *
 * Both helpers — the on-screen keyboard's `osk_autoshow` and the touch gesture
 * daemon's `touch_gestures` — ship as source and are correctly kept out of git. On a
 * fresh install neither runs, and until this existed the only way out either offered
 * was a command to paste into a terminal.
 *
 * That is an acceptable answer on a desktop and a circular one on a tablet: the two
 * things standing between a device with no keyboard and a usable shell are the
 * keyboard that raises itself and the gestures that navigate, and the fix for both
 * required a keyboard to type it. So the build is a button, and this is the button's
 * machinery, shared because there are two of them and they differ only in a path.
 *
 * Not a singleton: one instance per helper.
 */
QtObject {
    id: root

    /// Absolute path of the cargo project.
    required property string sourceDir
    /// Where the finished binary must end up.
    required property string binaryPath
    /// What cargo names it under target/release.
    required property string crateName
    /// For log lines and for the Settings copy.
    property string label: "helper"

    property bool building: false
    /// "" until something is attempted, then "ok" or "failed".
    property string buildResult: ""
    /// Whatever cargo said when it failed. Empty on success: nobody reads a build log
    /// that worked, and keeping it only invites showing it.
    property string buildOutput: ""
    /// No toolchain, no button. Pointing someone at a build they cannot run is worse
    /// than telling them what is missing.
    property bool cargoAvailable: false

    // ── Live progress ───────────────────────────────────────────────────────
    /**
     * What cargo is doing right now, read off its own output.
     *
     * A build takes a minute on a cold cache, and a button that just says "Building…"
     * for a minute is indistinguishable from a button that hung. Cargo already narrates
     * itself — one `Compiling <crate>` line per unit — so the progress here is its
     * narration rather than a number invented to fill a bar.
     */
    property string currentUnit: ""
    property int unitsCompiled: 0

    /**
     * How many units a cold build will compile, from the lockfile.
     *
     * Cargo does not announce a total before it starts, which is why the first draft of
     * this was indeterminate. But `Cargo.lock` lists exactly the packages that will be
     * built: for the gesture daemon it holds 23 entries and a clean build reported
     * exactly 23 crates. So the bar has a real denominator rather than an invented one.
     *
     * A warm cache compiles fewer than that, so the bar can finish short of the end —
     * which is honest (the build genuinely skipped work) and is why `finished` snaps it
     * to full rather than leaving it hanging at four fifths.
     */
    property int totalUnits: 0

    readonly property real progress: {
        if (root.buildResult === "ok")
            return 1;
        if (!root.building || root.totalUnits <= 0)
            return 0;
        return Math.max(0, Math.min(1, root.unitsCompiled / root.totalUnits));
    }

    readonly property FileView _lockFile: FileView {
        path: root.sourceDir.length > 0 ? `${root.sourceDir}/Cargo.lock` : ""
        onLoaded: {
            const matches = text().match(/^\[\[package\]\]$/gm);
            root.totalUnits = matches ? matches.length : 0;
        }
        // A missing lockfile is not an error worth surfacing: the bar falls back to the
        // crate count beside it, which is true either way.
        onLoadFailed: root.totalUnits = 0
    }
    /// A short phrase for the current phase: "Downloading", "Compiling", "Linking".
    property string phase: ""
    /// How long this build has been running, in seconds — the other honest signal that
    /// something is still happening.
    property int elapsedSeconds: 0

    signal finished(bool ok)

    /// The tail of cargo's output, for a failure. Bounded: a build that fails with
    /// hundreds of errors should not grow a string until the shell notices.
    property var _outputTail: []

    function _remember(line) {
        const tail = root._outputTail.slice(-39);
        tail.push(line);
        root._outputTail = tail;
    }

    /**
     * One line of cargo's stderr.
     *
     * Cargo indents its status lines by a few spaces and puts the verb first, which is
     * the whole grammar this needs to read.
     */
    function _consume(line) {
        const text = String(line ?? "");
        root._remember(text);

        const status = text.trim().match(/^(Compiling|Downloading|Downloaded|Updating|Building|Installing|Fresh) (\S+)/);
        if (status) {
            root.phase = status[1];
            root.currentUnit = status[2];
            if (status[1] === "Compiling")
                root.unitsCompiled++;
            return;
        }
        if (text.trim().startsWith("Finished")) {
            root.phase = "Finished";
            root.currentUnit = "";
        }
    }

    readonly property Timer _elapsedTimer: Timer {
        interval: 1000
        repeat: true
        running: root.building
        onTriggered: root.elapsedSeconds++
    }

    readonly property Process _cargoCheck: Process {
        command: ["sh", "-c", "command -v cargo"]
        onExited: code => root.cargoAvailable = (code === 0)
        Component.onCompleted: running = true
    }

    readonly property Process _buildProcess: Process {
        id: buildProcess

        /**
         * `sh -c` rather than an argv list, because this is three steps and the last two
         * are conditional on the first.
         *
         * Installed through a rename rather than a copy. By the time anyone rebuilds,
         * the previous helper is usually running, and writing over a running executable
         * is ETXTBSY — `cp` fails, the build is reported as failed, and a compile that
         * actually worked is thrown away. A rename swaps the directory entry and leaves
         * the running process on the old inode until it exits.
         */
        command: ["sh", "-c",
            `cd '${root.sourceDir}' && cargo build --release`
            + ` && cp 'target/release/${root.crateName}' '${root.binaryPath}.new'`
            + ` && mv -f '${root.binaryPath}.new' '${root.binaryPath}'`]

        // Parsed line by line rather than collected: cargo's narration is only useful
        // while it is happening, and a collector hands it over after the fact.
        stdout: SplitParser { onRead: line => root._consume(line) }
        stderr: SplitParser { onRead: line => root._consume(line) }

        onExited: code => {
            root.building = false;
            root.buildResult = code === 0 ? "ok" : "failed";
            root.buildOutput = code === 0 ? "" : root._outputTail.join("\n").trim();
            root.currentUnit = "";
            root.phase = code === 0 ? "Finished" : "Failed";
            if (code !== 0)
                console.warn(`[${root.label}] build failed (${code}): ${root.buildOutput}`);
            root.finished(code === 0);
        }
    }

    function build() {
        if (root.building || root.sourceDir.length === 0)
            return;
        root.building = true;
        root.buildResult = "";
        root.buildOutput = "";
        root._outputTail = [];
        root.currentUnit = "";
        root.unitsCompiled = 0;
        root.elapsedSeconds = 0;
        root.phase = "Starting";
        buildProcess.running = false;
        Qt.callLater(() => buildProcess.running = true);
    }

    /// One line describing where the build has got to, or "" when nothing is running.
    readonly property string progressText: {
        if (!root.building)
            return "";
        if (root.currentUnit.length > 0)
            return `${root.phase} ${root.currentUnit}`;
        return root.phase.length > 0 ? root.phase : "Starting";
    }

    /// The last few lines of a failure, which is the part that says what went wrong.
    function failureSummary(lines) {
        const count = lines === undefined ? 3 : lines;
        return root.buildOutput.split("\n").slice(-count).join(" ").trim();
    }
}
