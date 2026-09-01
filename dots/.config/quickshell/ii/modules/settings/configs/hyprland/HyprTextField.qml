import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// A text field bound to one Hyprland option. Written when the field is left or Enter is
/// pressed, never per keystroke - each write costs a config reload.
ConfigTextField {
    id: root

    required property string optionKey
    property string defaultValue: ""

    /**
     * What the row needs, split by what it depends on.
     *
     * `resolve()` bundles all five layers into one object, so a control bound to it was rebuilt
     * whenever anything anywhere in the config changed - and with six tabs open that is every
     * control on the page, on every edit. Ownership never changes at all, and "has Hyprland
     * answered yet" changes once; only the value really moves.
     */
    readonly property bool locked: HyprlandGui.shellOwned(root.optionKey) !== ""
    readonly property string optionValue: String(HyprlandGui.displayValue(root.optionKey, root.defaultValue) ?? "")

    enabled: !root.locked
    badgeText: HyprOrigin.label(root.optionKey)

    function push() {
        if (root.inputText === root.optionValue) return;
        HyprlandGui.setKey(root.optionKey, root.inputText);
    }

    // Typing in a field whose text is being rewritten underneath is maddening, so an edit in
    // progress always wins over an incoming value.
    onOptionValueChanged: {
        if (root.textField.activeFocus) return;
        root.inputText = root.optionValue;
    }

    Component.onCompleted: {
        HyprlandGui.watch([root.optionKey]);
        root.inputText = root.optionValue;
    }

    Connections {
        target: root.textField

        function onEditingFinished() {
            root.push();
        }
    }
}
