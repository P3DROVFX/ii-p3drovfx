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

    // Read from the children, not repeater.itemAt(): in an asynchronously built tree the
    // chips arrive after the count changes, and itemAt() gives null then with nothing to
    // re-run the binding, so the width stuck at 0 and the chips stacked over the row's
    // buttons. `children` notifies as each chip lands.
    readonly property real oneLineWidth: {
        let w = 0;
        let n = 0;
        const kids = root.children;
        for (let i = 0; i < kids.length; ++i) {
            const chip = kids[i];
            if (chip === repeater)
                continue;
            w += chip.implicitWidth + (n++ > 0 ? root.spacing : 0);
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
