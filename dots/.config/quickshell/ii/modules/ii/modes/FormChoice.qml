import qs.modules.common.widgets
import QtQuick

/** Segmented choice for a form: `current` in, `picked(value)` out. */
ConfigSelectionArray {
    id: root
    property var current
    signal picked(var value)
    currentValue: root.current
    onSelected: value => root.picked(value)
}
