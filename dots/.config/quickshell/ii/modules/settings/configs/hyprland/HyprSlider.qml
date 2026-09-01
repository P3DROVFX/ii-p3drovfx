import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A slider bound to one Hyprland option, with a live preview while dragging.
 *
 * The value is not bound to the option: the option is pushed into the slider whenever it
 * changes from elsewhere, and the slider writes back only when its own value stops matching.
 * Binding both ways would make every refresh look like a fresh edit.
 */
ConfigSlider {
    id: root

    required property string optionKey
    property real defaultValue: 0
    /// Hyprland types its options; writing 0.5 into an int key is rejected on reload.
    property bool integer: false
    property int decimals: 2

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
    readonly property real optionValue: {
        const value = Number(HyprlandGui.displayValue(root.optionKey, root.defaultValue));
        return isNaN(value) ? root.defaultValue : value;
    }
    /**
     * Nothing is written before Hyprland's own value has arrived and been shown.
     *
     * Arming on a timer instead was not enough: the answer from hyprctl is a process away, so
     * the control was armed while still sitting on its default, and the first real value then
     * arrived, got clamped into the control's range or rounded to its precision, and was
     * written straight back. Opening the page changed the setting.
     */
    property bool armed: false
    /// The last value Hyprland reported, before this control clamped or rounded it.
    property real reported: NaN

    usePercentTooltip: false
    enabled: !root.locked
    badgeText: HyprOrigin.label(root.optionKey)
    // A real binding, so the slider follows the option until the first drag replaces it; from
    // then on onOptionValueChanged keeps the two in step by hand.
    value: root.optionValue

    function committedValue(): real {
        return root.integer ? Math.round(root.value) : Number(root.value.toFixed(root.decimals));
    }

    function clamped(value: real): real {
        return Math.min(root.to, Math.max(root.from, value));
    }

    function wouldWrite(): bool {
        if (!root.armed || !root.known) return false;
        if (root.committedValue() === root.optionValue) return false;
        // A value that differs only because this control clamped or rounded what Hyprland
        // reported is not an edit, and writing it would change the setting just by looking.
        if (isFinite(root.reported) && root.value === root.clamped(root.reported)) return false;
        return true;
    }

    function push() {
        if (!root.wouldWrite()) return;
        HyprlandGui.setKey(root.optionKey, root.committedValue());
    }

    // Only the value the handle is left on is staged. Staging on every frame of a drag meant
    // sixty edits a second, and each one rebuilt every map the page reads.
    onValueChanged: {
        if (!root.pressed) root.push();
    }

    onPressedChanged: {
        if (root.pressed) return;
        root.push();
    }
    onOptionValueChanged: {
        if (root.pressed) return;
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
