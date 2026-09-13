import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A labelled row of choices, bound to a Hyprland option key or driven by hand.
 *
 * With `optionKey` set it reads and writes that key. With `currentOverride` set instead it just
 * reports what was chosen. That is what the per-device cards need, a device override being one
 * Lua table rather than a set of independent keys - and what a chooser standing in for several
 * keys needs, with `keys` naming them so the row still knows who set them and watches them.
 */
ContentSubsection {
    id: root

    property string optionKey: ""
    property var defaultValue: ""
    /// Used in place of an option key. Ignored when `optionKey` is set.
    property var currentOverride: undefined
    /// The keys a hand-driven chooser reads and writes. Ignored when `optionKey` is set.
    property var keys: []
    /// Off for a chooser whose key is shared with rows it has nothing to do with - every XKB
    /// option group lives in the same string.
    property bool showOrigin: true
    property alias options: choices.options

    signal selected(var newValue)

    /**
     * What the row needs, split by what it depends on.
     *
     * `resolve()` bundles all five layers into one object, so a control bound to it was rebuilt
     * whenever anything anywhere in the config changed - and with six tabs open that is every
     * control on the page, on every edit. Ownership never changes at all, and "has Hyprland
     * answered yet" changes once; only the value really moves.
     */
    readonly property var ownKeys: root.optionKey !== "" ? [root.optionKey] : Array.from(root.keys ?? [])
    readonly property bool locked: root.ownKeys.some(key => HyprlandGui.shellOwned(key) !== "")
    readonly property var optionValue: root.optionKey === ""
        ? root.currentOverride : HyprlandGui.displayValue(root.optionKey, root.defaultValue)
    readonly property string origin: root.showOrigin ? HyprOrigin.label(root.ownKeys) : ""

    Layout.fillWidth: true
    headerExtra: root.origin !== "" ? originPill : null

    Component {
        id: originPill

        HyprBadge {
            text: root.origin
        }
    }

    ConfigSelectionArray {
        id: choices
        enabled: !root.locked
        currentValue: root.optionValue
        onSelected: newValue => {
            if (root.optionKey !== "") HyprlandGui.setKey(root.optionKey, newValue);
            root.selected(newValue);
        }
    }

    Component.onCompleted: {
        if (root.ownKeys.length > 0) HyprlandGui.watch(root.ownKeys);
    }
}
