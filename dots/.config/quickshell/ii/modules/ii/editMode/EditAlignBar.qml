import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The selection's own toolbar: align and distribute, over whatever is picked.
 *
 * It appears only for two or more widgets, because that is the fewest a line
 * can be made of, and its distribute half needs three - the two ends of a
 * distribution are held where they are, so with nothing between them there is
 * nothing to place. Rather than hiding those two, they disable: a control that
 * comes and goes moves every other control on the row with it, and the row is
 * centred on the selection, so the whole thing would slide under the pointer
 * as a third widget is picked.
 *
 * Drawn on the widgets surface rather than on the chrome's, unlike the widget
 * menu. The menu is summoned at a pointer that can be anywhere, including over
 * the bar; this belongs to a rectangle that is always inside the card, which
 * the bar and the dock are inset away from by construction. Staying on the
 * canvas means it shares the widgets' coordinate space and follows a group
 * drag with no mapping at all - it only has to undo the mode's shrink, which
 * is one number.
 */
Item {
    id: root

    property int count: 0
    readonly property bool canDistribute: root.count >= 3

    signal requested(string mode)

    implicitWidth: bar.implicitWidth
    implicitHeight: bar.implicitHeight

    readonly property var alignModes: [
        { "mode": "left", "symbol": "align_horizontal_left", "label": Translation.tr("Align left") },
        { "mode": "hcenter", "symbol": "align_horizontal_center", "label": Translation.tr("Align centre") },
        { "mode": "right", "symbol": "align_horizontal_right", "label": Translation.tr("Align right") },
        { "mode": "top", "symbol": "align_vertical_top", "label": Translation.tr("Align top") },
        { "mode": "vcenter", "symbol": "align_vertical_center", "label": Translation.tr("Align middle") },
        { "mode": "bottom", "symbol": "align_vertical_bottom", "label": Translation.tr("Align bottom") }
    ]
    readonly property var distributeModes: [
        { "mode": "hdistribute", "symbol": "align_justify_space_even", "label": Translation.tr("Even gaps across") },
        { "mode": "vdistribute", "symbol": "align_space_even", "label": Translation.tr("Even gaps down") }
    ]

    // The pill's own padding is part of the toolbar, not a hole through it.
    // Without this a press between two buttons reaches the canvas underneath,
    // which reads it as the start of a marquee and clears the very selection
    // the toolbar is about.
    MouseArea {
        anchors.fill: bar
        acceptedButtons: Qt.AllButtons
    }

    Toolbar {
        id: bar
        anchors.centerIn: parent
        padding: 5
        spacing: 2
        implicitHeight: 44

        Repeater {
            model: root.alignModes

            delegate: AlignButton {
                required property var modelData
                symbol: modelData.symbol
                label: modelData.label
                mode: modelData.mode
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 3
            Layout.rightMargin: 3
            implicitWidth: 1
            implicitHeight: 18
            color: Appearance.colors.colOutlineVariant
        }

        Repeater {
            model: root.distributeModes

            delegate: AlignButton {
                required property var modelData
                symbol: modelData.symbol
                label: modelData.label
                mode: modelData.mode
                enabled: root.canDistribute
            }
        }
    }

    component AlignButton: IconToolbarButton {
        id: button
        property string mode: ""
        property string label: ""

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 34
        implicitHeight: 34
        iconSize: 20
        onClicked: root.requested(button.mode)

        StyledToolTip {
            requireOverlay: false
            text: button.enabled ? button.label
                : Translation.tr("Pick a third widget to spread them out")
        }
    }
}
