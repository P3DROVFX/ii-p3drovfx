pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A formatted figure ("3 h 12 min", "12.4 Wh", "76 %") set like the clock's digits:
 * the numbers in tall condensed bold, each unit small beside it on the same baseline,
 * so the eye lands on the amount and the unit only qualifies it.
 */
RowLayout {
    id: root

    /// Space-separated as UsageFormat writes it: numbers and units alternate.
    property string text: ""
    property real size: 64
    property color color: ClockStyle.colOnSurface
    property var axes: ClockStyle.axesDigitsBold

    readonly property var parts: root.text.split(" ").filter(part => part.length > 0)

    // A layout inside a layout fills by default, which spread the units away from
    // their numbers; the figure keeps its own width unless told otherwise.
    Layout.fillWidth: false
    spacing: 0

    Repeater {
        model: root.parts

        StyledText {
            id: part
            required property string modelData
            required property int index
            readonly property bool isNumber: /^[<>+\-−—.,0-9]/.test(part.modelData)

            Layout.alignment: Qt.AlignBaseline
            Layout.leftMargin: part.index === 0 ? 0 : (part.isNumber ? root.size * 0.16 : root.size * 0.06)
            text: part.modelData
            font.family: ClockStyle.fontMain
            font.variableAxes: part.isNumber ? root.axes : ClockStyle.axesDigits
            font.pixelSize: part.isNumber ? root.size : Math.round(Math.max(14, root.size * 0.34))
            color: root.color
            opacity: part.isNumber ? 1 : 0.85
        }
    }
}
