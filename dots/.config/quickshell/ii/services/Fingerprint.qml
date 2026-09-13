pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Fingerprint enrollment and reader state on top of fprintd.
 *
 * Shared by the lock screen (which arms `pam_fprintd`) and the settings page
 * (which enrols/deletes prints), so both agree on what is enrolled without
 * either of them re-running `fprintd-list` behind the other's back.
 *
 * Device metadata comes from D-Bus properties rather than the CLI: `busctl
 * --json=short` prints one JSON value per property, no GVariant parsing, and
 * reading them needs no claim on the device. `num-enroll-stages` matters a
 * lot — it is 5 on a typical swipe reader but 16 on a match-on-chip press
 * reader, and an enrollment UI that does not say how many touches are left
 * feels broken on the latter.
 *
 * Actions go through the `fprintd-*` CLI tools, which are already a hard
 * dependency of the lock screen. Two details in the command line matter:
 *  - `exec`: it makes the spawned process *be* fprintd-enroll rather than a
 *    bash wrapping it, so cancelling actually kills the enrollment instead of
 *    orphaning a process that still holds the device claim.
 *  - `stdbuf -oL`: glib's print handler was measured to flush per line on its
 *    own here, so this is insurance rather than a fix — but progress arriving
 *    only when the process exits would make the whole flow useless, and a
 *    build that block-buffers would fail exactly that way.
 *
 * Enrolling and deleting are polkit `auth_self_keep` actions: the user's own
 * password through the shell's native agent. No root, no polkit rule.
 */
Singleton {
    id: root

    // ── Device ─────────────────────────────────────────────────────────────
    property bool probed: false
    property string devicePath: ""
    property string deviceName: ""
    property string scanType: "press"
    // Fallback matches libfprint's historical default; the real value is read
    // from the device and may be far higher on match-on-chip readers.
    property int numEnrollStages: 5
    readonly property bool deviceAvailable: root.devicePath !== ""
    readonly property bool pressType: root.scanType === "press"

    // ── Enrolled prints ────────────────────────────────────────────────────
    // Plain JS array of fprintd finger ids, e.g. ["left-index-finger"].
    property var enrolled: []
    property bool enrolledLoaded: false
    readonly property bool hasEnrolled: root.enrolled.length > 0

    // ── Operations ─────────────────────────────────────────────────────────
    property bool enrollActive: false
    property string enrollFinger: ""
    property int enrollStage: 0
    // authorizing | scanning | done | failed
    property string enrollPhase: ""
    property string enrollMessage: ""
    property string enrollError: ""

    property bool verifyActive: false
    property string verifyFinger: ""
    // "" | match | no-match | error
    property string verifyResult: ""
    property string verifyMessage: ""

    property bool deleteActive: false
    property string lastError: ""

    // True whenever the reader is claimed by us. The lock screen must not arm
    // pam_fprintd against a claimed device — it would fail with
    // PAM_AUTHINFO_UNAVAIL and start its own retry ladder against a device
    // that is busy on purpose.
    readonly property bool busy: root.enrollActive || root.verifyActive || root.deleteActive

    readonly property real enrollProgress: root.numEnrollStages > 0 ? Math.min(1, root.enrollStage / root.numEnrollStages) : 0

    // ── Finger catalogue ───────────────────────────────────────────────────
    // Order is thumb → little, matching how the hand picker lays them out.
    readonly property var fingerCatalogue: [
        {
            "id": "left-thumb",
            "hand": "left",
            "digit": 0,
            "name": "Left thumb"
        },
        {
            "id": "left-index-finger",
            "hand": "left",
            "digit": 1,
            "name": "Left index"
        },
        {
            "id": "left-middle-finger",
            "hand": "left",
            "digit": 2,
            "name": "Left middle"
        },
        {
            "id": "left-ring-finger",
            "hand": "left",
            "digit": 3,
            "name": "Left ring"
        },
        {
            "id": "left-little-finger",
            "hand": "left",
            "digit": 4,
            "name": "Left little"
        },
        {
            "id": "right-thumb",
            "hand": "right",
            "digit": 0,
            "name": "Right thumb"
        },
        {
            "id": "right-index-finger",
            "hand": "right",
            "digit": 1,
            "name": "Right index"
        },
        {
            "id": "right-middle-finger",
            "hand": "right",
            "digit": 2,
            "name": "Right middle"
        },
        {
            "id": "right-ring-finger",
            "hand": "right",
            "digit": 3,
            "name": "Right ring"
        },
        {
            "id": "right-little-finger",
            "hand": "right",
            "digit": 4,
            "name": "Right little"
        }
    ]

    function catalogueEntry(finger: string): var {
        for (let i = 0; i < root.fingerCatalogue.length; i++) {
            if (root.fingerCatalogue[i].id === finger)
                return root.fingerCatalogue[i];
        }
        return null;
    }

    function defaultLabelFor(finger: string): string {
        const entry = root.catalogueEntry(finger);
        return entry ? Translation.tr(entry.name) : finger;
    }

    function isEnrolled(finger: string): bool {
        return root.enrolled.indexOf(finger) !== -1;
    }

    // ── Nicknames ──────────────────────────────────────────────────────────
    // Stored as a list of {finger, label} so the config stays a plain array
    // rather than a map with dynamic keys, which JsonAdapter handles poorly.
    function customLabelFor(finger: string): string {
        const list = Array.from(Config.options?.lock?.security?.fingerprint?.labels ?? []);
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].finger === finger)
                return list[i].label ?? "";
        }
        return "";
    }

    function labelFor(finger: string): string {
        const custom = root.customLabelFor(finger);
        return custom.length > 0 ? custom : root.defaultLabelFor(finger);
    }

    function setLabel(finger: string, label: string): void {
        const list = Array.from(Config.options.lock.security.fingerprint.labels).filter(entry => entry && entry.finger !== finger);
        const trimmed = (label ?? "").trim();
        if (trimmed.length > 0)
            list.push({
                "finger": finger,
                "label": trimmed
            });
        Config.options.lock.security.fingerprint.labels = list;
    }

    // ── Device probing ─────────────────────────────────────────────────────
    function probeDevice(): void {
        if (deviceListProc.running)
            return;
        deviceListProc.running = true;
    }

    function refresh(): void {
        root.probeDevice();
        root.refreshEnrolled();
    }

    function refreshEnrolled(): void {
        if (listProc.running)
            return;
        listProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: deviceListProc
        command: ["busctl", "--system", "--json=short", "call", "net.reactivated.Fprint", "/net/reactivated/Fprint/Manager", "net.reactivated.Fprint.Manager", "GetDevices"]
        stdout: StdioCollector {
            id: deviceListCollector
            onStreamFinished: {
                let path = "";
                try {
                    const parsed = JSON.parse(deviceListCollector.text);
                    // {"type":"ao","data":[["/net/reactivated/Fprint/Device/0"]]}
                    const paths = parsed?.data?.[0] ?? [];
                    if (paths.length > 0)
                        path = paths[0];
                } catch (e) {
                    path = "";
                }
                root.devicePath = path;
                root.probed = true;
                if (path !== "")
                    devicePropsProc.running = true;
                else
                    root.deviceName = "";
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.devicePath = "";
                root.deviceName = "";
                root.probed = true;
            }
        }
    }

    Process {
        id: devicePropsProc
        command: ["busctl", "--system", "--json=short", "get-property", "net.reactivated.Fprint", root.devicePath, "net.reactivated.Fprint.Device", "name", "num-enroll-stages", "scan-type"]
        stdout: StdioCollector {
            id: devicePropsCollector
            onStreamFinished: {
                // One JSON value per line, in the order the properties were asked for.
                const lines = devicePropsCollector.text.split("\n").filter(line => line.trim().length > 0);
                const values = lines.map(line => {
                    try {
                        return JSON.parse(line)?.data;
                    } catch (e) {
                        return undefined;
                    }
                });
                if (values[0] !== undefined)
                    root.deviceName = values[0];
                if (values[1] !== undefined && values[1] > 0)
                    root.numEnrollStages = values[1];
                if (values[2] !== undefined)
                    root.scanType = values[2];
            }
        }
    }

    // ── Enrolled list ──────────────────────────────────────────────────────
    Process {
        id: listProc
        command: ["bash", "-c", "fprintd-list \"$(whoami)\""]
        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: {
                const text = listCollector.text;
                const found = [];
                // " - #0: left-index-finger"
                const matches = text.match(/#\d+:\s*([a-z-]+)/g) ?? [];
                for (let i = 0; i < matches.length; i++) {
                    const finger = matches[i].replace(/#\d+:\s*/, "");
                    if (root.catalogueEntry(finger) && found.indexOf(finger) === -1)
                        found.push(finger);
                }
                root.enrolled = found;
                root.enrolledLoaded = true;
            }
        }
        onExited: exitCode => {
            // A user with no prints makes fprintd-list exit non-zero on some
            // versions while still printing a perfectly good "no fingers
            // enrolled" line, so an error here only means "nothing to list".
            if (exitCode !== 0 && !root.enrolledLoaded) {
                root.enrolled = [];
                root.enrolledLoaded = true;
            }
        }
    }

    // ── Claim cooldown ─────────────────────────────────────────────────────
    // fprintd only drops a claim once the previous client is fully gone, and
    // some drivers reset the reader on the way out. An operation started inside
    // that window dies with "failed to claim device", which is a lousy thing to
    // show someone who just pressed Try again — so hold the start briefly
    // instead of letting it fail.
    readonly property int claimCooldownMs: 800
    property bool claimCooling: false
    // { kind: "enroll" | "verify", finger: string }
    property var pendingStart: null

    Timer {
        id: claimCooldownTimer
        interval: root.claimCooldownMs
        onTriggered: {
            root.claimCooling = false;
            const pending = root.pendingStart;
            root.pendingStart = null;
            if (!pending)
                return;
            if (pending.kind === "enroll")
                root.spawnEnroll(pending.finger);
            else
                root.spawnVerify(pending.finger);
        }
    }

    function beginCooldown(): void {
        root.claimCooling = true;
        claimCooldownTimer.restart();
    }

    // ── Enrollment ──────────────────────────────────────────────────────────
    function startEnroll(finger: string): void {
        if (root.busy)
            return;
        root.enrollFinger = finger;
        root.enrollStage = 0;
        root.enrollPhase = "authorizing";
        root.enrollMessage = Translation.tr("Waiting for authorization…");
        root.enrollError = "";
        root.enrollActive = true;
        if (root.claimCooling) {
            root.pendingStart = {
                "kind": "enroll",
                "finger": finger
            };
            return;
        }
        root.spawnEnroll(finger);
    }

    function spawnEnroll(finger: string): void {
        enrollProc.command = ["bash", "-c", `exec stdbuf -oL fprintd-enroll -f ${finger} "$(whoami)"`];
        enrollProc.running = true;
    }

    function cancelEnroll(): void {
        if (!root.enrollActive)
            return;
        root.pendingStart = null;
        root.enrollActive = false;
        root.enrollPhase = "";
        root.enrollMessage = "";
        enrollProc.running = false;
        root.refreshEnrolled();
    }

    // Clears the leftover done/failed state so the next enrollment does not
    // open onto the previous one's result.
    function resetEnrollState(): void {
        root.enrollStage = 0;
        root.enrollPhase = "";
        root.enrollMessage = "";
        root.enrollError = "";
    }

    // Maps fprintd's enroll-result strings to something a person can act on.
    // Unknown codes fall through to a generic retry rather than stalling the
    // UI, since drivers do introduce new ones.
    function enrollStatusText(result: string): string {
        if (result.includes("retry-scan-too-short") || result.includes("swipe-too-short"))
            return root.pressType ? Translation.tr("Hold your finger on the reader a little longer") : Translation.tr("Swipe a little slower");
        if (result.includes("retry-center-finger") || result.includes("finger-not-centered"))
            return Translation.tr("Center your finger on the reader");
        if (result.includes("retry-remove-finger") || result.includes("remove-and-retry"))
            return Translation.tr("Lift your finger, then touch again");
        if (result.includes("duplicate"))
            return Translation.tr("This finger is already enrolled");
        if (result.includes("data-full"))
            return Translation.tr("The reader has no space left for new fingerprints");
        if (result.includes("disconnected"))
            return Translation.tr("The reader was disconnected");
        if (result.includes("unknown-error"))
            return Translation.tr("The reader reported an unknown error");
        return Translation.tr("Try again");
    }

    // fprintd needs a moment to drop a claim after the previous operation's
    // client goes away, and some drivers (egismoc) reset the reader on the way
    // out. Starting again inside that window prints this on *stdout*, not
    // stderr, and is worth telling apart from a genuine failure.
    function isClaimFailure(line: string): bool {
        return line.includes("failed to claim device") || line.includes("Device was not claimed");
    }

    function handleEnrollLine(line: string): void {
        if (!root.enrollActive)
            return;
        if (root.isClaimFailure(line)) {
            root.enrollPhase = "failed";
            root.enrollError = Translation.tr("The reader is busy. Wait a moment, then try again.");
            root.enrollMessage = root.enrollError;
            return;
        }
        const index = line.indexOf("Enroll result:");
        if (index === -1)
            return;
        const result = line.slice(index + "Enroll result:".length).trim();

        if (result.includes("enroll-completed")) {
            root.enrollPhase = "done";
            root.enrollStage = root.numEnrollStages;
            root.enrollMessage = Translation.tr("Fingerprint added");
            return;
        }
        if (result.includes("enroll-stage-passed")) {
            root.enrollPhase = "scanning";
            root.enrollStage = Math.min(root.numEnrollStages, root.enrollStage + 1);
            root.enrollMessage = root.pressType ? Translation.tr("Lift your finger, then touch again") : Translation.tr("Swipe again");
            return;
        }
        if (result.includes("enroll-failed") || result.includes("data-full") || result.includes("duplicate") || result.includes("disconnected")) {
            root.enrollPhase = "failed";
            root.enrollError = root.enrollStatusText(result);
            root.enrollMessage = root.enrollError;
            return;
        }
        // Anything else is a retryable scan hint; the stage counter stays put.
        root.enrollPhase = "scanning";
        root.enrollMessage = root.enrollStatusText(result);
    }

    Process {
        id: enrollProc
        stdout: SplitParser {
            // A single read can carry several lines glued together, so never
            // treat the payload as one line.
            onRead: data => data.split("\n").forEach(line => root.handleEnrollLine(line))
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.includes("not authorized") || data.includes("Not Authorized"))
                    root.enrollError = Translation.tr("Authorization was declined");
                else if (data.includes("no devices available") || data.includes("No devices available"))
                    root.enrollError = Translation.tr("No fingerprint reader was found");
            }
        }
        onExited: exitCode => {
            const wasActive = root.enrollActive;
            root.enrollActive = false;
            root.beginCooldown();
            if (!wasActive)
                return;
            if (root.enrollPhase === "done") {
                root.refreshEnrolled();
                return;
            }
            root.enrollPhase = "failed";
            if (root.enrollError === "")
                root.enrollError = exitCode === 0 ? Translation.tr("Enrollment did not complete") : Translation.tr("Enrollment failed");
            root.enrollMessage = root.enrollError;
            root.refreshEnrolled();
        }
    }

    // ── Deletion ───────────────────────────────────────────────────────────
    function deletePrint(finger: string): void {
        if (root.busy)
            return;
        root.deleteActive = true;
        root.lastError = "";
        deleteProc.command = ["bash", "-c", `fprintd-delete "$(whoami)" -f ${finger}`];
        deleteProc.running = true;
    }

    function deleteAll(): void {
        if (root.busy)
            return;
        root.deleteActive = true;
        root.lastError = "";
        deleteProc.command = ["bash", "-c", "fprintd-delete \"$(whoami)\""];
        deleteProc.running = true;
    }

    Process {
        id: deleteProc
        stderr: SplitParser {
            onRead: data => {
                if (data.includes("not authorized") || data.includes("Not Authorized"))
                    root.lastError = Translation.tr("Authorization was declined");
            }
        }
        onExited: exitCode => {
            root.deleteActive = false;
            if (exitCode !== 0 && root.lastError === "")
                root.lastError = Translation.tr("Could not delete the fingerprint");
            root.refreshEnrolled();
        }
    }

    // ── Verification (test scan) ───────────────────────────────────────────
    function startVerify(finger: string): void {
        if (root.busy)
            return;
        root.verifyFinger = finger;
        root.verifyResult = "";
        root.verifyMessage = Translation.tr("Touch the reader");
        root.verifyActive = true;
        if (root.claimCooling) {
            root.pendingStart = {
                "kind": "verify",
                "finger": finger
            };
            return;
        }
        root.spawnVerify(finger);
    }

    function spawnVerify(finger: string): void {
        verifyProc.command = ["bash", "-c", `exec stdbuf -oL fprintd-verify "$(whoami)" -f ${finger}`];
        verifyProc.running = true;
    }

    function cancelVerify(): void {
        if (!root.verifyActive)
            return;
        root.pendingStart = null;
        root.verifyActive = false;
        root.verifyResult = "";
        root.verifyMessage = "";
        verifyProc.running = false;
    }

    function handleVerifyLine(line: string): void {
        if (!root.verifyActive)
            return;
        if (root.isClaimFailure(line)) {
            root.verifyResult = "error";
            root.verifyMessage = Translation.tr("The reader is busy. Wait a moment, then try again.");
            return;
        }
        const index = line.indexOf("Verify result:");
        if (index === -1)
            return;
        const result = line.slice(index + "Verify result:".length).trim();
        if (result.includes("verify-match")) {
            root.verifyResult = "match";
            root.verifyMessage = Translation.tr("Fingerprint recognized");
        } else if (result.includes("verify-no-match")) {
            root.verifyResult = "no-match";
            root.verifyMessage = Translation.tr("Fingerprint not recognized");
        } else {
            root.verifyMessage = root.enrollStatusText(result);
        }
    }

    Process {
        id: verifyProc
        stdout: SplitParser {
            onRead: data => data.split("\n").forEach(line => root.handleVerifyLine(line))
        }
        onExited: exitCode => {
            root.verifyActive = false;
            root.beginCooldown();
            if (root.verifyResult === "") {
                root.verifyResult = "error";
                root.verifyMessage = Translation.tr("The reader did not respond");
            }
        }
    }

    // A verify result is transient feedback, not state — clear it so the row
    // does not keep showing a stale verdict.
    Timer {
        id: verifyResultClearTimer
        interval: 4000
        onTriggered: {
            root.verifyResult = "";
            root.verifyMessage = "";
            root.verifyFinger = "";
        }
    }

    onVerifyResultChanged: {
        if (root.verifyResult !== "")
            verifyResultClearTimer.restart();
    }
}
