import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * A labelled pill for an editor's footer (Duplicate, Delete…), in the clock button's
 * emphasis levels: tonal by default, `danger` takes the error container, and `filled`
 * makes it the confirming one.
 */
RippleButton {
    id: footerButton

    property string buttonIcon: ""
    property bool danger: false
    property bool filled: false

    readonly property color fg: footerButton.filled
        ? (footerButton.danger ? ClockStyle.colOnError : ClockStyle.colOnPrimary)
        : (footerButton.danger ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer)

    implicitHeight: ClockStyle.buttonHeight - 4
    implicitWidth: footerRow.implicitWidth + ClockStyle.gapHuge * 1.5
    buttonRadius: ClockStyle.pill(implicitHeight)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: footerButton.filled
        ? (footerButton.danger ? ClockStyle.colError : ClockStyle.colPrimary)
        : (footerButton.danger ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer)
    colBackgroundHover: footerButton.filled
        ? (footerButton.danger ? Appearance.colors.colErrorHover : ClockStyle.colPrimaryHover)
        : (footerButton.danger ? ClockStyle.colErrorContainerHover : ClockStyle.colSecondaryContainerHover)
    colRipple: footerButton.filled
        ? (footerButton.danger ? Appearance.colors.colErrorActive : ClockStyle.colPrimaryActive)
        : (footerButton.danger ? Appearance.colors.colErrorContainerActive : ClockStyle.colSecondaryContainerActive)

    contentItem: Item {
        implicitWidth: footerRow.implicitWidth
        implicitHeight: footerRow.implicitHeight

        RowLayout {
            id: footerRow
            anchors.centerIn: parent
            spacing: ClockStyle.gapSmall - 2

            MaterialSymbol {
                visible: footerButton.buttonIcon.length > 0
                text: footerButton.buttonIcon
                iconSize: ClockStyle.iconSmall + 2
                color: footerButton.fg
            }

            StyledText {
                text: footerButton.buttonText
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: footerButton.fg
            }
        }
    }
}
