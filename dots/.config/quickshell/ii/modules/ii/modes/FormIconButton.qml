import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/** Flat 32 px icon button used on editor rows and in forms. Icon in `buttonIcon`. */
RippleButton {
    id: root
    property string buttonIcon

    implicitWidth: 32
    implicitHeight: 32
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.buttonIcon
        iconSize: 20
        color: Appearance.colors.colOnLayer2
    }
}
