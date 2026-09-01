import QtQuick
import qs.services

/**
 * A switch bound to one Hyprland option.
 *
 * Shows what Hyprland is actually doing until this page sets the key, then shows what this page
 * set. Writing only ever happens on a click, so the value can never write itself back.
 */
HyprToggle {
    id: root

    required property string optionKey
    /// Used only until hyprctl has answered, so the row does not flicker on first paint.
    property bool defaultValue: false

    /**
     * What the row needs, split by what it depends on.
     *
     * `resolve()` bundles all five layers into one object, so a control bound to it was rebuilt
     * whenever anything anywhere in the config changed - and with six tabs open that is every
     * control on the page, on every edit. Ownership never changes at all, and "has Hyprland
     * answered yet" changes once; only the value really moves.
     */
    readonly property bool locked: HyprlandGui.shellOwned(root.optionKey) !== ""

    switchOn: {
        const value = HyprlandGui.displayValue(root.optionKey, root.defaultValue);
        return value === true || value === 1;
    }
    badgeText: HyprOrigin.label(root.optionKey)
    enabled: !root.locked
    onRequested: wanted => HyprlandGui.setKey(root.optionKey, wanted)

    Component.onCompleted: HyprlandGui.watch([root.optionKey])
}
