pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

/**
 * Segments utility buttons.
 *
 * The `default` style is a row of loose circles and the `expressive` one is a
 * filled pill with icons inside it. This is Material 3 Expressive's *connected
 * button group*: the buttons are joined shoulder to shoulder into one track, and
 * the corner radii carry every state.
 *
 *   at rest   square inner corners — the buttons read as one strip
 *   hover     the corners of that one segment lift; it starts to detach
 *   active    fully round and filled with the accent: it has popped out of the
 *             track, which is what "this toggle is on" looks like here
 *
 * These are *actions*, not statuses, so the state that matters is which one you
 * are about to press — and that is the one thing a filled pill full of icons
 * cannot say.
 *
 * The list is data, not markup. Every button is one entry with a key, and the
 * icon / active / handler lookups hang off that key; QML's dependency capture
 * reaches inside a called function, so `activeFor()` re-evaluates when the
 * service behind it changes without anything being wired per button.
 */
Item {
    id: root

    property bool vertical: BarPlacement.vertical

    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8
    // Wide enough to count the buttons, narrow enough that the strip still
    // reads as one object.
    readonly property real seam: 2

    readonly property var actions: {
        const options = Config.options.bar.utilButtons;
        const list = [];
        if (options.showScreenSnip)
            list.push("snip");
        if (options.showColorPicker)
            list.push("colorPicker");
        if (options.showScreenRecord)
            list.push("record");
        if (options.showScreenRecord && Persistent.states.screenRecord.active)
            list.push("recordPause");
        if (options.showKeyboardToggle)
            list.push("keyboard");
        if (options.showWallpaperToggle)
            list.push("wallpaper");
        if (options.showMicToggle)
            list.push("mic");
        if (options.showDarkModeToggle)
            list.push("darkMode");
        if (options.showPerformanceProfileToggle)
            list.push("performance");
        return list;
    }

    visible: root.actions.length > 0
    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : strip.implicitWidth
    implicitHeight: root.vertical ? strip.implicitHeight : Appearance.sizes.baseBarHeight

    function iconFor(key) {
        switch (key) {
        case "snip":
            return "screenshot_region";
        case "colorPicker":
            return "colorize";
        case "record":
            return Persistent.states.screenRecord.active ? "stop" : "screen_record";
        case "recordPause":
            return Persistent.states.screenRecord.paused ? "play_arrow" : "pause";
        case "keyboard":
            return "keyboard";
        case "wallpaper":
            return "imagesmode";
        case "mic":
            return (Pipewire.defaultAudioSource?.audio?.muted ?? false) ? "mic_off" : "mic";
        case "darkMode":
            return Appearance.m3colors.darkmode ? "light_mode" : "dark_mode";
        case "performance":
            switch (PowerProfiles.profile) {
            case PowerProfile.PowerSaver:
                return "energy_savings_leaf";
            case PowerProfile.Performance:
                return "local_fire_department";
            default:
                return "airwave";
            }
        }
        return "help";
    }

    // Only the buttons that genuinely latch report an active state. A snip or a
    // colour pick is over the moment it starts, and lighting its segment up
    // would say something that is not true.
    function activeFor(key) {
        switch (key) {
        case "record":
            return Persistent.states.screenRecord.active;
        case "recordPause":
            return Persistent.states.screenRecord.paused;
        case "keyboard":
            return GlobalStates.oskOpen;
        case "wallpaper":
            return GlobalStates.wallpaperSelectorOpen;
        case "mic":
            return Pipewire.defaultAudioSource?.audio?.muted ?? false;
        case "darkMode":
            return Appearance.m3colors.darkmode;
        case "performance":
            return PowerProfiles.profile !== PowerProfile.Balanced;
        }
        return false;
    }

    function invoke(key) {
        switch (key) {
        case "snip":
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
            return;
        case "colorPicker":
            GlobalStates.launchColorPicker();
            return;
        case "record":
            Quickshell.execDetached(Persistent.states.screenRecord.active
                ? [Directories.recordScriptPath]
                : [Directories.recordScriptPath, "--fullscreen"]);
            return;
        case "recordPause":
            Quickshell.execDetached([Directories.recordScriptPath, "--pause"]);
            return;
        case "keyboard":
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
            return;
        case "wallpaper":
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen;
            return;
        case "mic":
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"]);
            return;
        case "darkMode":
            Hyprland.dispatch(`exec ${Directories.wallpaperSwitchScriptPath} --mode ${Appearance.m3colors.darkmode ? "light" : "dark"} --noswitch`);
            return;
        case "performance":
            if (PowerProfiles.hasPerformanceProfile) {
                switch (PowerProfiles.profile) {
                case PowerProfile.PowerSaver:
                    PowerProfiles.profile = PowerProfile.Balanced;
                    break;
                case PowerProfile.Balanced:
                    PowerProfiles.profile = PowerProfile.Performance;
                    break;
                default:
                    PowerProfiles.profile = PowerProfile.PowerSaver;
                    break;
                }
            } else {
                PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced
                    ? PowerProfile.PowerSaver
                    : PowerProfile.Balanced;
            }
            return;
        }
    }

    // Right-click, where there is a second thing worth doing.
    function altFor(key) {
        if (key !== "record")
            return null;
        return () => Quickshell.execDetached(Persistent.states.screenRecord.active
            ? [Directories.recordScriptPath]
            : [Directories.recordScriptPath, "--region"]);
    }

    function tooltipFor(key) {
        switch (key) {
        case "snip":
            return Translation.tr("Screen snip");
        case "colorPicker":
            return Translation.tr("Pick a colour");
        case "record":
            return Persistent.states.screenRecord.active
                ? Translation.tr("Stop recording")
                : Translation.tr("Record the screen · right-click for a region");
        case "recordPause":
            return Persistent.states.screenRecord.paused
                ? Translation.tr("Resume recording")
                : Translation.tr("Pause recording");
        case "keyboard":
            return Translation.tr("On-screen keyboard");
        case "wallpaper":
            return Translation.tr("Wallpaper selector");
        case "mic":
            return (Pipewire.defaultAudioSource?.audio?.muted ?? false)
                ? Translation.tr("Unmute the microphone")
                : Translation.tr("Mute the microphone");
        case "darkMode":
            return Appearance.m3colors.darkmode
                ? Translation.tr("Switch to the light theme")
                : Translation.tr("Switch to the dark theme");
        case "performance":
            return Translation.tr("Cycle the power profile");
        }
        return "";
    }

    Grid {
        id: strip
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.actions.length
        rows: root.vertical ? root.actions.length : 1
        spacing: root.seam

        Repeater {
            model: root.actions

            delegate: UtilSegment {
                id: segment

                required property int index
                required property string modelData

                vertical: root.vertical
                thickness: root.thickness
                first: segment.index === 0
                last: segment.index === root.actions.length - 1
                iconText: root.iconFor(segment.modelData)
                active: root.activeFor(segment.modelData)
                altAction: root.altFor(segment.modelData)

                onTriggered: root.invoke(segment.modelData)

                StyledToolTip {
                    text: root.tooltipFor(segment.modelData)
                    requireOverlay: false
                }
            }
        }
    }
}
