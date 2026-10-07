import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/*
 * A transport button for the Poster, Deck and Halo widgets. Hover and press are
 * the fill tinted with its own content colour (8 % / 16 %), the M3E card action
 * recipe. `restRadius` is the corner the caller morphs to show state: a pill
 * while paused, a rounded square while playing.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property color colFill: "gray"
    property color colContent: "white"
    property real symbolSize: 26
    property real labelSize: Appearance.font.pixelSize.huge
    property real restRadius: Math.min(width, height) / 2

    colBackground: root.colFill
    colBackgroundHover: ColorUtils.mix(root.colContent, root.colFill, 0.08)
    colBackgroundActive: ColorUtils.mix(root.colContent, root.colFill, 0.16)
    colRipple: ColorUtils.mix(root.colContent, root.colFill, 0.24)
    buttonRadius: root.restRadius

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.symbol !== ""
                text: root.symbol
                fill: 1
                iconSize: root.symbolSize
                color: root.colContent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.label !== ""
                // Long translations shrink to the key instead of spilling out of it.
                width: Math.min(implicitWidth, root.width - (root.symbol !== "" ? root.symbolSize + 8 : 0) - 28)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                text: root.label
                color: root.colContent
                font.family: Appearance.font.family.main
                font.pixelSize: root.labelSize
                font.variableAxes: ({ "wght": 560, "wdth": 110, "ROND": 100 })
                font.letterSpacing: 1
            }
        }
    }
}
