import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The dashed "Add …" row at the end of a section.
 */
RippleButton {
    id: addButton

    Layout.fillWidth: true
    implicitHeight: 42
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    DashedBorder {
        anchors.fill: parent
        radius: addButton.buttonRadius
        color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.4)
    }

    contentItem: RowLayout {
        anchors.centerIn: parent
        spacing: 8

        MaterialSymbol {
            text: "add"
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        StyledText {
            text: addButton.buttonText
            font.weight: Font.Medium
            color: Appearance.colors.colPrimary
        }
    }
}
