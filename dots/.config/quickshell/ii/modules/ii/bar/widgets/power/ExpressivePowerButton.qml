import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : Appearance.sizes.baseBarHeight - 8
    implicitHeight: vertical ? Appearance.sizes.verticalBarWidth - 8 : Appearance.sizes.baseBarHeight - 8

    // The plate already follows the bar; without this the symbol inside does not, and a
    // taller bar just puts more empty circle around the same small glyph.
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    BarWidgetPalette {
        id: palette
        colorMode: Config.options.bar.power.colorMode
    }

    RippleButton {
        anchors.fill: parent
        buttonRadius: Appearance.rounding.full
        colBackground: palette.colBackground
        colBackgroundHover: palette.colBackgroundHover
        colRipple: palette.colBackgroundActive
        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen
        }

        MaterialShapeWrappedMaterialSymbol {
            anchors.centerIn: parent
            text: "power_settings_new"
            iconSize: Math.round((root.vertical ? 18 : Appearance.font.pixelSize.normal) * root.contentScale)
            color: palette.colOnBackground
            colSymbol: palette.colBackground
            shape: MaterialShape.Shape.Cookie12Sided
            padding: Math.round((root.vertical ? 5 : 2) * root.contentScale)
        }
    }
}
