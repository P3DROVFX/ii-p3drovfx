pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * A call on the paired phone: ringing, in progress, or just missed.
 *
 * Two halves, because neither side can tell the whole story alone.
 *
 * KDE Connect says a call *started*: its telephony plugin emits `callReceived` for
 * "ringing", "talking" and "missedCall". It never says one ended - the phone's cancel
 * packet only closes the daemon's own notification, and nothing reaches D-Bus.
 *
 * ADB says what the call is *now*: `dumpsys telephony.registry` carries `mCallState`
 * (0 idle, 1 ringing, 2 off-hook). It is read every two seconds, and only while a call
 * is up, so an idle phone costs nothing. ADB is also the only way to answer or decline
 * from here; there is no `telecom accept` on current Android, so the buttons press the
 * headset hook and the end-call key, and only while the phone reports a call, since
 * the end-call key on an idle phone turns its screen off.
 *
 * Without ADB the ringing card still shows, silences nothing and leaves on its own
 * timer; an answered call cannot be followed, so it simply ends.
 */
Singleton {
    id: root

    /** "idle", "ringing" or "talking". */
    property string callState: "idle"
    property string number: ""
    /** The name KDE Connect resolved, if any. */
    property string contactName: ""
    /** When the current state began, for the in-call timer. */
    property double stateSince: 0
    /** Whether ADB answered the last poll: the buttons only mean something then. */
    property bool adbLive: false

    readonly property bool active: root.callState !== "idle"
    /** A call injected over IPC for testing: ADB knows nothing about it, so don't ask. */
    property bool _simulated: false

    /** The contact record for the caller, for the photo; null when unknown. */
    readonly property var contact: root.number !== "" ? PhoneContactsService.contactByNumber(root.number) : null
    readonly property string displayName: root.contactName !== "" ? root.contactName
        : (root.contact && root.contact.displayName ? root.contact.displayName
            : (root.number !== "" ? root.number : Translation.tr("Unknown caller")))
    readonly property string avatarPath: root.contact ? String(root.contact.avatarPath ?? "") : ""

    signal missed(string displayName, string number)

    // ── Actions ─────────────────────────────────────────────────────────────
    function answer() {
        if (root.callState !== "ringing")
            return;
        root._key(79);   // KEYCODE_HEADSETHOOK: answers a ringing call
    }

    function decline() {
        if (root.callState === "idle")
            return;
        root._key(6);    // KEYCODE_ENDCALL: rejects a ringing call, ends one in progress
    }

    /** Silences the ringer without rejecting: a volume key does that while ringing. */
    function silence() {
        if (root.callState !== "ringing")
            return;
        root._key(25);   // KEYCODE_VOLUME_DOWN
    }

    function _key(code) {
        Quickshell.execDetached(["adb"].concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "input", "keyevent", String(code)]));
        // Answering and hanging up show on the next poll; ask for it now.
        pollTimer.restart();
        root._poll();
    }

    // ── KDE Connect: a call started ─────────────────────────────────────────
    Connections {
        target: KdeConnectService
        function onCallEvent(devId, state, number, contact) {
            if (state === "missedCall") {
                const name = contact !== "" ? contact : number;
                root._setState("idle");
                root.missed(name, number);
                return;
            }
            root.number = number;
            root.contactName = contact;
            if (state === "ringing") {
                root._setState("ringing");
                // Always try: the transport goes cold while idle, and warming it on
                // the first ring is what makes Answer work a second later.
                if (!root._simulated)
                    KdeConnectService._probeAdb();
            } else if (state === "talking") {
                root._setState("talking");
            }
        }
    }

    function _setState(next) {
        if (root.callState === next)
            return;
        root.callState = next;
        root.stateSince = Date.now();
        if (next === "idle") {
            root.adbLive = false;
            root._simulated = false;
            root._failedPolls = 0;
        } else {
            root._poll();
        }
    }

    // ── ADB: what the call is now ───────────────────────────────────────────
    property int _failedPolls: 0

    function _poll() {
        if (root.callState === "idle" || root._simulated || statePoll.running)
            return;
        statePoll.running = true;
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: root.active && !root._simulated
        onTriggered: root._poll()
    }

    Process {
        id: statePoll
        command: ["adb"].concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "dumpsys telephony.registry | grep -m1 mCallState="])
        stdout: StdioCollector {
            id: stateOut
        }
        onExited: (code, status) => {
            const match = /mCallState=(\d)/.exec(stateOut.text ?? "");
            if (code !== 0 || !match) {
                root.adbLive = false;
                root._failedPolls += 1;
                // Following a call needs ADB; without it an answered call is lost the
                // moment it is answered, so give up after a few tries.
                if (root.callState === "talking" && root._failedPolls >= 3)
                    root._setState("idle");
                return;
            }
            root.adbLive = true;
            root._failedPolls = 0;
            switch (match[1]) {
            case "0":
                root._setState("idle");
                break;
            case "1":
                root._setState("ringing");
                break;
            case "2":
                root._setState("talking");
                break;
            }
        }
    }

    // A ring nothing can follow (no ADB) must not stay on screen forever: phones stop
    // ringing into voicemail after about 30 s.
    Timer {
        interval: 45000
        running: root.callState === "ringing" && !root.adbLive
        onTriggered: root._setState("idle")
    }

    IpcHandler {
        target: "phoneCall"

        /** Simulate a call for testing: state is ringing, talking, missedCall or idle. */
        function simulate(state: string, number: string, contact: string): void {
            if (state === "idle") {
                root._setState("idle");
                return;
            }
            root._simulated = true;
            KdeConnectService.callEvent("", state, number, contact);
        }
        function answer(): void { root.answer(); }
        function decline(): void { root.decline(); }
    }
}
