import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode

/**
 * A menu's rows as ContextMenus.arrange() returns them: EditPanelRows in
 * runs, a run ending at each separator. Comfortable runs are the grouped
 * pills with a gap between groups; compact rows are flat and a separator is
 * a hairline.
 *
 * Entry fields (all optional but id/title):
 *   id, symbol, iconSource, title, subtitle, submenu (chevron), toggle +
 *   checked (switch), selected, destructive, enabled, valueText,
 *   stepper (+ canStepUp / canStepDown), trailing (overrides the kind).
 */
ColumnLayout {
    id: root

    property var rows: []
    // false draws the rows as one run and ignores the separators in them.
    property bool separators: true
    readonly property var shownRows: root.separators ? root.rows : root.rows.filter(r => !r.separator)
    property bool dense: ContextMenus.compact
    property real hostRadius: Appearance.rounding.windowRounding
    property real hostPadding: 8
    // A row index to give keyboard focus to, -1 for none.
    property int focusIndex: -1
    // Id of the row showing its submenu beside the card (cascade).
    property string openId: ""
    // A row that just did its job (a copy) answers in place: a check, this
    // text, the selected fill (ItemContextDialog.confirmAction).
    property string doneId: ""
    property string doneText: ""

    signal activated(var entry, Item row)
    signal stepped(var entry, int delta)
    signal hovered(var entry, Item row)

    readonly property real groupGap: root.dense ? 0 : 8
    spacing: root.dense ? 1 : 3

    // first/last within the run each row belongs to.
    function _isFirst(i: int): bool {
        return i === 0 || root.shownRows[i - 1].separator === true;
    }
    function _isLast(i: int): bool {
        return i === root.shownRows.length - 1 || root.shownRows[i + 1].separator === true;
    }

    // The rows that can take the keyboard, in order (separators skipped),
    // for a host's arrow navigation.
    function focusRows(): var {
        const out = [];
        for (let i = 0; i < repeater.count; i++) {
            const row = repeater.itemAt(i)?.row;
            if (row)
                out.push(row);
        }
        return out;
    }

    Repeater {
        id: repeater
        model: root.shownRows

        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property bool isSeparator: slot.modelData.separator === true
            readonly property Item row: rowLoader.item

            Layout.fillWidth: true
            implicitWidth: slot.isSeparator ? 0 : (rowLoader.item?.implicitWidth ?? 0)
            implicitHeight: slot.isSeparator
                ? (root.dense ? 9 : Math.max(0, root.groupGap - root.spacing * 2))
                : (rowLoader.item?.implicitHeight ?? 0)

            Rectangle {
                visible: slot.isSeparator && root.dense
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.6
            }

            Loader {
                id: rowLoader
                anchors.left: parent.left
                anchors.right: parent.right
                active: !slot.isSeparator
                sourceComponent: EditPanelRow {
                    readonly property var entry: slot.modelData
                    readonly property bool done: root.doneId !== "" && entry.id === root.doneId
                    dense: root.dense
                    hostRadius: root.hostRadius
                    hostPadding: root.hostPadding
                    first: root._isFirst(slot.index)
                    last: root._isLast(slot.index)
                    symbol: done ? "check" : (entry.symbol ?? "")
                    iconSource: done ? "" : (entry.iconSource ?? "")
                    title: done ? root.doneText : (entry.title ?? "")
                    subtitle: entry.subtitle ?? ""
                    valueText: entry.valueText ?? ""
                    selected: done || entry.selected === true
                    highlighted: root.openId !== "" && root.openId === entry.id
                    destructive: entry.destructive === true
                    rowEnabled: entry.enabled !== false
                    switchChecked: entry.checked === true
                    stepUpEnabled: entry.canStepUp !== false
                    stepDownEnabled: entry.canStepDown !== false
                    trailingKind: entry.trailing ?? (entry.stepper ? "stepper"
                        : entry.toggle ? "switch"
                        : entry.submenu ? "chevron"
                        : entry.check ? "check" : "none")
                    focus: root.focusIndex === slot.index
                    onActivated: root.activated(entry, this)
                    onStepUp: root.stepped(entry, 1)
                    onStepDown: root.stepped(entry, -1)
                    onContainsMouseChanged: { if (containsMouse) root.hovered(entry, this); }
                }
            }
        }
    }
}
