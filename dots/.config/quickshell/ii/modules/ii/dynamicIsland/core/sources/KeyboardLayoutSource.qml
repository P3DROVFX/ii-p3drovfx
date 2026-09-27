pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * The keyboard layout changed.
 *
 * Pointless with a single layout configured, and the first reading after startup is the
 * layout the session already had. A different main keyboard is not a switch either: a
 * headset's AVRCP device takes that role as it connects, with its own default keymap, and
 * announced it the moment the Bluetooth strip should have had the island.
 */
TransientSource {
    id: source

    activityId: "keyboard"
    ttlMs: 1500
    cooldownMs: 300

    readonly property string currentLayout: HyprlandXkb.currentLayoutName
    property string previousLayout: ""
    property string previousKeyboard: ""

    onCurrentLayoutChanged: {
        const from = source.previousLayout;
        const fromKeyboard = source.previousKeyboard;
        source.previousLayout = source.currentLayout;
        source.previousKeyboard = HyprlandXkb.mainKeyboardName;
        if (from === "" || from === source.currentLayout)
            return;
        if (fromKeyboard !== HyprlandXkb.mainKeyboardName)
            return;
        if (HyprlandXkb.layoutCodes.length <= 1)
            return;
        source.trigger({ from: from, to: source.currentLayout });
    }

    Component.onCompleted: {
        source.previousLayout = source.currentLayout;
        source.previousKeyboard = HyprlandXkb.mainKeyboardName;
    }
}
