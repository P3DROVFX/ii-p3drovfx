import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One key of a shortcut, drawn the way the cheatsheet draws it so the same shortcut looks the
 * same in both places: the modifiers quiet, the key itself in the accent colour.
 *
 * Where a key has a symbol everybody already reads - the Super lozenge, an arrow, a volume
 * glyph - the symbol is shown instead of its name. "XF86AudioRaiseVolume" is not a key anybody
 * recognises at a glance; a speaker is, and it is a third of the width.
 */
Rectangle {
    id: root

    property string text: ""
    /// A modifier rather than the key the shortcut ends on.
    property bool subdued: false

    /// Key names worth replacing with a symbol. Anything not here keeps its name, because a
    /// symbol nobody recognises is worse than the word.
    readonly property var symbols: ({
        "SUPER": "keyboard_command_key", "CTRL": "keyboard_control_key",
        "ALT": "keyboard_option_key", "SHIFT": "shift", "CAPS": "keyboard_capslock",
        "Return": "keyboard_return", "KP_Enter": "keyboard_return", "Tab": "keyboard_tab",
        "BackSpace": "keyboard_backspace", "Space": "space_bar",
        "Up": "arrow_upward", "Down": "arrow_downward", "Left": "arrow_back",
        "Right": "arrow_forward", "Print": "screenshot_monitor",
        "mouse:272": "left_click", "mouse:273": "right_click", "mouse:274": "mouse",
        "mouse_up": "keyboard_double_arrow_up", "mouse_down": "keyboard_double_arrow_down",
        "XF86AudioRaiseVolume": "volume_up", "XF86AudioLowerVolume": "volume_down",
        "XF86AudioMute": "volume_off", "XF86AudioPlay": "play_arrow",
        "XF86AudioNext": "skip_next", "XF86AudioPrev": "skip_previous",
        "XF86MonBrightnessUp": "brightness_high", "XF86MonBrightnessDown": "brightness_low"
    })

    /// Set by the caller when it holds the raw key name and `text` is already the pretty label.
    property string symbolKey: ""
    readonly property string symbol: root.symbols[root.symbolKey !== "" ? root.symbolKey : root.text] ?? ""

    readonly property color foreground: root.subdued ? Appearance.colors.colOnSurfaceVariant
        : Appearance.colors.colOnPrimary

    implicitWidth: Math.max((root.symbol !== "" ? symbolItem.implicitWidth : label.implicitWidth) + 14, 28)
    implicitHeight: 26
    radius: Appearance.rounding.small
    color: root.subdued ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colPrimary

    MaterialSymbol {
        id: symbolItem
        anchors.centerIn: parent
        visible: root.symbol !== ""
        text: root.symbol
        iconSize: 16
        color: root.foreground
    }

    StyledText {
        id: label
        anchors.centerIn: parent
        visible: root.symbol === ""
        text: root.text
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: root.foreground
    }
}
