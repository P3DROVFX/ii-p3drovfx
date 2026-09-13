pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input.
 *
 * Keyboard, key repeat, mouse, touchpad, cursor, and the devices themselves. Nothing here had a
 * page anywhere in the shell before; the only way to change any of it was to edit Lua.
 *
 * Every control shows what Hyprland is actually doing until this page sets the key. The footer
 * of each section is where anything gets undone, and where the page admits that something else
 * - a hand-written line, a Mode, the shell itself - is having the last word.
 */
ContentPage {
    id: tab

    forceWidth: false

    /// The four "Advanced …" doors, the per-device overrides and the prose all sit behind the
    /// switch in the corner. What is left is the six settings a laptop actually needs.
    readonly property bool advanced: Config.options.hyprland.advancedSettings

    Component.onCompleted: {
        // The Layout row names the layout in words, so the catalogue is needed before the
        // sub-page is ever opened.
        XkbCatalog.load();
        tab.loadDevices();
    }

    /// Asking Hyprland for the device list is a process, and in basic mode there is nothing on
    /// the page that would show the answer.
    function loadDevices() {
        if (tab.advanced) HyprlandDevices.refresh();
    }

    onAdvancedChanged: tab.loadDevices()

    ContentSection {
        title: Translation.tr("Keyboard")
        icon: "keyboard"

        HyprNavRow {
            buttonIcon: "language"
            text: Translation.tr("Layout")
            value: {
                const layout = String(HyprlandGui.displayValue("input:kb_layout", "us") ?? "");
                const variant = String(HyprlandGui.displayValue("input:kb_variant", "") ?? "");
                if (layout.indexOf(",") >= 0)
                    return Translation.tr("%1 layouts").arg(layout.split(",").length);
                const name = XkbCatalog.loaded
                    ? (variant === "" ? XkbCatalog.layoutName(layout)
                        : XkbCatalog.variantName(layout, variant))
                    : layout;
                return variant === "" ? `${name} (${layout})` : `${name} (${layout} ${variant})`;
            }
            configPage: Qt.resolvedUrl("HyprKeyboardLayoutPage.qml")
            onOpenSubPage: XkbCatalog.load()

            // The row reads the layout, and nothing else on this tab asks Hyprland for it, so it
            // showed the fallback ("English (US)") until the sub-page had been opened once.
            Component.onCompleted: HyprlandGui.watch(["input:kb_layout", "input:kb_variant"])
        }

        HyprSwitch {
            optionKey: "input:numlock_by_default"
            defaultValue: true
            buttonIcon: "pin"
            text: Translation.tr("Num Lock on at startup")
            textOn: Translation.tr("Num Lock is on when the session starts.")
            textOff: Translation.tr("Num Lock is off when the session starts.")
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("Advanced keyboard")
            description: Translation.tr("Caps Lock, Compose, XKB quirks, several layouts at once")
            keys: ["input:kb_options", "input:kb_model", "input:resolve_binds_by_sym"]
            configPage: Qt.resolvedUrl("HyprKeyboardAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["input:kb_layout", "input:kb_variant", "input:numlock_by_default"]
        }
    }

    ContentSection {
        title: Translation.tr("Key repeat")
        icon: "repeat"

        HyprSlider {
            optionKey: "input:repeat_delay"
            defaultValue: 600
            integer: true
            buttonIcon: "timer"
            text: Translation.tr("Delay before repeating")
            tooltipContent: `${Math.round(value)} ms`
            from: 100
            to: 1500
            stepSize: 25
        }

        HyprSlider {
            optionKey: "input:repeat_rate"
            defaultValue: 25
            integer: true
            buttonIcon: "speed"
            text: Translation.tr("Repeats per second")
            tooltipContent: `${Math.round(value)}/s`
            from: 1
            to: 80
            stepSize: 1
        }

        HyprOptionNote {
            keys: ["input:repeat_delay", "input:repeat_rate"]
        }
    }

    ContentSection {
        title: Translation.tr("Mouse")
        icon: "mouse"

        HyprSlider {
            optionKey: "input:sensitivity"
            buttonIcon: "speed"
            text: Translation.tr("Sensitivity")
            tooltipContent: value.toFixed(2)
            from: -1
            to: 1
            stepSize: 0.05
        }

        HyprSwitch {
            optionKey: "input:natural_scroll"
            buttonIcon: "swap_vert"
            text: Translation.tr("Natural scrolling")
            textOn: Translation.tr("The content moves with the wheel, the way it does under a finger.")
            textOff: Translation.tr("The view moves with the wheel, the way a mouse usually works.")
        }

        HyprSelect {
            optionKey: "input:accel_profile"
            title: Translation.tr("Pointer acceleration")
            icon: "trending_up"
            options: [
                { "displayName": Translation.tr("libinput default"), "value": "" },
                { "displayName": Translation.tr("Adaptive"), "value": "adaptive" },
                { "displayName": Translation.tr("Flat"), "value": "flat" }
            ]
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("Advanced mouse")
            description: Translation.tr("Focus, scrolling, buttons")
            keys: ["input:left_handed", "input:force_no_accel", "input:scroll_factor",
                "input:scroll_button_lock", "input:scroll_method", "input:mouse_refocus",
                "input:follow_mouse", "input:follow_mouse_threshold", "input:focus_on_close"]
            configPage: Qt.resolvedUrl("HyprMouseAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["input:sensitivity", "input:natural_scroll", "input:accel_profile"]
        }
    }

    ContentSection {
        title: Translation.tr("Touchpad")
        icon: "touchpad_mouse"

        HyprSwitch {
            optionKey: "input:touchpad:tap_to_click"
            defaultValue: true
            buttonIcon: "touch_app"
            text: Translation.tr("Tap to click")
            textOn: Translation.tr("A tap on the pad is a click.")
            textOff: Translation.tr("Only pressing the pad clicks.")
        }

        HyprSwitch {
            optionKey: "input:touchpad:natural_scroll"
            buttonIcon: "swap_vert"
            text: Translation.tr("Natural scrolling")
            textOn: Translation.tr("The page moves with your fingers, the way a phone does.")
            textOff: Translation.tr("The page moves against your fingers, the way a mouse wheel does.")
        }

        HyprSwitch {
            optionKey: "input:touchpad:disable_while_typing"
            defaultValue: true
            buttonIcon: "keyboard_hide"
            text: Translation.tr("Ignore the touchpad while typing")
            textOn: Translation.tr("The pad ignores touches for a moment after each keystroke.")
            textOff: Translation.tr("The pad stays live while you type.")
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("Advanced touchpad")
            description: Translation.tr("Gestures, clicks, orientation")
            keys: ["input:touchpad:tap_and_drag", "input:touchpad:drag_lock", "input:touchpad:drag_3fg",
                "input:touchpad:scroll_factor", "input:touchpad:clickfinger_behavior",
                "input:touchpad:middle_button_emulation", "input:touchpad:tap_button_map",
                "input:touchpad:flip_x", "input:touchpad:flip_y"]
            configPage: Qt.resolvedUrl("HyprTouchpadAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["input:touchpad:tap-to-click", "input:touchpad:natural_scroll",
                "input:touchpad:disable_while_typing"]
        }
    }

    ContentSection {
        title: Translation.tr("Cursor")
        icon: "mouse"

        HyprSlider {
            optionKey: "cursor:inactive_timeout"
            buttonIcon: "timer_off"
            text: Translation.tr("Hide when idle")
            tooltipContent: value < 0.5 ? Translation.tr("Never") : `${value.toFixed(1)} s`
            from: 0
            to: 30
            stepSize: 0.5
            decimals: 1
        }

        HyprSwitch {
            visible: tab.advanced
            optionKey: "cursor:enable_hyprcursor"
            defaultValue: true
            buttonIcon: "brush"
            text: Translation.tr("Use hyprcursor themes")
            textOn: Translation.tr("A hyprcursor theme is used when one is installed, the XCursor one otherwise.")
            textOff: Translation.tr("Only classic XCursor themes are used.")
        }

        HyprNavRow {
            visible: tab.advanced
            buttonIcon: "tune"
            text: Translation.tr("Advanced cursor")
            description: Translation.tr("Zoom, warping, hardware")
            keys: ["cursor:hide_on_key_press", "cursor:hide_on_touch", "cursor:no_warps",
                "cursor:persistent_warps", "cursor:warp_on_change_workspace", "cursor:zoom_rigid",
                "cursor:zoom_factor", "cursor:no_hardware_cursors"]
            configPage: Qt.resolvedUrl("HyprCursorAdvancedPage.qml")
        }

        HyprOptionNote {
            keys: ["cursor:inactive_timeout", "cursor:enable_hyprcursor"]
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: tab.advanced
            text: Translation.tr("The cursor's theme and size are environment variables, not compositor options, so they live in the Environment tab.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }

    ContentSection {
        id: perDeviceSection
        visible: tab.advanced
        title: Translation.tr("Per device")
        icon: "devices"

        // Deferred to its own page: a machine with several peripherals - or one with several
        // HID interfaces per peripheral, which gaming keyboards and mice commonly register -
        // can report a dozen or more real devices, and building a full settings card for every
        // one of them the instant this tab mounted was most of what made it heavy to open.
        readonly property int deviceCount: HyprlandDevices.realKeyboards.length
            + HyprlandDevices.realMice.length + HyprlandDevices.realTablets.length
            + HyprlandDevices.realTouch.length

        HyprNavRow {
            buttonIcon: "tune"
            text: Translation.tr("Per-device overrides")
            value: HyprlandDevices.ready
                ? Translation.tr("%1 devices").arg(perDeviceSection.deviceCount)
                : Translation.tr("Asking Hyprland what is plugged in…")
            configPage: Qt.resolvedUrl("HyprPerDevicePage.qml")
        }
    }
}
