import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// A spin box bound to one Hyprland option. Same write rule as HyprSlider: the option pushes
/// into the box, the box writes back only when the user has moved it off that value.
ConfigSpinBox {
    id: root

    required property string optionKey
    property int defaultValue: 0

    /**
     * What the row needs, split by what it depends on.
     *
     * `resolve()` bundles all five layers into one object, so a control bound to it was rebuilt
     * whenever anything anywhere in the config changed - and with six tabs open that is every
     * control on the page, on every edit. Ownership never changes at all, and "has Hyprland
     * answered yet" changes once; only the value really moves.
     */
    readonly property bool locked: HyprlandGui.shellOwned(root.optionKey) !== ""
    readonly property bool known: HyprlandGui.effective[root.optionKey] !== undefined
    readonly property int optionValue: {
        const value = Number(HyprlandGui.displayValue(root.optionKey, root.defaultValue));
        return isNaN(value) ? root.defaultValue : Math.round(value);
    }
    /// See HyprSlider: arming before Hyprland has answered turns the first real value into an
    /// edit, because this control clamps it into its own range on the way in.
    property bool armed: false
    property real reported: NaN

    enabled: !root.locked
    value: root.optionValue
    badgeText: HyprOrigin.label(root.optionKey)

    function clamped(value: real): real {
        return Math.min(root.to, Math.max(root.from, value));
    }

    onValueChanged: {
        if (!root.armed || !root.known) return;
        if (root.value === root.optionValue) return;
        if (isFinite(root.reported) && root.value === root.clamped(root.reported)) return;
        HyprlandGui.setKey(root.optionKey, root.value);
    }
    onOptionValueChanged: {
        root.reported = root.optionValue;
        root.value = root.optionValue;
    }

    Component.onCompleted: {
        HyprlandGui.watch([root.optionKey]);
        if (root.known) {
            root.reported = root.optionValue;
            Qt.callLater(() => root.armed = true);
        }
    }

    onKnownChanged: {
        if (root.armed || !root.known) return;
        root.reported = root.optionValue;
        Qt.callLater(() => root.armed = true);
    }
}
