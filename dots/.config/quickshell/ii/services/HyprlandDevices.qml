pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common.functions

/**
 * The input devices Hyprland can see, split into the ones a person owns and the ones software
 * invented.
 *
 * `hyprctl devices` on this laptop lists eleven keyboards and eight mice for a machine with one
 * of each: keyd, ydotool and logiops each register a virtual device, ACPI lids and power buttons
 * show up as keyboards, and a single USB receiver appears three times. A per-device settings list
 * that shows all of them is unusable, so the phantoms are filtered out - and counted, because
 * hiding them silently would be its own kind of lie.
 */
Singleton {
    id: root

    property var mice: []
    property var keyboards: []
    property var tablets: []
    property var touch: []
    property bool ready: false

    /// Names that belong to software, or to a driver's own control channel, not hardware a
    /// person would want a per-device settings card for.
    readonly property var virtualPatterns: [
        /virtual/i, /^video-bus(-\d+)?$/, /^power-button$/, /^sleep-button$/, /^lid-switch$/,
        /hid-events$/, /button-array$/, /consumer-control/, /system-control/, /^ydotool/, /^keyd/,
        /^logiops/, /^wlr/, /^wayland/, /passthrough/, /privacy-driver$/, /wmi-hotkeys$/,
        // A Bluetooth headset's AVRCP media-control endpoint registers as a "keyboard" for its
        // play/pause/volume buttons - real hardware, but not one anybody wants a keyboard-layout
        // and repeat-rate card for.
        /\(avrcp\)$/i
    ]

    function isVirtual(name: string): bool {
        return root.virtualPatterns.some(pattern => pattern.test(String(name ?? "")));
    }

    function real(list: var): var {
        return Array.from(list ?? []).filter(device => !root.isVirtual(device.name));
    }

    /// `real()` of each list, as properties: the lists above only move when their content does,
    /// so these keep their identity too and the per-device cards are not rebuilt per rescan.
    readonly property var realMice: root.real(root.mice)
    readonly property var realKeyboards: root.real(root.keyboards)
    readonly property var realTablets: root.real(root.tablets)
    readonly property var realTouch: root.real(root.touch)

    readonly property int hiddenCount:
        (root.mice.length - root.real(root.mice).length)
        + (root.keyboards.length - root.real(root.keyboards).length)
        + (root.tablets.length - root.real(root.tablets).length)
        + (root.touch.length - root.real(root.touch).length)

    /// A touchpad is a mouse as far as Hyprland is concerned, and the only thing that says
    /// otherwise is its name.
    function isTouchpad(device: var): bool {
        return /touchpad|trackpad|synaptics|glidepoint/i.test(String(device?.name ?? ""));
    }

    // ------------------------------------------------------------- one device at a time

    /**
     * Which device the per-device editor is open on.
     *
     * The list used to be one settings card per device, all expanded on one page - a laptop with
     * a gaming keyboard and a receiver reports a dozen devices, so that was a dozen identical
     * "Settings just for this device" switches in a row and nothing else legible. It is a list
     * of names now, and the settings for one of them are a page. The page is opened by URL, so
     * which device it is has to be left somewhere both sides can see.
     */
    property string editName: ""
    property string editKind: ""

    function beginEdit(name: string, kind: string) {
        root.editName = String(name ?? "");
        root.editKind = String(kind ?? "");
    }

    /// The device object behind `editName`, whichever list it came from.
    readonly property var editing: {
        const lists = [root.realKeyboards, root.realMice, root.realTablets, root.realTouch];
        for (const list of lists)
            for (const device of list)
                if (String(device.name ?? "") === root.editName) return device;
        return null;
    }

    function refresh() {
        root.stale = false;
        if (devicesProc.running) return;
        devicesProc.running = true;
    }

    /// Nothing outside Settings -> Hyprland reads this list, so it is only kept current while
    /// that page is on screen. What happened while it was closed is caught up on the way back.
    property bool stale: false

    function ensureFresh() {
        if (root.stale || !root.ready) root.refresh();
    }

    Connections {
        target: HyprlandGui
        function onWatchingChanged() {
            if (HyprlandGui.watching) root.ensureFresh();
        }
    }

    function _take(name: string, next: var) {
        if (ObjectUtils.canon(next) === ObjectUtils.canon(root[name])) return;
        root[name] = next;
    }

    Process {
        id: devicesProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    console.warn("[HyprlandDevices] cannot parse hyprctl devices:", error);
                    return;
                }
                // Replaced only on change: a rescan follows every reload and every layout
                // switch, and each one used to rebuild all the per-device cards.
                root._take("mice", parsed.mice ?? []);
                root._take("keyboards", parsed.keyboards ?? []);
                root._take("tablets", parsed.tablets ?? []);
                root._take("touch", parsed.touch ?? []);
                root.ready = true;
            }
        }
    }

    Connections {
        target: HyprlandGui

        // Only general.lua holds device blocks, so a write to any other file changes nothing
        // in this list.
        function onReloaded(own, targets) {
            if (own && targets.general !== true) return;
            root.stale = true;
            if (HyprlandGui.watching) root.refresh();
        }
    }

    Connections {
        target: Hyprland

        // Plugging a mouse in does not reload the config, so the list has to follow the
        // compositor's own device events too.
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            root.stale = true;
            if (HyprlandGui.watching) rescan.restart();
        }
    }

    Timer {
        id: rescan
        interval: 400
        onTriggered: root.refresh()
    }
}
