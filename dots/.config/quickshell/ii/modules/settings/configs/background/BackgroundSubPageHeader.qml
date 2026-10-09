import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** The back button and title every sub-page opens with. */
RowLayout {
    id: root

    readonly property real buttonSize: 40
    readonly property real headerSpacing: 12

    property string title: ""

    signal backRequested()

    spacing: root.headerSpacing

    RippleButton {
        implicitWidth: root.buttonSize
        implicitHeight: root.buttonSize
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        onClicked: root.backRequested()

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    StyledText {
        text: root.title
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.large
        color: Appearance.colors.colOnLayer0
    }
}
