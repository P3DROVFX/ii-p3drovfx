pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
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
 *
 * With the ii tools app reporting calls over ii link (`IiLinkService.callsLive`), the
 * phone itself says what the call is now, and the buttons go to Android's own call
 * controls: no ADB, no polling, and the end of the call is known for sure.
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
    /** The app reports calls over ii link: state and buttons go through it. */
    readonly property bool linkLive: IiLinkService.callsLive
    /** Whether the buttons can do anything right now. */
    readonly property bool controllable: root.linkLive || root.adbLive

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

    // ── The call's audio on the PC ──────────────────────────────────────
    // Android lets no app capture a call, but it sends a call to a Bluetooth headset:
    // the PC becomes one (HFP, hands-free role, which PipeWire's own backend does), and
    // only for the call. WirePlumber routes the call like any app's audio: the phone's
    // voice to the default output, the default microphone to the phone. Only the HFP
    // profile is connected, so the phone's media never moves to the PC.

    readonly property bool pcAudioEnabled: (Config.options?.iiTools?.callAudio?.enable ?? true) && root.linkLive
    /// The phone among this PC's paired Bluetooth devices, by the name ii tools knows.
    readonly property var phoneBluetooth: {
        const name = String(IiLinkService.peers[0]?.name ?? "").trim();
        if (name === "")
            return null;
        return Bluetooth.devices.values.find(d => d.paired && (d.name === name || d.deviceName === name)) ?? null;
    }
    readonly property bool canUsePc: root.pcAudioEnabled && root.phoneBluetooth !== null
    /// Every call goes to the PC on its own (ringing, or dialled), not only on request.
    readonly property bool pcAudioAuto: root.canUsePc && (Config.options?.iiTools?.callAudio?.auto ?? true)
    /// Moved back to the phone by hand: not taken again for this call.
    property bool _keptOnPhone: false
    /// The call's audio is on the PC now.
    readonly property bool pcAudio: root.canUsePc && root.active && (root.phoneBluetooth?.connected ?? false)
    readonly property bool pcAudioBusy: hfpProc.running
    property string pcAudioError: ""
    /// Connected by us, so ours to undo when the call ends.
    property bool _weConnected: false
    property bool _answerAfterConnect: false

    readonly property string _hfpUuid: "0000111f-0000-1000-8000-00805f9b34fb"

    /** Answer with the PC as the headset. */
    function answerOnPc() {
        if (root.callState !== "ringing" || !root.canUsePc)
            return;
        root._answerAfterConnect = true;
        root._hfp(true);
    }

    function moveToPc() {
        if (root.active && root.canUsePc && !root.pcAudio)
            root._hfp(true);
    }

    function moveToPhone() {
        if (root.pcAudio) {
            root._keptOnPhone = true;
            root._hfp(false);
        }
    }

    // A call starting (ringing, or one dialled on the phone) takes the PC as its headset
    // at once, so answering anywhere talks through the PC.
    onCallStateChanged: {
        if (root.callState !== "idle" && root.pcAudioAuto && !root._keptOnPhone && !root._simulated
                && !(root.phoneBluetooth?.connected ?? false))
            root._hfp(true);
    }

    function _hfp(connect) {
        if (hfpProc.running || !root.phoneBluetooth)
            return;
        root.pcAudioError = "";
        hfpProc.connecting = connect;
        hfpProc.command = connect
            ? ["bluetoothctl", "--timeout", "15", "connect", root.phoneBluetooth.address, root._hfpUuid]
            : ["bluetoothctl", "--timeout", "10", "disconnect", root.phoneBluetooth.address];
        hfpProc.running = true;
    }

    Process {
        id: hfpProc
        property bool connecting: false
        stdout: StdioCollector { id: hfpOut }
        onExited: code => {
            const ok = code === 0 && /successful/i.test(hfpOut.text);
            if (hfpProc.connecting) {
                root._weConnected = ok || root._weConnected;
                if (!ok)
                    root.pcAudioError = Translation.tr("The phone did not connect over Bluetooth");
                // Answered either way: a failed connection must not leave the call ringing.
                if (root._answerAfterConnect) {
                    root._answerAfterConnect = false;
                    root.answer();
                }
            } else if (ok) {
                root._weConnected = false;
            }
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    function answer() {
        if (root.callState !== "ringing")
            return;
        // A simulated call (IPC `simulate`): play it out here, there is no phone to ask.
        if (root._simulated)
            return root._setState("talking");
        if (!IiLinkService.phoneCommand("answer"))
            root._key(79);   // KEYCODE_HEADSETHOOK: answers a ringing call
    }

    function decline() {
        if (root.callState === "idle")
            return;
        if (root._simulated)
            return root._setState("idle");
        if (!IiLinkService.phoneCommand("end"))
            root._key(6);    // KEYCODE_ENDCALL: rejects a ringing call, ends one in progress
    }

    /** Silences the ringer without rejecting. */
    function silence() {
        if (root.callState !== "ringing" || root._simulated)
            return;
        if (!IiLinkService.phoneCommand("silence"))
            root._key(25);   // KEYCODE_VOLUME_DOWN
    }

    function _key(code) {
        Quickshell.execDetached(["adb"].concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", "input", "keyevent", String(code)]));
        // Answering and hanging up show on the next poll; ask for it now.
        pollTimer.restart();
        root._poll();
    }

    // ── ii link: the phone says what the call is ────────────────────────────
    Connections {
        target: IiLinkService
        function onCallReported(state, name) {
            if (root._simulated)
                return;
            if (name !== "" && root.contactName === "")
                root.contactName = name;
            if (state === "ringing" || state === "talking" || state === "idle")
                root._setState(state);
        }
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
                if (!root._simulated && !root.linkLive)
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
            // The PC was the headset for this call only.
            if (root._weConnected)
                hfpRelease.restart();
            root._answerAfterConnect = false;
            root._keptOnPhone = false;
            root.adbLive = false;
            root.contactName = "";
            root._simulated = false;
            root._failedPolls = 0;
        } else {
            root._poll();
        }
    }

    // ── ADB: what the call is now ───────────────────────────────────────────
    property int _failedPolls: 0

    function _poll() {
        if (root.callState === "idle" || root._simulated || root.linkLive || statePoll.running)
            return;
        statePoll.running = true;
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: root.active && !root._simulated && !root.linkLive
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
        running: root.callState === "ringing" && !root.controllable
        onTriggered: root._setState("idle")
    }

    // A moment after the call, so the phone has closed the audio link first.
    Timer {
        id: hfpRelease
        interval: 1500
        onTriggered: {
            if (root.callState === "idle" && root._weConnected)
                root._hfp(false);
        }
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
        function status(): string {
            return JSON.stringify({ state: root.callState, name: root.displayName, linkLive: root.linkLive, adbLive: root.adbLive, simulated: root._simulated,
                canUsePc: root.canUsePc, pcAudio: root.pcAudio, phoneBluetooth: root.phoneBluetooth?.address ?? "" });
        }
        function answer(): void { root.answer(); }
        function decline(): void { root.decline(); }
    }
}
