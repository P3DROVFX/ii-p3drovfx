import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A pill button for the editor footer (Duplicate, Delete…). `danger`
 * paints it in the error colour, `filled` makes it the confirming one.
 */
RippleButton {
    id: footerButton
    property string buttonIcon: ""
    property bool danger: false
    property bool filled: false

    readonly property color fg: danger ? (filled ? Appearance.colors.colOnError : Appearance.colors.colError)
        : Appearance.colors.colOnLayer2

    implicitHeight: 38
    implicitWidth: footerRow.implicitWidth + 28
    buttonRadius: Appearance.rounding.full
    colBackground: filled ? Appearance.colors.colError : Appearance.colors.colLayer2
    colBackgroundHover: filled ? Appearance.colors.colErrorHover : Appearance.colors.colLayer2Hover
    colRipple: filled ? Appearance.colors.colErrorActive : Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        id: footerRow
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            visible: footerButton.buttonIcon.length > 0
            text: footerButton.buttonIcon
            iconSize: 18
            color: footerButton.fg
        }

        StyledText {
            text: footerButton.buttonText
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: footerButton.fg
        }
    }
}
