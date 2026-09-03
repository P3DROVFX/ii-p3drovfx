pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The vertical picker the first Welcome steps are built from.
 *
 * These lists used to run with `clip: false`, and for a good reason: a row
 * grows under the pointer, and a clipped list shaves that growth off against
 * its own wall. Unclipped, though, a ListView also paints the rows just past
 * its end — so on the language and layout steps the next row landed on top of
 * the card below the list.
 *
 * The rows are inset by the room their growth needs instead. The growth then
 * happens inside the clip rather than against it: the list keeps its own
 * edges, and the pointer still gets a row at full size.
 *
 * Each entry of `choices` carries `value` and `label`, and may carry `icon`
 * and `secondaryLabel`.
 */
Item {
    id: root

    required property var choices
    property string currentValue: ""
    /** Dimmed while another control on the page owns the choice. */
    property bool dimmed: false

    signal chosen(string value)

    /**
     * RippleButton grows to 1.01 under the pointer, so a full-width row
     * overflows its list by half a percent of its own width on each side.
     * The inset covers exactly that, with a floor for the narrow lists where
     * half a percent rounds down to nothing worth reserving.
     */
    readonly property real hoverHeadroom: Math.max(Appearance.rounding.verysmall,
        Math.ceil(root.width * 0.005))

    StyledListView {
        id: list

        anchors.fill: parent
        clip: true
        spacing: Appearance.rounding.verysmall
        // The ends carry the same headroom, so the first and last rows can
        // grow once the list is scrolled all the way to them.
        topMargin: root.hoverHeadroom
        bottomMargin: root.hoverHeadroom
        // The rows arrive with the page. A second stagger on top of the page
        // transition reads as the list lagging behind its own header.
        animatePopulate: false
        model: root.choices

        // The row is a plain wrapper and the button sits inset inside it.
        // StyledListView's entrance transitions write `x` and `scale` on the
        // delegate root, which on a RippleButton would land on the very
        // properties its hover state is bound to and leave the row unable to
        // grow at all.
        delegate: Item {
            id: choiceRow

            required property var modelData

            width: list.width
            implicitHeight: Appearance.rounding.large * 2.5
            height: implicitHeight

            RippleButton {
                id: choiceButton

                anchors.fill: parent
                anchors.leftMargin: root.hoverHeadroom
                anchors.rightMargin: root.hoverHeadroom
                buttonRadius: Appearance.rounding.normal
                toggled: !root.dimmed && root.currentValue === choiceRow.modelData.value
                opacity: root.dimmed ? 0.55 : 1
                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: toggled ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                colBackgroundActive: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                colRipple: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                Accessible.name: choiceRow.modelData.label

                readonly property color foreground: choiceButton.toggled
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer1

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Appearance.rounding.normal
                    anchors.rightMargin: Appearance.rounding.normal
                    spacing: Appearance.rounding.small

                    MaterialSymbol {
                        visible: text.length > 0
                        text: choiceRow.modelData.icon ?? ""
                        iconSize: Appearance.font.pixelSize.large
                        color: choiceButton.foreground
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: choiceRow.modelData.label
                            color: choiceButton.foreground
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: choiceButton.toggled ? Font.Bold : Font.DemiBold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: text.length > 0
                            Layout.fillWidth: true
                            text: choiceRow.modelData.secondaryLabel ?? ""
                            color: choiceButton.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }
                    }

                    MaterialSymbol {
                        visible: choiceButton.toggled
                        text: "check"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimary
                    }
                }

                onClicked: root.chosen(choiceRow.modelData.value)
            }
        }
    }
}
