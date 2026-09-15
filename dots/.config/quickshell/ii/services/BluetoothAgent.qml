pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services
import qs.modules.common.functions

/**
 * The pairing agent BlueZ needs before it will ask anyone anything.
 *
 * Pairing is a conversation: the remote device offers a passkey, or wants a PIN
 * typed, and BlueZ hands that question to whichever D-Bus object registered as
 * an `org.bluez.Agent1`. Quickshell's Bluetooth API has no way to be one, so a
 * small Python helper (`scripts/bluetooth/agent.py`) holds the D-Bus side and
 * talks to this singleton in JSON lines. Without it, `pair()` on anything more
 * demanding than a mouse just fails.
 *
 * `request` is the question waiting on the user; `display` is a passkey BlueZ
 * only wants shown, with nothing to answer.
 */
Singleton {
    id: root

    /** Questions BlueZ asked but nobody has answered yet, oldest first. */
    property var queue: []
    readonly property var request: root.queue.length > 0 ? root.queue[0] : null
    readonly property bool hasRequest: root.request !== null

    /** A passkey or PIN to read out to the other device. Nothing to answer. */
    property var display: null

    property bool ready: false
    /** False when another agent already holds the default slot. */
    property bool isDefaultAgent: false
    property string lastError: ""

    readonly property bool available: Bluetooth.adapters.values.length > 0

    signal requestReceived(var request)

    // Types that need a value typed in rather than a yes/no.
    readonly property var typedRequestKinds: ["pincode", "passkey"]
    readonly property bool needsValue: root.hasRequest
        && root.typedRequestKinds.indexOf(root.request.type) !== -1

    // A passkey is six digits and is compared against another screen, so the
    // leading zeros BlueZ drops on the way through an integer have to come back.
    function formatPasskey(value): string {
        const digits = `${value ?? 0}`;
        return digits.length >= 6 ? digits : "0".repeat(6 - digits.length) + digits;
    }

    function requestName(request): string {
        if (!request)
            return "";
        const name = request.name ?? "";
        return name.length > 0 ? name : (request.address ?? Translation.tr("A device"));
    }

    function requestTitle(request): string {
        if (!request)
            return "";
        if (request.type === "confirm")
            return Translation.tr("Does %1 show this code?").arg(root.requestName(request));
        if (request.type === "pincode")
            return Translation.tr("Type the PIN shown on %1").arg(root.requestName(request));
        if (request.type === "passkey")
            return Translation.tr("Type the passkey shown on %1").arg(root.requestName(request));
        if (request.type === "authorize-service")
            return Translation.tr("%1 wants to use a service").arg(root.requestName(request));
        return Translation.tr("%1 wants to pair").arg(root.requestName(request));
    }

    function respond(id: int, action: string, value): void {
        if (!agentProcess.running)
            return;
        agentProcess.write(JSON.stringify({
            id: id,
            action: action,
            value: value ?? ""
        }) + "\n");
        root.queue = root.queue.filter(entry => entry.id !== id);
    }

    function accept(value): void {
        if (!root.hasRequest)
            return;
        root.respond(root.request.id, value === undefined ? "accept" : "value", value);
    }

    function reject(): void {
        if (!root.hasRequest)
            return;
        root.respond(root.request.id, "reject", "");
    }

    function dismissDisplay(): void {
        root.display = null;
        displayTimeout.stop();
    }

    function handleEvent(event): void {
        if (event.event === "ready") {
            root.ready = true;
            root.isDefaultAgent = event.default === true;
            root.lastError = "";
            return;
        }
        if (event.event === "error") {
            root.ready = false;
            root.lastError = event.message ?? "";
            console.warn("[BluetoothAgent]", root.lastError);
            return;
        }
        if (event.event === "request") {
            root.dismissDisplay();
            root.queue = [...root.queue, event];
            root.requestReceived(event);
            return;
        }
        if (event.event === "display") {
            root.display = event;
            displayTimeout.restart();
            return;
        }
        if (event.event === "cancel") {
            root.queue = [];
            root.dismissDisplay();
        }
    }

    // BlueZ never says a displayed passkey is finished with, so it is dropped on
    // a timer rather than left on screen for the rest of the session.
    Timer {
        id: displayTimeout
        interval: 60000
        onTriggered: root.display = null
    }

    Process {
        id: agentProcess
        stdinEnabled: true
        // DisplayYesNo covers every pairing method a laptop can actually
        // perform: it can show a passkey, ask for one, and confirm a match.
        command: ProcUtils.pdeath(["python3", Quickshell.shellPath("scripts/bluetooth/agent.py"),
            "DisplayYesNo"])
        running: root.available

        onRunningChanged: {
            if (running)
                return;
            root.ready = false;
            root.queue = [];
            root.display = null;
        }

        stdout: SplitParser {
            onRead: data => {
                // One read can carry several lines glued together.
                data.split("\n").forEach(line => {
                    if (line.trim().length === 0)
                        return;
                    try {
                        root.handleEvent(JSON.parse(line));
                    } catch (error) {
                        console.warn("[BluetoothAgent] bad event:", line, error);
                    }
                });
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length > 0)
                    console.warn("[BluetoothAgent stderr]", data);
            }
        }
    }
}
