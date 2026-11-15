pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * The phone's microphone over ii link (ROADMAP 5.14): raw PCM from the phone's AudioRecord
 * through the link helper's own socket into a PipeWire source (`ii-tools-mic`, via pw-cat),
 * which every app lists as a microphone and EasyEffects can take as its input. No null sink,
 * no scrcpy, no DroidCam. PhoneMicService drives it as one of its backends.
 *
 * The phone starts a session (its Mic screen, or the notification a PC request posts), the
 * helper arms it, and the link carries only the token: same shape as the webcam.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.iiTools?.mic?.enable ?? true
    readonly property bool useDroidcam: Config.options?.iiTools?.mic?.useDroidcam ?? false
    readonly property bool activeIsIi: KdeConnectService.activeIsIi
    readonly property string activeDev: {
        if (!root.activeIsIi)
            return "";
        const active = String(KdeConnectService.activeDeviceId ?? "");
        if (active.startsWith("iitools:"))
            return active.slice(8);
        return String(IiLinkService.peers[0]?.id ?? "");
    }
    readonly property bool connected: root.activeDev !== ""
        && IiLinkService.connections[root.activeDev] !== undefined
    readonly property bool hasMicCap: root.connected
        && (IiLinkService.phoneCaps[root.activeDev] ?? []).includes("mic")
    /// The ii tools phone can be the microphone: PhoneMicService uses this backend first.
    readonly property bool usable: (Config.options?.policies?.phone ?? 1) !== 0
        && root.enabled && !root.useDroidcam && root.hasMicCap && root.pwCatPresent

    readonly property string sourceName: "ii-tools-mic"

    /// "idle" | "asking" | "starting" | "live"
    property string state: "idle"
    property string lastError: ""
    property int sid: 0
    property string dev: ""
    property bool pwCatPresent: false
    property string detectedDistro: "unknown"

    signal errorOccurred(string message)

    // The phone's own sound processing (AudioRecord effects), set from the Phone tab's toggles.
    readonly property bool noiseSuppression: Config.options?.phone?.microphone?.noiseSuppression ?? false
    readonly property bool echoCancellation: Config.options?.phone?.microphone?.echoCancellation ?? false
    readonly property bool autoGainControl: Config.options?.phone?.microphone?.autoGainControl ?? false
    onNoiseSuppressionChanged: root._pushEffects()
    onEchoCancellationChanged: root._pushEffects()
    onAutoGainControlChanged: root._pushEffects()

    function _pushEffects(): void {
        if (root.dev !== "" && root.state !== "idle" && root.state !== "asking")
            IiLinkService.sendTo(root.dev, { t: "mic", a: "set", ns: root.noiseSuppression,
                aec: root.echoCancellation, agc: root.autoGainControl });
    }

    readonly property var missingDeps: root.pwCatPresent ? [] : [{
        key: "pw-cat",
        name: Translation.tr("pw-cat (PipeWire tools)"),
        description: Translation.tr("Plays the phone's audio into a PipeWire microphone source."),
        present: false,
        installCommands: ({
            arch: "sudo pacman -S pipewire",
            fedora: "sudo dnf install pipewire-utils",
            debian: "sudo apt install pipewire-bin",
            opensuse: "sudo zypper install pipewire-tools"
        })
    }]

    Component.onCompleted: root.refresh()

    function refresh(): void {
        depsProc.running = false;
        depsProc.running = true;
    }

    Process {
        id: depsProc
        running: false
        command: ["bash", "-c", "command -v pw-cat >/dev/null 2>&1 && echo pw=1 || echo pw=0"]
        stdout: StdioCollector {
            onStreamFinished: root.pwCatPresent = String(this.text).indexOf("pw=1") >= 0
        }
    }

    onActiveDevChanged: {
        if (root.dev !== "" && root.dev !== root.activeDev)
            root.stop();
    }

    onUsableChanged: {
        if (!root.usable && root.state !== "idle")
            root.stop();
    }

    /// Asks the phone to start (it posts a notification unless its Mic screen is open).
    function request(): void {
        if (!root.usable || root.state !== "idle")
            return;
        root.lastError = "";
        root.dev = root.activeDev;
        root.state = "asking";
        IiLinkService.sendTo(root.dev, { t: "mic", a: "request" });
        askTimeout.restart();
    }

    Timer {
        id: askTimeout
        interval: 70000
        onTriggered: {
            if (root.state === "asking")
                root.stop();
        }
    }

    function stop(): void {
        const targetDev = root.dev;
        const wasArmed = root.state === "starting" || root.state === "live";
        root.sid += 1;
        askTimeout.stop();
        root._reset();
        if (targetDev !== "" && IiLinkService.connections[targetDev] !== undefined)
            IiLinkService.sendTo(targetDev, { t: "mic", a: "stop" });
        if (wasArmed)
            IiLinkService.send({ op: "mic", a: "stop" });
    }

    function _reset(): void {
        root.state = "idle";
        root.dev = "";
    }

    function _fail(message: string): void {
        root.lastError = message;
        root.errorOccurred(message);
    }

    function _phoneErrorMessage(code: string): string {
        switch (code) {
        case "permission":
            return Translation.tr("Microphone permission denied: allow Microphone access for ii tools on your phone");
        case "mic":
            return Translation.tr("The phone's microphone could not be opened: another app may be using it");
        case "network":
            return Translation.tr("Microphone stream network error: check Wi-Fi");
        default:
            return code;
        }
    }

    function _reasonMessage(reason: string): string {
        switch (reason) {
        case "timeout":
            return Translation.tr("The phone did not connect to the microphone stream in time: keep ii tools open and try again");
        case "device":
            return Translation.tr("The PipeWire microphone could not be created: check that pw-cat works and PipeWire is running");
        default:
            return reason;
        }
    }

    function handleMessage(dev: string, m: var): void {
        if (m.asking !== undefined) {
            if (dev !== root.activeDev && dev !== root.dev)
                return;
            if (m.asking === true) {
                if (root.state === "idle") {
                    root.dev = dev;
                    root.state = "asking";
                }
            } else {
                if (root.state === "asking" && dev === root.dev)
                    root._reset();
                if (String(m.reason ?? "") === "notifications")
                    root._fail(Translation.tr("Open the microphone in ii tools on the phone and press Start: its notifications are off, so it cannot ask you"));
            }
            return;
        }
        if (m.err !== undefined && dev === root.dev) {
            root._fail(root._phoneErrorMessage(String(m.err)));
            root.stop();
            return;
        }
        switch (String(m.a ?? "")) {
        case "start":
            if (!root.enabled || root.useDroidcam || !root.pwCatPresent) {
                IiLinkService.sendTo(dev, { t: "mic", err: "disabled" });
                return;
            }
            if (root.state !== "idle" && root.state !== "asking" && root.dev !== dev) {
                IiLinkService.sendTo(dev, { t: "mic", err: "busy" });
                return;
            }
            if (root.state === "starting" || root.state === "live")
                IiLinkService.send({ op: "mic", a: "stop" });
            askTimeout.stop();
            root.sid += 1;
            root.dev = dev;
            root.lastError = "";
            root.state = "starting";
            IiLinkService.send({ op: "mic", a: "arm", dev: dev, sid: root.sid });
            return;
        case "stop":
            if (dev === root.dev && root.state !== "idle") {
                const wasArmed = root.state === "starting" || root.state === "live";
                root.sid += 1;
                askTimeout.stop();
                root._reset();
                if (wasArmed)
                    IiLinkService.send({ op: "mic", a: "stop" });
            }
            return;
        }
    }

    function handleEvent(ev: var): void {
        if (Number(ev?.sid ?? -1) !== root.sid || root.state === "idle")
            return;
        switch (String(ev.ev ?? "")) {
        case "mic":
            if (root.state !== "starting" || String(ev.dev ?? "") !== root.dev)
                return;
            IiLinkService.sendTo(root.dev, { t: "mic", state: "ready", token: String(ev.token ?? ""), sid: root.sid });
            root._pushEffects();
            return;
        case "micLive":
            if (String(ev.dev ?? "") !== root.dev)
                return;
            root.state = "live";
            root.lastError = "";
            IiLinkService.sendTo(root.dev, { t: "mic", state: "live", sid: root.sid });
            return;
        case "micEnd": {
            const reason = String(ev.reason ?? "");
            const targetDev = root.dev;
            const endedSid = root.sid;
            root._reset();
            if (targetDev !== "")
                IiLinkService.sendTo(targetDev, { t: "mic", state: "stopped", reason: reason, sid: endedSid });
            if (reason !== "" && reason !== "stopped" && reason !== "closed")
                root._fail(root._reasonMessage(reason));
            return;
        }
        }
    }

    function handleDisconnect(dev: string): void {
        if (dev === root.dev && root.state !== "idle" && root.state !== "live") {
            const wasArmed = root.state === "starting";
            root.sid += 1;
            askTimeout.stop();
            root._reset();
            if (wasArmed)
                IiLinkService.send({ op: "mic", a: "stop" });
        }
    }
}
