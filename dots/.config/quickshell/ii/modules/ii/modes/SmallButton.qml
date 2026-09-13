import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/** Tonal pill button for a form ("Add", "Use current"). Text in `buttonText`. */
RippleButton {
    id: root

    implicitHeight: 36
    implicitWidth: label.implicitWidth + 28
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive

    contentItem: StyledText {
        id: label
        text: root.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colOnSecondaryContainer
    }
}
