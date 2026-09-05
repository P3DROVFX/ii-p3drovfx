pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    property bool disabled: false
    property var targetDevices: ["at-translated-set-2-keyboard"]
    property bool keydDetected: false

    function detectDevice() {
        if (!HyprlandDevices.ready)
            return;

        root.keydDetected = HyprlandDevices.keyboards.some(k => /^keyd/i.test(String(k?.name ?? "")));

        const keyboards = HyprlandDevices.realKeyboards;
        for (let i = 0; i < keyboards.length; i++) {
            const name = String(keyboards[i]?.name ?? "");
            if (/at-translated/i.test(name) || /internal.*keyboard/i.test(name) || /laptop.*keyboard/i.test(name)) {
                if (!root.targetDevices.includes(name)) {
                    root.targetDevices = [name];
                }
                return;
            }
        }
    }

    Connections {
        target: HyprlandDevices
        function onReadyChanged() {
            root.detectDevice();
        }
        function onKeyboardsChanged() {
            root.detectDevice();
        }
    }

    Component.onCompleted: {
        root.detectDevice();
    }

    function setDisabled(disable: bool) {
        root.disabled = disable;
        const enabled = !disable;
        for (let i = 0; i < root.targetDevices.length; i++) {
            const dev = root.targetDevices[i];
            const lua = "hl.device({ name = '" + dev + "', enabled = " + enabled + " })";
            Quickshell.execDetached(["hyprctl", "eval", lua]);
        }
    }

    function toggle() {
        root.setDisabled(!root.disabled);
    }

    Component.onDestruction: {
        if (root.disabled) {
            for (let i = 0; i < root.targetDevices.length; i++) {
                const dev = root.targetDevices[i];
                Quickshell.execDetached(["hyprctl", "eval", "hl.device({ name = '" + dev
                                         + "', enabled = true })"]);
            }
        }
    }
}
