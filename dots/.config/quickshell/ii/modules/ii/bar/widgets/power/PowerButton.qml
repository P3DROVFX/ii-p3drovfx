import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property bool vertical: false

    property real buttonPadding: 5
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    implicitWidth: Math.round((BarInteraction.cornerStyle === 2 ? 27 : 27 + buttonPadding) * root.contentScale)
    implicitHeight: Math.round((BarInteraction.cornerStyle === 2 ? 27 : 27 + buttonPadding) * root.contentScale)
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    onPressed: {
        GlobalStates.sessionOpen = !GlobalStates.sessionOpen
    }
    MaterialSymbol {
        anchors.centerIn: parent
        text: "power_settings_new"
        iconSize: Math.round(Appearance.font.pixelSize.larger * root.contentScale)
        color: Appearance.colors.colOnLayer0
    }
}