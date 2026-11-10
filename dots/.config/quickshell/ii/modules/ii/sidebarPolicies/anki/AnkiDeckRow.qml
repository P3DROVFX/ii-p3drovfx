import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A deck in the grouped list: outer corners round, joins tight, the pressed row turns
 * pill and its neighbours follow (RippleButton's dynamic radius). Subdecks indent; the
 * three due counts sit on the right in their queue colours, or a check when done.
 */
RippleButton {
    id: root

    property var deck: ({})
    readonly property int due: (root.deck.new ?? 0) + (root.deck.learn ?? 0) + (root.deck.review ?? 0)

    implicitHeight: 60
    useDynamicRadius: true
    colBackground: ClockStyle.colPane
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active

    contentItem: RowLayout {
        spacing: ClockStyle.gap

        Item {
            implicitWidth: (root.deck.depth ?? 0) * 14
            visible: implicitWidth > 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: ClockStyle.gapSmall
            spacing: -1

            StyledText {
                Layout.fillWidth: true
                text: root.deck.name ?? ""
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: (root.deck.depth ?? 0) === 0 ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal
                color: ClockStyle.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 cards").arg(root.deck.total ?? 0)
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        Row {
            Layout.rightMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapSmall
            visible: root.due > 0

            Repeater {
                model: [
                    { "value": root.deck.new ?? 0, "col": Appearance.m3colors.m3primary },
                    { "value": root.deck.learn ?? 0, "col": Appearance.m3colors.m3tertiary },
                    { "value": root.deck.review ?? 0, "col": ClockStyle.colOnSurfaceVariant }
                ]
                StyledText {
                    required property var modelData
                    visible: modelData.value > 0
                    text: modelData.value
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    color: modelData.col
                }
            }
        }

        MaterialSymbol {
            Layout.rightMargin: ClockStyle.gap
            visible: root.due === 0
            text: "check_circle"
            iconSize: 20
            color: ClockStyle.colSubtext
        }
    }
}
