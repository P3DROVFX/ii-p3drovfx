import QtQuick
import qs.modules.common
import qs.modules.ii.editMode

/**
 * The action list of a dock menu: runs of EditPanelRow, the desktop menu's
 * grouped rows (full rounding at the ends of a run, a tight seam between
 * neighbours), one run per group. Dense (the compact context menus) draws
 * 34 px rows with a hairline between groups.
 *
 * `groups` is an array of arrays of plain action objects:
 *   { id, text, icon, iconSource, subtitle, destructive, enabled, visible,
 *     toggle, checked, selected, chevron, stepper, valueText, canStepUp,
 *     canStepDown }
 *
 * A stepper row answers its two buttons as "<id>:up" and "<id>:down".
 *
 * The height is arithmetic, not a layout's answer. The menu's PopupWindow is
 * sized from it, and a Layout only knows its implicit height after its first
 * polish - a frame after the surface was mapped - so the popup used to map at
 * the wrong size and then re-anchor, which read as the menu arriving late.
 * `naturalWidth`, what the dense rows need, is measured the same way.
 */
Item {
    id: root

    property var groups: []
    property bool dense: false
    property real rowHeight: root.dense ? 34 : 58
    property real rowSpacing: root.dense ? 1 : 3
    property real groupSpacing: root.dense ? 9 : 8
    property real hostRadius: Appearance.rounding.windowRounding
    property real hostPadding: 8
    signal triggered(string actionId)

    readonly property var visibleGroups: (root.groups ?? [])
        .map(group => (group ?? []).filter(action => action && action.visible !== false))
        .filter(group => group.length > 0)
    readonly property int rowCount: root.visibleGroups.reduce((total, group) => total + group.length, 0)

    implicitWidth: 272
    implicitHeight: root.rowCount === 0 ? 0
        : root.rowCount * root.rowHeight
            + (root.rowCount - root.visibleGroups.length) * root.rowSpacing
            + (root.visibleGroups.length - 1) * root.groupSpacing

    // A dense row: 10 + icon 20 + 10 + title + trailing + 8 (EditPanelRow).
    FontMetrics {
        id: titleMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallie + 1
    }
    function _trailingWidth(action): real {
        return action.stepper === true ? 10 + 26 * 2 + 34
            : action.toggle === true ? 10 + 32
            : action.selected === true || action.chevron === true ? 10 + 18 : 0;
    }
    readonly property real naturalWidth: {
        let widest = 0;
        for (const group of root.visibleGroups) {
            for (const action of group) {
                const w = 10 + 20 + 10 + titleMetrics.advanceWidth(action.text ?? "") + root._trailingWidth(action) + 8;
                widest = Math.max(widest, w);
            }
        }
        return widest;
    }

    // Where group `i` ends, by the same arithmetic as the height.
    function _groupBottom(i: int): real {
        let y = 0;
        for (let g = 0; g <= i && g < root.visibleGroups.length; g++) {
            const n = root.visibleGroups[g].length;
            y += n * root.rowHeight + (n - 1) * root.rowSpacing + (g > 0 ? root.groupSpacing : 0);
        }
        return y;
    }

    // Dense: a hairline in the middle of each gap between groups.
    Repeater {
        model: root.dense ? Math.max(0, root.visibleGroups.length - 1) : 0
        delegate: Rectangle {
            required property int index
            x: 8
            y: root._groupBottom(index) + Math.floor(root.groupSpacing / 2)
            width: root.width - 16
            height: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.6
        }
    }

    Column {
        width: root.width
        spacing: root.groupSpacing

        Repeater {
            model: root.visibleGroups

            delegate: Column {
                id: group
                required property var modelData
                width: root.width
                spacing: root.rowSpacing

                Repeater {
                    model: group.modelData

                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        width: group.width
                        height: root.rowHeight
                        implicitHeight: root.rowHeight
                        dense: root.dense
                        hostRadius: root.hostRadius
                        hostPadding: root.hostPadding
                        first: index === 0
                        last: index === group.modelData.length - 1
                        symbol: modelData.iconSource ? "" : (modelData.icon ?? "")
                        iconSource: modelData.iconSource ?? ""
                        title: modelData.text ?? ""
                        subtitle: modelData.subtitle ?? ""
                        destructive: modelData.destructive === true
                        rowEnabled: modelData.enabled !== false
                        trailingKind: modelData.toggle === true ? "switch"
                            : modelData.stepper === true ? "stepper"
                            : modelData.selected === true ? "check"
                            : modelData.chevron === true ? "chevron" : "none"
                        switchChecked: modelData.checked === true
                        selected: modelData.selected === true
                        valueText: modelData.valueText ?? ""
                        stepUpEnabled: modelData.canStepUp !== false
                        stepDownEnabled: modelData.canStepDown !== false
                        onActivated: {
                            if (modelData.stepper !== true)
                                root.triggered(String(modelData.id ?? ""));
                        }
                        onStepUp: root.triggered(String(modelData.id ?? "") + ":up")
                        onStepDown: root.triggered(String(modelData.id ?? "") + ":down")
                    }
                }
            }
        }
    }
}
