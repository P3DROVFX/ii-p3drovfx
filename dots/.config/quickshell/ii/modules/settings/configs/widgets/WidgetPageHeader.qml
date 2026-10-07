import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * A desktop widget page's top line: the back key and the page's title.
 */
RowLayout {
    id: root

    property string title
    signal back

    spacing: 12

    RippleButton {
        implicitWidth: implicitHeight
        implicitHeight: 40
        topLeftRadius: Appearance.rounding.full
        topRightRadius: Appearance.rounding.full
        bottomLeftRadius: Appearance.rounding.full
        bottomRightRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSecondaryContainer
        }

        onClicked: root.back()
    }

    StyledText {
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.large
        font.family: Appearance.font.family.title
        color: Appearance.colors.colOnLayer0
    }
}
