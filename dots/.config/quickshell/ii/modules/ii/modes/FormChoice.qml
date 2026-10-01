pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * A one-of-several choice for a form, as a row of the clock's filter chips: the picked
 * one fills with the secondary container and squares off. `current` in, `picked(value)`
 * out; `options` is [{ displayName, value }].
 *
 * The chips wrap when the row is narrow. The preferred width is the one-line width, so a
 * layout that does not fill gives the choice exactly the room of its chips.
 */
Flow {
    id: root

    property var current
    property var options: []

    signal picked(var value)

    readonly property real oneLineWidth: {
        let w = 0;
        for (let i = 0; i < repeater.count; ++i) {
            const chip = repeater.itemAt(i);
            if (chip)
                w += chip.implicitWidth + (i > 0 ? root.spacing : 0);
        }
        return w;
    }

    Layout.fillWidth: true
    Layout.preferredWidth: root.oneLineWidth
    spacing: ClockStyle.gapTiny + 2

    Repeater {
        id: repeater
        model: root.options

        ClockChip {
            required property var modelData
            height_: 32
            label: String(modelData.displayName ?? modelData.label ?? modelData.value)
            symbol: root.current == modelData.value ? "check" : ""
            selected: root.current == modelData.value
            enabled: modelData.enabled !== false
            opacity: enabled ? 1 : 0.5
            onClicked: root.picked(modelData.value)
        }
    }
}
