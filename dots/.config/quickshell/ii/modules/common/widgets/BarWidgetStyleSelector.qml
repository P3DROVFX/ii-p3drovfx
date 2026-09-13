import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Compact style picker used by each Bar settings row.
//
// This used to lay every style out as a pill inside a nested horizontal
// Flickable, which cost a clip node per row inside an already nested scroll
// view and grew wider with every style added - the Workspaces row was already
// clipping its last option. A single chip that opens a menu has a fixed width
// no matter how many styles exist, and keeps the choice one overlay away
// instead of behind a sub-page.
StyledComboBox {
    id: root

    property string styleConfigKey: ""
    property list<var> styleOptions: []
    // Not `currentValue`: ComboBox declares that one FINAL and read-only.
    property string selectedValue: "default"

    signal selected(var newValue)

    // Widened for the longest option this widget offers rather than the one
    // currently picked, so choosing a style never reflows the row it sits in.
    // An approximation is enough here: the label elides, and the only cost of
    // being off is a slightly roomy chip.
    readonly property int longestOptionLength: {
        let longest = 0;
        for (const option of root.styleOptions)
            longest = Math.max(longest, String(option?.displayName ?? option?.value ?? "").length);
        return longest;
    }

    model: root.styleOptions
    textRole: "displayName"
    valueRole: "value"

    // ComboBox writes currentIndex itself on activation, which would break a
    // plain binding and leave the chip stale on the next external change.
    Binding {
        target: root
        property: "currentIndex"
        value: {
            // `indexOfValue()` reads the ComboBox model internally. During
            // Loader construction it can run before `styleOptions` has been
            // assigned, leaving currentIndex at 0 (the Default option) for
            // the lifetime of the selector. Read the options explicitly so
            // the binding depends on the model supplied by the caller.
            const selected = String(root.selectedValue ?? "default");
            for (let i = 0; i < root.styleOptions.length; ++i) {
                if (String(root.styleOptions[i]?.value ?? "default") === selected)
                    return i;
            }
            return root.styleOptions.length > 0 ? 0 : -1;
        }
        restoreMode: Binding.RestoreBindingOrValue
    }

    // The list row is only 48px tall, so this sits below the page-body combo size.
    implicitHeight: 32
    implicitWidth: Math.round(root.longestOptionLength * Appearance.font.pixelSize.small * 0.62) + 84
    Layout.fillWidth: false
    Layout.preferredWidth: root.implicitWidth

    font.pixelSize: Appearance.font.pixelSize.small
    buttonRadius: Appearance.rounding.small
    popupWidth: Math.max(root.implicitWidth, 172)

    onActivated: index => {
        const option = root.styleOptions[index];
        if (!option || option.enabled === false)
            return;
        root.selected(String(option.value ?? "default"));
    }
}
