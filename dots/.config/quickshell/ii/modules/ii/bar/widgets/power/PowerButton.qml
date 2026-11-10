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

    // Fills the group's pill (the registry makes this widget paddingless): the
    // plate across the bar, the old padded length along it. The corners follow
    // the group's, so hover and active take the pill's own shape.
    readonly property real plate: root.vertical
        ? Appearance.sizes.baseVerticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property real length: Math.round(42 * root.contentScale)
    implicitWidth: root.vertical ? root.plate : root.length
    implicitHeight: root.vertical ? root.length : root.plate

    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full
    topLeftRadius: startRadius
    bottomLeftRadius: root.vertical ? endRadius : startRadius
    topRightRadius: root.vertical ? startRadius : endRadius
    bottomRightRadius: endRadius
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