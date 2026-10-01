import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick

/**
 * Tonal pill for a form ("Add", "Use current"): the clock's tonal button at chip height.
 * Text in `buttonText`; squares off while pressed like every clock button.
 */
RippleButton {
    id: root

    implicitHeight: 34
    implicitWidth: label.implicitWidth + ClockStyle.gapLarge * 2
    buttonRadius: ClockStyle.pill(34)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: ClockStyle.colSecondaryContainer
    colBackgroundHover: ClockStyle.colSecondaryContainerHover
    colRipple: ClockStyle.colSecondaryContainerActive

    contentItem: StyledText {
        id: label
        text: root.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: ClockStyle.textNormal
        font.weight: Font.DemiBold
        color: ClockStyle.colOnSecondaryContainer
    }
}
