pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Advanced keyboard.
 *
 * XKB quirks and multi-layout setup: things almost nobody touches after the first time they set
 * them up, which is why they live behind a tap rather than sitting open on the Input tab for
 * every visit.
 */
HyprSubPage {
    title: Translation.tr("Advanced keyboard")
    subtitle: Translation.tr("XKB quirks and multiple layouts at once")

    ContentSection {
        title: Translation.tr("Key behaviour")
        icon: "keyboard_option_key"

        HyprXkbChoice {
            title: Translation.tr("Caps Lock acts as")
            icon: "keyboard_capslock"
            group: ["caps:escape", "caps:ctrl_modifier", "caps:swapescape"]
            options: [
                { "displayName": Translation.tr("Caps Lock"), "value": "" },
                { "displayName": Translation.tr("Escape"), "value": "caps:escape" },
                { "displayName": Translation.tr("Control"), "value": "caps:ctrl_modifier" },
                { "displayName": Translation.tr("Escape, and Escape as Caps Lock"), "value": "caps:swapescape" }
            ]
        }

        HyprXkbOptionSwitch {
            option: "compose:ralt"
            buttonIcon: "add_circle"
            text: Translation.tr("Right Alt is the Compose key")
            textOn: Translation.tr("Right Alt, then ', then e types é - in every app, on any layout.")
            textOff: Translation.tr("Right Alt is Alt Gr, as the layout defines it.")
        }

        HyprXkbOptionSwitch {
            option: "terminate:ctrl_alt_bksp"
            buttonIcon: "logout"
            text: Translation.tr("Ctrl+Alt+Backspace kills the session")
            textOn: Translation.tr("Ctrl+Alt+Backspace ends the session at once, unsaved work and all.")
            textOff: Translation.tr("Ctrl+Alt+Backspace does nothing special.")
        }

        HyprXkbOptionSwitch {
            option: "grp:alt_shift_toggle"
            buttonIcon: "language"
            text: Translation.tr("Alt+Shift switches between layouts")
            textOn: Translation.tr("Alt+Shift moves to the next layout in the list.")
            textOff: Translation.tr("Alt+Shift does nothing special; layouts are switched from the bar or a shortcut.")
        }

        HyprSwitch {
            optionKey: "input:resolve_binds_by_sym"
            buttonIcon: "abc"
            text: Translation.tr("Match shortcuts by symbol, not position")
            textOn: Translation.tr("SUPER+A means the key that types A on the layout in use.")
            textOff: Translation.tr("SUPER+A means the key where A sits on a US keyboard, whatever it types.")
        }

        HyprOptionNote {
            keys: ["input:kb_options", "input:resolve_binds_by_sym"]
        }
    }

    ContentSection {
        title: Translation.tr("Several layouts at once")
        icon: "list"

        HyprTextField {
            optionKey: "input:kb_layout"
            defaultValue: "us"
            icon: "language"
            text: Translation.tr("Layout codes")
            placeholderText: "fr,us"
            tooltip: Translation.tr("Comma separated. The first one is active at startup.")
        }

        HyprTextField {
            optionKey: "input:kb_variant"
            icon: "tune"
            text: Translation.tr("Variants")
            placeholderText: ",intl"
            tooltip: Translation.tr("One per layout, in the same order. Leave a slot empty for no variant.")
        }

        HyprTextField {
            optionKey: "input:kb_options"
            icon: "settings"
            text: Translation.tr("XKB options")
            placeholderText: "caps:escape,compose:ralt"
            tooltip: Translation.tr("The raw list. The rows above edit the same string.")
        }

        HyprTextField {
            optionKey: "input:kb_model"
            icon: "keyboard_alt"
            text: Translation.tr("Keyboard model")
            placeholderText: "pc105"
        }

        HyprOptionNote {
            keys: ["input:kb_layout", "input:kb_variant", "input:kb_model"]
        }
    }
}
