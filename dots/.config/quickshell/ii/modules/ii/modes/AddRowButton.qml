import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * The "Add …" row at the end of a section: the dashed pill the clock's side sheets use
 * for the action that adds rather than commits. Label in `buttonText`.
 */
RippleButton {
    id: addButton

    Layout.fillWidth: true
    Layout.topMargin: 3
    implicitHeight: 46
    buttonRadius: ClockStyle.pill(46)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: "transparent"
    colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.08)
    colRipple: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.16)

    DashedBorder {
        anchors.fill: parent
        radius: addButton.buttonRadius
        color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.7)
        borderWidth: 1
        dashLength: 5
        gapLength: 4
    }

    contentItem: Item {
        implicitWidth: addLabelRow.implicitWidth
        implicitHeight: addLabelRow.implicitHeight

        RowLayout {
            id: addLabelRow
            anchors.centerIn: parent
            spacing: ClockStyle.gapSmall

            MaterialSymbol {
                text: "add"
                iconSize: ClockStyle.iconSmall + 4
                color: ClockStyle.colPrimary
            }

            StyledText {
                text: addButton.buttonText
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: ClockStyle.colPrimary
            }
        }
    }
}
