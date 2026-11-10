import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** Back button + title for a Settings sub-page (bind `visible` to its showBackButton). */
RowLayout {
    id: root

    property string title: ""
    signal back()

    spacing: 12

    RippleButton {
        implicitWidth: implicitHeight
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.back()

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.large
        font.family: Appearance.font.family.title
        color: Appearance.colors.colOnLayer0
    }
}
